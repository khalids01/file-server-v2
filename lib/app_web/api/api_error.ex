defmodule AppWeb.ApiError do
  @moduledoc false
  import Plug.Conn

  def send(conn, status, code, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: %{code: code, message: message}})
    |> halt()
  end
end
