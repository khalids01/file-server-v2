defmodule AppWeb.ApplicationApiController do
  use AppWeb, :controller

  def usage(conn, params) when map_size(params) == 0 do
    auth = conn.assigns.application_auth

    case App.Storage.Insights.application(auth.user, auth.application.id) do
      {:ok, %{metrics: metrics}} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> json(%{
          data: %{
            applicationId: auth.application.id,
            files: metrics.files,
            originalBytes: metrics.original_bytes,
            previewBytes: metrics.variant_bytes,
            reservedBytes: metrics.reserved_bytes,
            imagePending: metrics.image_pending,
            imageFailed: metrics.image_failed,
            cleanupPending: metrics.cleanup_pending,
            pendingUploads: metrics.upload_pending
          }
        })

      _ ->
        AppWeb.ApiError.send(conn, 503, "USAGE_UNAVAILABLE", "Usage is temporarily unavailable.")
    end
  end

  def usage(conn, _),
    do:
      AppWeb.ApiError.send(conn, 400, "INVALID_QUERY", "This route accepts no query parameters.")

  def show(conn, _) do
    %{application: app, key: key} = conn.assigns.application_auth

    json(conn, %{
      data: %{id: app.id, name: app.name, scopes: key.scopes},
      storage_ready: true,
      api_version: "v2",
      sdk_v1_compatible: false
    })
  end
end
