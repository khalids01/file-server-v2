defmodule App.Storage.S3 do
  @moduledoc "Path-style S3 requests signed with SigV4, streamed through Req without redirects."
  def request(connection, method, key \\ nil, opts \\ []) do
    with {:ok, endpoint} <- App.Storage.Endpoint.validate(connection.endpoint),
         {:ok, plaintext} <- App.Vault.decrypt(connection.credentials),
         {:ok, credentials} <- Jason.decode(plaintext) do
      path =
        "/" <>
          URI.encode(connection.bucket, &URI.char_unreserved?/1) <>
          if(key,
            do:
              "/" <>
                Enum.map_join(
                  String.split(key, "/"),
                  "/",
                  &URI.encode(&1, fn c -> URI.char_unreserved?(c) end)
                ),
            else: ""
          )

      options = [
        method: method,
        url: endpoint <> path,
        redirect: false,
        retry: false,
        decode_body: false,
        receive_timeout: 30_000,
        aws_sigv4: [
          access_key_id: credentials["access_key_id"],
          secret_access_key: credentials["secret_access_key"],
          region: connection.region,
          service: :s3
        ]
      ]

      options = Keyword.merge(options, Application.get_env(:app, :storage_s3_request_options, []))

      case Req.request(Keyword.merge(options, opts)) do
        {:ok, %{private: %{oversize: true}}} -> {:error, :unavailable}
        {:ok, %{status: status}} when status in 200..299 -> :ok
        _ -> {:error, :unavailable}
      end
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def put(connection, key, path, size),
    do:
      request(connection, :put, key,
        body: File.stream!(path, 65_536),
        headers: [
          {"content-length", to_string(size)},
          {"content-type", "application/octet-stream"}
        ]
      )

  def download(connection, key, destination, expected_size) do
    {:ok, io} = File.open(destination, [:write, :binary, :exclusive])

    try do
      File.chmod!(destination, 0o600)

      into = fn {:data, chunk}, {req, resp} ->
        size = Map.get(resp.private, :stored_size, 0) + byte_size(chunk)

        if size > expected_size do
          {:halt, {req, %{resp | private: Map.put(resp.private, :oversize, true)}}}
        else
          :ok = IO.binwrite(io, chunk)
          {:cont, {req, %{resp | private: Map.put(resp.private, :stored_size, size)}}}
        end
      end

      result = request(connection, :get, key, into: into)
      File.close(io)

      if result == :ok and File.stat!(destination).size == expected_size,
        do: :ok,
        else: {:error, :unavailable}
    after
      File.close(io)
    end
  end
end
