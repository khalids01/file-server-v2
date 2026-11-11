defmodule AppWeb.OperatorLive do
  use AppWeb, :live_view
  require Ash.Query
  on_mount {AppWeb.LiveUserAuth, :operator_required}

  def mount(_, _, socket), do: {:ok, socket |> assign(offset: 0) |> load()}

  def handle_event("toggle_signup", _, socket) do
    App.Platform.set_signup_enabled!(!socket.assigns.signup_enabled, socket.assigns.current_user)
    {:noreply, socket |> put_flash(:info, "Registration policy updated") |> load()}
  end

  def handle_event(event, %{"id" => id}, socket) when event in ["ban", "unban"] do
    user =
      App.Accounts.User
      |> Ash.Query.for_read(:admin_read, %{}, actor: socket.assigns.current_user)
      |> Ash.Query.filter(id == ^id)
      |> Ash.read_one!()

    action = if event == "ban", do: :ban, else: :unban

    case Ash.update(user, %{}, action: action, actor: socket.assigns.current_user) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Account updated") |> load()}
      _ -> {:noreply, put_flash(socket, :error, "Unable to change this account")}
    end
  end

  def handle_event("next", _, socket),
    do: {:noreply, socket |> update(:offset, &(&1 + 50)) |> load()}

  def handle_event("previous", _, socket),
    do: {:noreply, socket |> update(:offset, &max(&1 - 50, 0)) |> load()}

  defp load(socket) do
    page =
      App.Accounts.User
      |> Ash.Query.for_read(:admin_read, %{}, actor: socket.assigns.current_user)
      |> Ash.Query.sort(email: :asc)
      |> Ash.read!(page: [limit: 50, offset: socket.assigns.offset])

    socket
    |> assign(
      signup_enabled: App.Platform.signup_enabled?(),
      more?: page.more?,
      user_count: length(page.results)
    )
    |> stream(:users, page.results, reset: true)
  end
end
