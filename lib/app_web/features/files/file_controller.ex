defmodule AppWeb.FileController do
  use AppWeb, :controller

  def download(conn, %{"id" => id}) do
    case App.Accounts.active_user(conn.assigns[:current_user]) do
      nil ->
        redirect(conn, to: ~p"/sign-in")

      actor ->
        case App.Storage.download(actor, id) do
          {:ok, file} ->
            try do
              conn
              |> put_resp_header("cache-control", "private, no-store")
              |> put_resp_header("x-content-type-options", "nosniff")
              |> send_download({:file, file.path},
                filename: file.filename,
                content_type: "application/octet-stream",
                disposition: :attachment
              )
            after
              if file.temporary?, do: File.rm(file.path)
            end

          _ ->
            send_resp(conn, 404, "File unavailable")
        end
    end
  end
end
