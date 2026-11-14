defmodule AppWeb.HealthController do
  use AppWeb, :controller

  def live(conn, _), do: json(conn, %{status: "ok"})

  def ready(conn, _) do
    healthy =
      match?(
        {:ok, %{rows: [[true]]}},
        App.Repo.query(
          "SELECT to_regclass('public.stored_files') IS NOT NULL AND to_regclass('public.account_storage') IS NOT NULL AND to_regclass('public.oban_jobs') IS NOT NULL",
          [], timeout: 2_000, pool_timeout: 2_000)
      ) and
        is_pid(Oban.whereis(Oban))

    respond(conn, healthy)
  rescue
    _ -> respond(conn, false)
  catch
    :exit, _ -> respond(conn, false)
  end

  defp respond(conn, healthy) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(if(healthy, do: 200, else: 503))
    |> json(%{status: if(healthy, do: "ready", else: "unavailable")})
  end
end
