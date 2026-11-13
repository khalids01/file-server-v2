defmodule AppWeb.ApplicationApiController do
  use AppWeb, :controller

  def show(conn, _) do
    bearer =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> value] -> value
        _ -> List.first(get_req_header(conn, "x-api-key"))
      end

    if get_req_header(conn, "origin") != [] do
      conn |> put_status(403) |> json(%{error: "Application keys are server-side credentials"})
    else
      case App.Applications.authenticate_key(bearer, "files:read") do
        {:ok, %{application: app, key: key}} ->
          json(conn, %{
            data: %{id: app.id, name: app.name, scopes: key.scopes},
            storage_ready: false
          })

        _ ->
          conn
          |> put_status(401)
          |> json(%{error: "Invalid, expired, or revoked application key"})
      end
    end
  end
end
