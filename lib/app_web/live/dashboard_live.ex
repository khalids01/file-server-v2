defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view
  require Ash.Query
  alias App.Workspaces
  alias App.Workspaces.{Application, ApplicationKey}
  on_mount {AppWeb.LiveUserAuth, :live_user_required}

  def mount(_, _, socket) do
    Workspaces.ensure_personal!(socket.assigns.current_user)

    {:ok,
     assign(socket,
       plaintext_key: nil,
       selected_app: nil,
       keys: [],
       tenants: [],
       applications: [],
       tenant: nil
     )}
  end

  def handle_params(params, _, socket) do
    tenants = Workspaces.tenants(socket.assigns.current_user)
    tenant = Enum.find(tenants, &(&1.id == params["tenant"])) || List.first(tenants)

    socket =
      socket
      |> assign(tenants: tenants, tenant: tenant, selected_app: nil, plaintext_key: nil)
      |> load_apps()

    {:noreply, socket}
  end

  def handle_event("switch_tenant", %{"tenant" => id}, socket) do
    {:noreply, push_patch(socket, to: workspace_path(socket.assigns.live_action, id))}
  end

  def handle_event("create_workspace", %{"workspace" => %{"name" => name}}, socket) do
    perform(socket, fn ->
      tenant = Workspaces.create_tenant!(socket.assigns.current_user, name)
      push_navigate(socket, to: workspace_path(:overview, tenant.id))
    end)
  end

  def handle_event("create_application", %{"application" => attrs}, socket) do
    perform(socket, fn ->
      Ash.create!(Application, Map.take(attrs, ["name", "slug"]),
        actor: socket.assigns.current_user,
        tenant: socket.assigns.tenant.id
      )

      socket |> put_flash(:info, "Application created") |> load_apps()
    end)
  end

  def handle_event("select_app", %{"id" => id}, socket) do
    perform(socket, fn ->
      app =
        Ash.get!(Application, id,
          actor: socket.assigns.current_user,
          tenant: socket.assigns.tenant.id
        )

      socket |> assign(selected_app: app, plaintext_key: nil) |> load_keys()
    end)
  end

  def handle_event("issue_key", %{"key" => attrs}, socket) do
    perform(socket, fn ->
      scopes =
        case attrs["access"] do
          "read" -> ["files:read"]
          "write" -> ["files:read", "files:write"]
          "manage" -> ["files:read", "files:write", "files:delete"]
          _ -> ["files:read"]
        end

      {_key, raw} =
        Workspaces.issue_key!(
          socket.assigns.current_user,
          socket.assigns.tenant.id,
          socket.assigns.selected_app.id,
          attrs["name"],
          scopes
        )

      socket
      |> assign(:plaintext_key, raw)
      |> put_flash(:info, "Key created. Copy it now; it won't be shown again.")
      |> load_keys()
    end)
  end

  def handle_event("revoke_key", %{"id" => id}, socket) do
    perform(socket, fn ->
      key =
        Ash.get!(ApplicationKey, id,
          actor: socket.assigns.current_user,
          tenant: socket.assigns.tenant.id
        )

      Ash.update!(key, %{},
        action: :revoke,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.tenant.id
      )

      socket |> assign(:plaintext_key, nil) |> put_flash(:info, "Key revoked") |> load_keys()
    end)
  end

  def handle_event("update_profile", %{"profile" => attrs}, socket) do
    perform(socket, fn ->
      user =
        Ash.update!(socket.assigns.current_user, Map.take(attrs, ["name"]),
          action: :update_profile,
          actor: socket.assigns.current_user
        )

      socket |> assign(:current_user, user) |> put_flash(:info, "Profile updated")
    end)
  end

  defp load_apps(socket) do
    apps =
      Application
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: socket.assigns.current_user, tenant: socket.assigns.tenant.id)

    socket |> assign(:applications, apps) |> stream(:applications, apps, reset: true)
  end

  defp load_keys(socket) do
    id = socket.assigns.selected_app.id

    keys =
      ApplicationKey
      |> Ash.Query.filter(application_id == ^id)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: socket.assigns.current_user, tenant: socket.assigns.tenant.id)

    socket |> assign(:keys, keys) |> stream(:keys, keys, reset: true)
  end

  defp perform(socket, fun) do
    {:noreply, fun.()}
  rescue
    _error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown] ->
      {:noreply,
       put_flash(socket, :error, "Unable to save. Check your input and workspace permissions.")}
  end

  defp workspace_path(action, tenant) do
    base =
      case action do
        :applications -> "/dashboard/applications"
        :settings -> "/dashboard/settings"
        :profile -> "/dashboard/profile"
        _ -> "/dashboard"
      end

    base <> "?tenant=" <> tenant
  end

  defp section(action),
    do:
      %{
        overview: "Overview",
        applications: "Applications",
        settings: "Workspace settings",
        profile: "Your profile"
      }[action]
end
