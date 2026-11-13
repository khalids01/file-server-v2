defmodule AppWeb.FileApiController do
  use AppWeb, :controller
  require Ash.Query
  alias App.Storage.StoredFile
  alias AppWeb.ApiError

  def index(conn, params) do
    with {:ok, page} <- integer(params["page"], 1, 100_000),
         {:ok, limit} <- integer(params["limit"], 20, 100),
         true <- Enum.all?(Map.keys(params), &(&1 in ["page", "limit", "search"])),
         search when is_binary(search) and byte_size(search) <= 200 <-
           Map.get(params, "search", "") do
      auth = conn.assigns.application_auth
      query = StoredFile |> Ash.Query.filter(application_id == ^auth.application.id)

      query =
        if search == "", do: query, else: Ash.Query.filter(query, contains(filename, ^search))

      total = Ash.count!(query, actor: auth.user)

      files =
        query
        |> Ash.Query.sort(created_at: :desc, id: :desc)
        |> Ash.Query.offset((page - 1) * limit)
        |> Ash.Query.limit(limit)
        |> Ash.read!(actor: auth.user)

      pages = ceil(total / limit)

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
          "Use page >= 1, limit 1–100 and an optional search up to 200 bytes."
        )
    end
  end

  def create(conn, params) do
    case {Map.keys(params), params["file"]} do
      {["file"], %Plug.Upload{} = upload} ->
        try do
          create_upload(conn, upload)
        after
          File.rm(upload.path)
        end

      _ ->
        ApiError.send(
          conn,
          400,
          "INVALID_UPLOAD",
          "Send exactly one file field. Application and storage come from the credential's application."
        )
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, file} <- scoped_file(conn, id),
         do: json(conn, %{data: serialize(file)}),
         else: (_ -> not_found(conn))
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, file} <- scoped_file(conn, id) do
      case App.Storage.delete(conn.assigns.application_auth.user, file.id) do
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
         {:ok, download} <- App.Storage.download(conn.assigns.application_auth.user, file.id) do
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

  defp create_upload(conn, upload) do
    case File.stat(upload.path) do
      {:ok, %{size: size}} when size > 0 ->
        if size > App.Storage.max_file_size() do
          ApiError.send(
            conn,
            413,
            "FILE_TOO_LARGE",
            "File exceeds the configured size limit."
          )
        else
          auth = conn.assigns.application_auth

          case App.Storage.upload(
                 auth.user,
                 auth.application.id,
                 upload.path,
                 upload.filename,
                 upload.content_type
               ) do
            {:ok, file} ->
              conn |> put_status(201) |> json(%{data: serialize(file)})

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

    with {:ok, %StoredFile{application_id: app_id} = file} <-
           Ash.get(StoredFile, id, actor: auth.user),
         true <- app_id == auth.application.id,
         do: {:ok, file},
         else: (_ -> {:error, :not_found})
  end

  defp not_found(conn), do: ApiError.send(conn, 404, "FILE_NOT_FOUND", "File not found.")

  defp serialize(file),
    do: %{
      id: file.id,
      applicationId: file.application_id,
      filename: file.filename,
      contentType: file.content_type,
      sizeBytes: file.size,
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
end
