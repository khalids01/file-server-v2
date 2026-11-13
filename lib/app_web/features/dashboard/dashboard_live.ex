defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view
  require Ash.Query
  alias App.Applications
  alias App.Applications.{Application, ApplicationKey}
  on_mount {AppWeb.LiveUserAuth, :live_user_required}

  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       plaintext_key: nil,
       selected_app: nil,
       revoking_key: nil,
       keys: [],
       applications: [],
       show_create: false,
       save_error: nil,
       tab: "settings",
       key_counts: %{}
     )}
  end

  def handle_params(params, _, socket) do
    socket =
      socket
      |> assign(selected_app: nil, plaintext_key: nil, tab: params["tab"] || "settings")
      |> load_apps()

    if socket.assigns.live_action == :application do
      case Ash.get(Application, params["id"], actor: socket.assigns.current_user) do
        {:ok, %Application{} = app} ->
          {:noreply, socket |> assign(selected_app: app) |> load_keys()}

        _ ->
          {:noreply,
           socket
           |> put_flash(:error, "Application not found")
           |> push_navigate(to: ~p"/dashboard/applications")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("new_application", _, socket),
    do: {:noreply, assign(socket, show_create: true, save_error: nil)}

  def handle_event("close_dialog", _, socket),
    do: {:noreply, assign(socket, show_create: false, revoking_key: nil)}

  def handle_event("update_application", %{"application" => attrs}, socket) do
    perform(socket, fn ->
      app =
        Ash.update!(socket.assigns.selected_app, Map.take(attrs, ["name"]),
          actor: socket.assigns.current_user
        )

      socket
      |> assign(selected_app: app)
      |> put_flash(:info, "Application updated")
      |> load_apps()
    end)
  end

  def handle_event("create_application", %{"application" => attrs}, socket) do
    perform(socket, fn ->
      Ash.create!(Application, Map.take(attrs, ["name", "slug"]),
        actor: socket.assigns.current_user
      )

      socket
      |> assign(show_create: false)
      |> put_flash(:info, "Application created")
      |> load_apps()
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
        Applications.issue_key!(
          socket.assigns.current_user,
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
      key = Ash.get!(ApplicationKey, id, actor: socket.assigns.current_user)
      assign(socket, :revoking_key, key)
    end)
  end

  def handle_event("confirm_revoke_key", _, socket) do
    perform(socket, fn ->
      Ash.update!(socket.assigns.revoking_key, %{},
        action: :revoke,
        actor: socket.assigns.current_user
      )

      socket
      |> assign(plaintext_key: nil, revoking_key: nil)
      |> put_flash(:info, "Key revoked")
      |> load_keys()
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
      |> Ash.read!(actor: socket.assigns.current_user)

    counts =
      App.Applications.ApplicationKey
      |> Ash.read!(actor: socket.assigns.current_user)
      |> Enum.frequencies_by(& &1.application_id)

    socket
    |> assign(applications: apps, key_counts: counts)
    |> stream(:applications, apps, reset: true)
  end

  defp load_keys(socket) do
    id = socket.assigns.selected_app.id

    keys =
      ApplicationKey
      |> Ash.Query.filter(application_id == ^id)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: socket.assigns.current_user)

    socket |> assign(:keys, keys) |> stream(:keys, keys, reset: true)
  end

  defp perform(socket, fun) do
    {:noreply, fun.()}
  rescue
    _error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown] ->
      {:noreply,
       socket
       |> assign(:save_error, "Unable to save. Check your input and application permissions.")
       |> put_flash(:error, "Unable to save. Check your input and application permissions.")}
  end

  defp section(action),
    do:
      %{
        overview: "Overview",
        applications: "Applications",
        application: "Applications",
        profile: "Profile"
      }[action]
end
