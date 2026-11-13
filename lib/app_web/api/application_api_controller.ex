defmodule AppWeb.ApplicationApiController do
  use AppWeb, :controller

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
