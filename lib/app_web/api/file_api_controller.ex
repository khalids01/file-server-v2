defmodule AppWeb.FileApiController do
  use AppWeb, :controller
  require Ash.Query
  alias App.Storage
  alias App.Storage.StoredFile
  alias AppWeb.ApiError

  @index_params ~w(page limit search tags tags[])

  def index(conn, params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @index_params)),
         {:ok, page} <- integer(params["page"], 1, 100_000),
         {:ok, limit} <- integer(params["limit"], 20, 100),
         {:ok, search} <- parse_search(params["search"]),
         {:ok, tags} <- parse_filter_tags(params) do
      auth = conn.assigns.application_auth
      query = StoredFile |> Ash.Query.filter(application_id == ^auth.application.id)

      query =
        if search == "", do: query, else: Ash.Query.filter(query, contains(filename, ^search))

      query =
        Enum.reduce(tags, query, fn tag, acc ->
          Ash.Query.filter(
            acc,
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS t(value) WHERE lower(t.value) = lower(?))",
              tags,
              ^tag
            )
          )
        end)

      total = Ash.count!(query, actor: auth.user)
      pages = ceil(total / limit)

      files =
        query
        |> Ash.Query.sort(created_at: :desc, id: :desc)
        |> Ash.Query.offset((page - 1) * limit)
        |> Ash.Query.limit(limit)
        |> Ash.read!(actor: auth.user)

      json(conn, %{
        data: Enum.map(files, &serialize/1),
        pagination: %{
          page: page,
          limit: limit,
          total: total,
          pages: pages,
          hasNext: page < pages,
          hasPrev: page > 1
        }
      })
    else
      _ ->
        ApiError.send(
          conn,
          400,
          "INVALID_QUERY",
          "Use page >= 1, limit 1-100, optional search up to 200 bytes, and optional tags[] filters."
        )
    end
  end

  def create(conn, params) do
    case {Enum.sort(Map.keys(params)), params["file"]} do
      {["file"], %Plug.Upload{} = upload} ->
        with_upload(conn, upload, nil)

      {["file", "tags"], %Plug.Upload{} = upload} ->
        with_upload(conn, upload, params["tags"])

      _ ->
        cleanup_upload(params)
        invalid_upload(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, file} <- scoped_file(conn, id),
         do: json(conn, %{data: serialize(file)}),
         else: (_ -> not_found(conn))
  end

  def update(conn, %{"id" => id} = params) do
    case {Map.keys(params) |> Enum.reject(&(&1 == "id")) |> Enum.sort(), params["tags"]} do
      {["tags"], tags} when is_list(tags) ->
        auth = conn.assigns.application_auth

        case Storage.update_tags(auth.user, auth.application.id, id, tags) do
          {:ok, file} ->
            json(conn, %{data: serialize(file)})

          {:error, {:invalid_tags, message}} ->
            ApiError.send(conn, 400, "INVALID_TAGS", message)

          {:error, :not_found} ->
            not_found(conn)

          _ ->
            ApiError.send(conn, 503, "STORAGE_UNAVAILABLE", "Unable to update file tags.")
        end

      _ ->
        ApiError.send(conn, 400, "INVALID_TAGS", "Provide a JSON object with a tags array.")
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, file} <- scoped_file(conn, id) do
      case Storage.delete(conn.assigns.application_auth.user, file.id) do
        :ok ->
          json(conn, %{data: %{id: file.id, deleted: true}})

        _ ->
          ApiError.send(
            conn,
            503,
            "STORAGE_UNAVAILABLE",
            "Unable to delete this file. Please try again later."
          )
      end
    else
      _ -> not_found(conn)
    end
  end

  def content(conn, %{"id" => id}) do
    with {:ok, file} <- scoped_file(conn, id),
         {:ok, download} <- Storage.download(conn.assigns.application_auth.user, file.id) do
      try do
        conn
        |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
        |> send_download({:file, download.path},
          filename: download.filename,
          content_type: "application/octet-stream",
          disposition: :attachment
        )
      after
        if download.temporary?, do: File.rm(download.path)
      end
    else
      _ -> not_found(conn)
    end
  end

  defp with_upload(conn, upload, tags) do
    try do
      create_upload(conn, upload, tags)
    after
      File.rm(upload.path)
    end
  end

  defp create_upload(conn, upload, tags) do
    case File.stat(upload.path) do
      {:ok, %{size: size}} when size > 0 ->
        if size > Storage.max_file_size() do
          ApiError.send(conn, 413, "FILE_TOO_LARGE", "File exceeds the configured size limit.")
        else
          auth = conn.assigns.application_auth

          case Storage.upload(
                 auth.user,
                 auth.application.id,
                 upload.path,
                 upload.filename,
                 upload.content_type,
                 tags: tags
               ) do
            {:ok, file} ->
              conn |> put_status(201) |> json(%{data: serialize(file)})

            {:error, {:invalid_tags, message}} ->
              ApiError.send(conn, 400, "INVALID_TAGS", message)

            _ ->
              ApiError.send(
                conn,
                503,
                "STORAGE_UNAVAILABLE",
                "Unable to store this file. Check the application's storage connection."
              )
          end
        end

      _ ->
        ApiError.send(conn, 400, "INVALID_UPLOAD", "Send one non-empty file.")
    end
  end

  defp scoped_file(conn, id) do
    auth = conn.assigns.application_auth

    case Ash.get(StoredFile, id, actor: auth.user) do
      {:ok, %StoredFile{application_id: app_id} = file} when app_id == auth.application.id ->
        {:ok, file}

      _ ->
        {:error, :not_found}
    end
  rescue
    _ in [Ash.Error.Invalid, Ash.Error.Query.NotFound, Ecto.Query.CastError, ArgumentError] ->
      {:error, :not_found}

    _ ->
      {:error, :not_found}
  end

  defp not_found(conn), do: ApiError.send(conn, 404, "FILE_NOT_FOUND", "File not found.")

  defp cleanup_upload(params) do
    case params["file"] do
      %Plug.Upload{path: path} -> File.rm(path)
      _ -> :ok
    end
  end

  defp invalid_upload(conn),
    do:
      ApiError.send(
        conn,
        400,
        "INVALID_UPLOAD",
        "Send exactly one file field and optional tags JSON. Application and storage come from the credential's application."
      )

  defp serialize(file),
    do: %{
      id: file.id,
      applicationId: file.application_id,
      filename: file.filename,
      contentType: file.content_type,
      sizeBytes: file.size,
      tags: file.tags || [],
      createdAt: DateTime.to_iso8601(file.created_at),
      urls: %{content: "/api/v2/files/#{file.id}/content"}
    }

  defp integer(nil, default, _), do: {:ok, default}

  defp integer(value, _, max) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 and n <= max -> {:ok, n}
      _ -> :error
    end
  end

  defp integer(_, _, _), do: :error

  defp parse_search(nil), do: {:ok, ""}
  defp parse_search(value) when is_binary(value) and byte_size(value) <= 200, do: {:ok, value}
  defp parse_search(_), do: :error

  defp parse_filter_tags(params) do
    case {Map.get(params, "tags"), Map.get(params, "tags[]")} do
      {nil, nil} ->
        {:ok, []}

      {tags, nil} when is_list(tags) ->
        Storage.validate_tags_filter(tags)

      {nil, tag} when is_binary(tag) ->
        Storage.validate_tags_filter([tag])

      {nil, tags} when is_list(tags) ->
        Storage.validate_tags_filter(tags)

      _ ->
        :error
    end
  end
end
