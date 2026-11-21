defmodule AppWeb.StorageBrowserLive do
  use AppWeb, :live_view
  alias App.Storage.Browser
  on_mount {AppWeb.LiveUserAuth, :live_user_required}

  def mount(_, _, socket) do
    if connected?(socket), do: App.DashboardNotifier.subscribe(socket.assigns.current_user.id)

    {:ok,
     assign(socket,
       show_storage: false,
       storage_error: nil,
       storage_form: to_form(%{}, as: :storage),
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

  def handle_event("new_storage", _, socket) do
    apps = Enum.filter(socket.assigns.drives, &(&1.type == :local))

    app_id =
      case apps do
        [app] -> app.application_id
        _ -> ""
      end

    {:noreply,
     assign(socket,
       show_storage: true,
       storage_error: nil,
       storage_form: to_form(%{"application_id" => app_id}, as: :storage)
     )}
  end

  def handle_event("close_storage", _, socket) do
    {:noreply,
     assign(socket,
       show_storage: false,
       storage_error: nil,
       storage_form: to_form(%{}, as: :storage)
     )}
  end

  def handle_event("create_storage", %{"storage" => attrs}, socket) when is_map(attrs) do
    case App.Storage.create_connection(
           socket.assigns.current_user,
           attrs["application_id"],
           attrs
         ) do
      {:ok, _connection} ->
        {:ok, drives} = Browser.drives(socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(
           drives: drives,
           show_storage: false,
           storage_error: nil,
           storage_form: to_form(%{}, as: :storage)
         )
         |> put_flash(
           :info,
           "S3 connection saved. Choose it in application settings to use it for new uploads."
         )}

      {:error, reason} ->
        values = Map.take(attrs, ~w(application_id name endpoint bucket region))

        {:noreply,
         assign(socket,
           storage_form: to_form(values, as: :storage),
           storage_error:
             if(is_binary(reason),
               do: reason,
               else: "Unable to save the connection. Check its fields and application."
             )
         )}
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
