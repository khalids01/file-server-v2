defmodule App.Storage.S3 do
  @moduledoc "Path-style S3 requests signed with SigV4, streamed through Req without redirects."
  @max_list_bytes 1024 * 1024
  @list_timeout_ms 10_000
  @max_list_entries 100
  @max_prefix_bytes 512
  @max_cursor_bytes 1024

  @doc """
  Lists one bounded page of objects under `prefix`.

  Only the fixed server-derived namespace passed in by the caller is ever requested;
  keys and common prefixes outside it are discarded. Returns relative names and sizes
  only. No redirects, retries, or raw provider errors are surfaced.
  """
  def list(connection, prefix, cursor \\ nil) do
    with {:ok, endpoint} <- App.Storage.Endpoint.validate(connection.endpoint),
         {:ok, prefix} <- normalize_prefix(prefix),
         {:ok, cursor} <- normalize_cursor(cursor),
         {:ok, plaintext} <- App.Vault.decrypt(connection.credentials),
         {:ok, credentials} <- Jason.decode(plaintext),
         true <- is_binary(credentials["access_key_id"]),
         true <- is_binary(credentials["secret_access_key"]),
         {:ok, body} <-
           fetch_list(endpoint, connection, prefix, cursor, credentials),
         {:ok, result} <- parse_list(body, prefix) do
      {:ok, result}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

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

  # ---- ListObjectsV2 ----

  defp normalize_prefix(prefix) when is_binary(prefix) do
    cond do
      byte_size(prefix) == 0 or byte_size(prefix) > @max_prefix_bytes -> {:error, :invalid}
      not String.ends_with?(prefix, "/") -> {:error, :invalid}
      String.contains?(prefix, ["\\", <<0>>]) -> {:error, :invalid}
      String.match?(prefix, ~r/[\x00-\x1f\x7f]/u) -> {:error, :invalid}
      ".." in String.split(prefix, "/") -> {:error, :invalid}
      true -> {:ok, prefix}
    end
  end

  defp normalize_prefix(_), do: {:error, :invalid}

  defp normalize_cursor(nil), do: {:ok, nil}
  defp normalize_cursor(""), do: {:ok, nil}

  defp normalize_cursor(cursor) when is_binary(cursor) do
    if byte_size(cursor) <= @max_cursor_bytes and
         not String.match?(cursor, ~r/[\x00-\x1f\x7f\s]/u) do
      {:ok, cursor}
    else
      {:error, :invalid}
    end
  end

  defp normalize_cursor(_), do: {:error, :invalid}

  defp fetch_list(endpoint, connection, prefix, cursor, credentials) do
    url = endpoint <> "/" <> URI.encode(connection.bucket, &URI.char_unreserved?/1)

    params =
      [
        {"list-type", "2"},
        {"prefix", prefix},
        {"delimiter", "/"},
        {"encoding-type", "url"},
        {"max-keys", Integer.to_string(@max_list_entries)}
      ] ++ if(cursor, do: [{"continuation-token", cursor}], else: [])

    into = fn {:data, chunk}, {req, resp} ->
      acc = Map.get(resp.private, :list_acc, "")

      if byte_size(acc) + byte_size(chunk) > @max_list_bytes do
        {:halt, {req, %{resp | private: Map.put(resp.private, :oversize, true)}}}
      else
        {:cont, {req, %{resp | private: Map.put(resp.private, :list_acc, acc <> chunk)}}}
      end
    end

    options = [
      method: :get,
      url: url,
      params: params,
      headers: [{"accept", "application/xml"}],
      redirect: false,
      retry: false,
      decode_body: false,
      receive_timeout: @list_timeout_ms,
      connect_options: [timeout: @list_timeout_ms],
      into: into,
      aws_sigv4: [
        access_key_id: credentials["access_key_id"],
        secret_access_key: credentials["secret_access_key"],
        region: connection.region,
        service: :s3
      ]
    ]

    options = Keyword.merge(options, Application.get_env(:app, :storage_s3_request_options, []))

    case Req.request(options) do
      {:ok, %{private: %{oversize: true}}} -> {:error, :unavailable}
      {:ok, %{status: 200, private: private}} -> {:ok, Map.get(private, :list_acc, "")}
      _ -> {:error, :unavailable}
    end
  end

  defp parse_list(body, prefix) do
    # SAX keeps provider element names as charlists instead of creating atoms.
    with true <- String.valid?(body) and not String.contains?(body, <<0>>),
         false <- Regex.match?(~r/<!doctype|<!entity/i, body),
         {:ok, state, rest} <-
           :xmerl_sax_parser.stream(body,
             event_fun: &list_event/3,
             event_state: %{
               stack: [],
               text: "",
               record: %{},
               entries: [],
               token: nil,
               truncated: false,
               root: false
             }
           ),
         true <- String.trim(to_string(rest)) == "" and state.root do
      entries =
        state.entries
        |> Enum.reverse()
        |> Enum.flat_map(&relative_entry(&1, prefix))
        |> Enum.take(@max_list_entries)

      {:ok, %{entries: entries, next_cursor: if(state.truncated, do: state.token)}}
    else
      _ -> {:error, :unavailable}
    end
  catch
    _, _ -> {:error, :unavailable}
  end

  defp list_event({:startElement, _, name, _, _}, _, state) do
    if length(state.stack) >= 16, do: throw(:invalid_xml)
    if state.stack == [] and name != ~c"ListBucketResult", do: throw(:invalid_xml)
    %{state | stack: [name | state.stack], text: "", root: true}
  end

  defp list_event({:characters, chars}, _, state),
    do: %{state | text: state.text <> List.to_string(chars)}

  defp list_event({:endElement, _, name, _}, _, state) do
    value = String.trim(state.text)

    state =
      case name do
        ~c"Key" ->
          %{state | record: Map.put(state.record, :key, value)}

        ~c"Size" ->
          %{state | record: Map.put(state.record, :size, value)}

        ~c"Prefix" ->
          %{state | record: Map.put(state.record, :key, value)}

        ~c"Contents" ->
          %{state | entries: [Map.put(state.record, :type, :file) | state.entries], record: %{}}

        ~c"CommonPrefixes" ->
          %{state | entries: [Map.put(state.record, :type, :folder) | state.entries], record: %{}}

        ~c"NextContinuationToken" ->
          case normalize_cursor(value) do
            {:ok, token} -> %{state | token: token}
            _ -> throw(:invalid_cursor)
          end

        ~c"IsTruncated" ->
          %{state | truncated: value == "true"}

        _ ->
          state
      end

    %{state | stack: tl(state.stack), text: ""}
  end

  defp list_event(_, _, state), do: state

  defp relative_entry(%{key: key, type: type} = entry, prefix) do
    decoded = URI.decode(key)

    if String.starts_with?(decoded, prefix) do
      relative = String.replace_prefix(decoded, prefix, "")
      segment = if type == :folder, do: String.trim_trailing(relative, "/"), else: relative
      size = Map.get(entry, :size, "0")

      with true <- segment != "" and segment not in [".", ".."],
           false <- String.contains?(segment, ["/", "\\", <<0>>]),
           false <- Regex.match?(~r/[\x00-\x1f\x7f]/u, segment),
           true <- byte_size(size) <= 20,
           {bytes, ""} when bytes >= 0 <- Integer.parse(size) do
        [%{name: relative, type: type, size: bytes}]
      else
        _ -> []
      end
    else
      []
    end
  end

  defp relative_entry(_, _), do: []
end
