defmodule AppWeb.UploadParser do
  @moduledoc "Bounded multipart parsing for authenticated API uploads and tag updates."
  alias AppWeb.ApiError
  @json_tag_limit 65_536

  def init(opts), do: opts

  def call(%{method: "POST", path_info: ["api", "v2", "files"]} = conn, _) do
    limit = App.Storage.max_file_size() + 1_048_576
    parse_with_length(conn, limit, &parse_multipart(&1, limit), :upload)
  end

  def call(%{method: "PATCH", path_info: ["api", "v2", "files", _id]} = conn, _) do
    parse_with_length(conn, @json_tag_limit, &parse_json_tags/1, :tags)
  end

  def call(conn, _), do: conn

  defp parse_with_length(conn, limit, parser, kind) do
    case Plug.Conn.get_req_header(conn, "content-length") do
      [length] ->
        case Integer.parse(length) do
          {n, ""} when n > limit ->
            too_large(conn, kind)

          {n, ""} when n >= 0 ->
            parser.(conn)

          _ ->
            invalid_request(conn, kind)
        end

      [] ->
        parser.(conn)

      _ ->
        invalid_request(conn, kind)
    end
  end

  defp parse_multipart(conn, limit) do
    Plug.Parsers.call(
      conn,
      Plug.Parsers.init(
        parsers: [:multipart],
        length: limit,
        read_length: 65_536,
        multipart_to_params: {__MODULE__, :multipart_to_params, []}
      )
    )
  rescue
    Plug.Parsers.RequestTooLargeError ->
      too_large(conn, :upload)

    Plug.Parsers.UnsupportedMediaTypeError ->
      ApiError.send(conn, 415, "INVALID_UPLOAD", "Use multipart/form-data with one file field.")

    ArgumentError ->
      invalid_multipart(conn)

    _ in [Plug.Parsers.ParseError, Plug.Parsers.BadEncodingError, Plug.UploadError] ->
      invalid_multipart(conn)
  catch
    {:api_error, status, code, message} ->
      ApiError.send(conn, status, code, message)
  end

  defp parse_json_tags(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [content_type] ->
        case Plug.Conn.Utils.media_type(content_type) do
          {:ok, "application", "json", _} -> read_json_tags(conn, "")
          _ -> ApiError.send(conn, 415, "INVALID_BODY", "Use application/json.")
        end

      _ ->
        ApiError.send(conn, 415, "INVALID_BODY", "Use application/json.")
    end
  end

  defp read_json_tags(conn, acc) when byte_size(acc) > @json_tag_limit, do: too_large(conn, :tags)

  defp read_json_tags(conn, acc) do
    case Plug.Conn.read_body(conn, length: @json_tag_limit, read_length: @json_tag_limit) do
      {:ok, body, conn} ->
        body = acc <> body

        if byte_size(body) > @json_tag_limit,
          do: too_large(conn, :tags),
          else: decode_json_tags(conn, body)

      {:more, body, conn} ->
        body = acc <> body

        if byte_size(body) > @json_tag_limit,
          do: too_large(conn, :tags),
          else: read_json_tags(conn, body)

      {:error, _} ->
        ApiError.send(conn, 400, "INVALID_BODY", "Malformed JSON body.")
    end
  rescue
    Plug.Parsers.RequestTooLargeError ->
      too_large(conn, :tags)
  end

  defp decode_json_tags(conn, body) do
    case Jason.decode(body) do
      {:ok, %{"tags" => tags} = map} when map_size(map) == 1 and is_list(tags) ->
        %{conn | body_params: %{"tags" => tags}, params: Map.put(conn.params, "tags", tags)}

      {:ok, %{"tags" => tags}} when is_list(tags) ->
        ApiError.send(conn, 400, "INVALID_TAGS", "Provide a JSON object with only a tags array.")

      {:ok, %{"tags" => _}} ->
        ApiError.send(conn, 400, "INVALID_TAGS", "Tags must be an array of strings.")

      {:ok, %{} = map} when map_size(map) == 0 ->
        ApiError.send(conn, 400, "INVALID_TAGS", "Provide a JSON object with a tags array.")

      {:ok, %{}} ->
        ApiError.send(conn, 400, "INVALID_TAGS", "Provide a JSON object with a tags array.")

      {:ok, _} ->
        ApiError.send(conn, 400, "INVALID_BODY", "Provide a JSON object with a tags array.")

      _ ->
        ApiError.send(conn, 400, "INVALID_BODY", "Malformed JSON body.")
    end
  end

  def multipart_to_params(parts, conn) do
    case normalize_parts(parts) do
      {:ok, params} ->
        # Cleanup any non-file parts we won't keep; file temp is managed by controller/storage.
        {:ok, params, conn}

      {:error, :invalid_tags} ->
        cleanup_parts(parts)
        # Let the outer parser return the structured API error after cleanup.
        throw({:api_error, 400, "INVALID_TAGS", "Tags must be valid strings."})

      {:error, _message} ->
        cleanup_parts(parts)

        throw(
          {:api_error, 400, "INVALID_UPLOAD",
           "Send exactly one file field and optional tags JSON."}
        )
    end
  end

  defp normalize_parts(parts) do
    grouped = Enum.group_by(parts, &elem(&1, 0))

    cond do
      Map.keys(grouped) -- ["file", "tags"] != [] ->
        {:error, :invalid_upload}

      match?(%{"file" => [_, _ | _]}, grouped) or match?(%{"tags" => [_, _ | _]}, grouped) ->
        {:error, :invalid_upload}

      not match?(%{"file" => [{_, _, %Plug.Upload{}}]}, grouped) ->
        {:error, :invalid_upload}

      true ->
        file = grouped |> Map.fetch!("file") |> hd() |> elem(2)

        case Map.get(grouped, "tags") do
          nil ->
            {:ok, %{"file" => file}}

          [{_, _, tags_json}] when is_binary(tags_json) ->
            case Jason.decode(tags_json) do
              {:ok, tags} when is_list(tags) ->
                case App.Storage.validate_tags(tags) do
                  {:ok, normalized} -> {:ok, %{"file" => file, "tags" => normalized}}
                  {:error, _} -> {:error, :invalid_tags}
                end

              _ ->
                {:error, :invalid_tags}
            end

          _ ->
            {:error, :invalid_tags}
        end
    end
  end

  defp cleanup_parts(parts) do
    Enum.each(parts, fn
      {_, _, %Plug.Upload{path: path}} -> File.rm(path)
      _ -> :ok
    end)
  end

  defp invalid_multipart(conn),
    do:
      ApiError.send(
        conn,
        400,
        "INVALID_UPLOAD",
        "Malformed multipart upload. Send exactly one file field and optional tags JSON."
      )

  defp invalid_request(conn, :tags),
    do: ApiError.send(conn, 400, "INVALID_BODY", "Invalid tag update request.")

  defp invalid_request(conn, _),
    do: ApiError.send(conn, 400, "INVALID_UPLOAD", "Invalid upload request.")

  defp too_large(conn, :tags),
    do:
      ApiError.send(
        conn,
        413,
        "FILE_TOO_LARGE",
        "Tag update body exceeds the configured size limit."
      )

  defp too_large(conn, _),
    do:
      ApiError.send(
        conn,
        413,
        "FILE_TOO_LARGE",
        "Request exceeds the configured size limit."
      )
end
