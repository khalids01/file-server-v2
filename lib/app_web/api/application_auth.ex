defmodule AppWeb.ApplicationAuth do
  @moduledoc "Server-side application credentials, revalidated for every request before body parsing."
  import Plug.Conn
  alias AppWeb.ApiError
  def init(opts), do: opts

  def call(conn, _) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    cond do
      get_req_header(conn, "origin") != [] or get_req_header(conn, "sec-fetch-site") != [] ->
        ApiError.send(
          conn,
          403,
          "SERVER_CREDENTIAL_REQUIRED",
          "Application keys are server-side credentials."
        )

      not App.Accounts.RateLimit.allow_api_ip?(to_string(:inet.ntoa(conn.remote_ip))) ->
        limited(conn)

      true ->
        case App.Applications.authenticate_key(credential(conn), nil) do
          {:ok, %{key: key} = auth} ->
            scope =
              case conn.method do
                "POST" -> "files:write"
                "DELETE" -> "files:delete"
                _ -> "files:read"
              end

            cond do
              scope not in key.scopes ->
                ApiError.send(
                  conn,
                  403,
                  "INSUFFICIENT_SCOPE",
                  "This key does not grant the required file permission."
                )

              not App.Accounts.RateLimit.allow_api_key?(key.id) ->
                limited(conn)

              true ->
                assign(conn, :application_auth, auth)
            end

          _ ->
            ApiError.send(
              conn,
              401,
              "INVALID_API_KEY",
              "Invalid, expired, or revoked application key."
            )
        end
    end
  end

  defp credential(conn) do
    case {get_req_header(conn, "authorization"), get_req_header(conn, "x-api-key")} do
      {["Bearer " <> token], []} -> token
      {[], [token]} -> token
      _ -> nil
    end
  end

  defp limited(conn),
    do:
      conn
      |> put_resp_header("retry-after", "60")
      |> ApiError.send(429, "RATE_LIMITED", "Too many API requests. Try again later.")
end
