defmodule AppWeb.StorageBrowserLive do
  use AppWeb, :live_view
  alias App.Storage.Browser
  on_mount {AppWeb.LiveUserAuth, :live_user_required}

  def mount(_, _, socket) do
    if connected?(socket), do: App.DashboardNotifier.subscribe(socket.assigns.current_user.id)

    {:ok,
     assign(socket,
       refresh_pending: nil,
       drives: [],
       page: nil,
       error: nil,
       loading: false,
       drive_id: nil,
       prefix: "",
       cursor: nil
     )}
  end

  def handle_params(params, _, socket) do
    case Browser.drives(socket.assigns.current_user) do
      {:ok, drives} ->
        socket =
          assign(socket,
            refresh_pending: nil,
            drives: drives,
            drive_id: params["id"],
            prefix: params["prefix"] || "",
            cursor: params["cursor"],
            page: nil,
            error: nil
          )

        {:noreply, load_page(socket)}

      _ ->
        {:noreply, assign(socket, error: "Storage is unavailable.")}
    end
  end

  def handle_event("refresh", _, socket), do: {:noreply, load_page(socket)}

  def handle_info(:dashboard_changed, socket) do
    if socket.assigns.refresh_pending do
      {:noreply, socket}
    else
      token = make_ref()
      Process.send_after(self(), {:refresh_storage, token}, 25)
      {:noreply, assign(socket, refresh_pending: token)}
    end
  end

  def handle_info({:refresh_storage, token}, %{assigns: %{refresh_pending: token}} = socket) do
    socket = assign(socket, refresh_pending: nil)

    case App.Accounts.active_user(socket.assigns.current_user) do
      nil ->
        {:noreply, redirect(socket, to: ~p"/sign-in")}

      user ->
        case Browser.drives(user) do
          {:ok, drives} ->
            {:noreply, socket |> assign(current_user: user, drives: drives) |> load_page()}

          _ ->
            {:noreply, assign(socket, error: "Storage is unavailable.")}
        end
    end
  end

  def handle_info({:refresh_storage, _}, socket), do: {:noreply, socket}

  def handle_async(:browse, {:ok, {id, prefix, cursor, result}}, socket) do
    cond do
      is_nil(App.Accounts.active_user(socket.assigns.current_user)) ->
        {:noreply, redirect(socket, to: ~p"/sign-in")}

      {id, prefix, cursor} ==
          {socket.assigns.drive_id, socket.assigns.prefix, socket.assigns.cursor} ->
        case result do
          {:ok, page} ->
            {:noreply, assign(socket, page: page, loading: false, error: nil)}

          _ ->
            {:noreply,
             assign(socket,
               page: nil,
               loading: false,
               error: "Unable to browse this drive. Check its connection and permissions."
             )}
        end

      true ->
        {:noreply, socket}
    end
  end

  def handle_async(:browse, {:exit, _}, socket),
    do: {:noreply, assign(socket, loading: false, error: "Unable to browse this drive.")}

  defp load_page(%{assigns: %{drive_id: nil}} = socket),
    do: assign(socket, page: nil, loading: false)

  defp load_page(socket) do
    actor = socket.assigns.current_user
    id = socket.assigns.drive_id
    prefix = socket.assigns.prefix
    cursor = socket.assigns.cursor

    socket
    |> cancel_async(:browse)
    |> assign(loading: true, error: nil)
    |> start_async(:browse, fn ->
      {id, prefix, cursor, Browser.browse(actor, id, prefix, cursor)}
    end)
  end

  defp browse_path(id, prefix, cursor \\ nil) do
    ~p"/dashboard/storage/#{id}?#{Enum.reject([prefix: prefix, cursor: cursor], fn {_, v} -> v in [nil, ""] end)}"
  end

  defp parent(prefix) do
    parts = prefix |> String.split("/", trim: true) |> Enum.drop(-1)
    if parts == [], do: "", else: Enum.join(parts, "/") <> "/"
  end
end
