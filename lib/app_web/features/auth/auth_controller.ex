defmodule AppWeb.AuthController do
  use AppWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    return_to = ~p"/dashboard"

    if App.Accounts.active_user(user) do
      conn
      |> configure_session(renew: true)
      |> delete_session(:return_to)
      |> store_in_session(user)
      # If your resource has a different name, update the assign name here (i.e :current_admin)
      |> assign(:current_user, user)
      |> put_flash(:info, "You are now signed in")
      |> redirect(to: return_to)
    else
      conn
      |> put_flash(:info, "If an eligible account exists, check your email for the next step.")
      |> redirect(to: ~p"/sign-in")
    end
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(
      :error,
      "GitHub sign-in could not be completed. Try signing in with your email code."
    )
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = ~p"/"

    conn
    |> clear_session(:app)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
