defmodule AppWeb.LiveUserAuth do
  import Phoenix.Component
  import Phoenix.LiveView
  use AppWeb, :verified_routes

  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    {:cont,
     assign(socket, :current_user, App.Accounts.active_user(socket.assigns[:current_user]))}
  end

  def on_mount(mode, _params, _session, socket)
      when mode in [:live_user_required, :operator_required] do
    user = App.Accounts.active_user(socket.assigns[:current_user])

    if user && (mode != :operator_required || user.operator) do
      socket =
        socket
        |> assign(:current_user, user)
        |> attach_hook(:fresh_account, :handle_event, fn _event, _params, socket ->
          fresh = App.Accounts.active_user(socket.assigns.current_user)

          if fresh && (mode != :operator_required || fresh.operator),
            do: {:cont, assign(socket, :current_user, fresh)},
            else: {:halt, redirect(socket, to: ~p"/sign-in")}
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if App.Accounts.active_user(socket.assigns[:current_user]),
      do: {:halt, redirect(socket, to: ~p"/dashboard")},
      else: {:cont, assign(socket, :current_user, nil)}
  end
end
