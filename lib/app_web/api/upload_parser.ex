defmodule AppWeb.UploadParser do
  @moduledoc "Bounded multipart parsing for authenticated API uploads."
  alias AppWeb.ApiError
  def init(opts), do: opts

  def call(%{method: "POST", path_info: ["api", "v2", "files"]} = conn, _) do
    limit = App.Storage.max_file_size() + 1_048_576

    case Plug.Conn.get_req_header(conn, "content-length") do
      [length] ->
        case Integer.parse(length) do
          {n, ""} when n > limit ->
            ApiError.send(
              conn,
              413,
              "FILE_TOO_LARGE",
              "Upload exceeds the configured size limit."
            )

          {n, ""} when n >= 0 ->
            parse(conn, limit)

          _ ->
            ApiError.send(conn, 400, "INVALID_UPLOAD", "Invalid content length.")
        end

      [] ->
        parse(conn, limit)

      _ ->
        ApiError.send(conn, 400, "INVALID_UPLOAD", "Invalid content length.")
    end
  end

  def call(conn, _), do: conn

  defp parse(conn, limit) do
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
      ApiError.send(conn, 413, "FILE_TOO_LARGE", "Upload exceeds the configured size limit.")

    Plug.Parsers.UnsupportedMediaTypeError ->
      ApiError.send(conn, 415, "INVALID_UPLOAD", "Use multipart/form-data with one file field.")

    _ in [Plug.Parsers.ParseError, Plug.Parsers.BadEncodingError, Plug.UploadError] ->
      ApiError.send(
        conn,
        400,
        "INVALID_UPLOAD",
        "Malformed multipart upload. Send exactly one file field."
      )
  end

  def multipart_to_params([{"file", _, %Plug.Upload{} = file}], conn),
    do: {:ok, %{"file" => file}, conn}

  def multipart_to_params(parts, _) do
    Enum.each(parts, fn
      {_, _, %Plug.Upload{path: path}} -> File.rm(path)
      _ -> :ok
    end)

    raise ArgumentError, "Exactly one file field is required"
  end
end
