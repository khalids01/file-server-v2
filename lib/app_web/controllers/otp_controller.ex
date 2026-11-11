defmodule AppWeb.OtpController do
  use AppWeb, :controller

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]

  alias App.Accounts.Otp

  def new(conn, _params) do
    conn
    |> render(:new)
  end

  def request_code(conn, %{"email" => email}) do
    ip = client_ip(conn)

    case Otp.request_sign_in(email, ip) do
      :ok ->
        conn
        |> put_session(:pending_otp_email, email)
        |> render(:verify, email: email, error: nil)

      {:error, reason} ->
        {status, message} =
          case reason do
            :rate_limited -> {429, "Too many requests. Please wait a minute and try again."}
            :delivery_failed -> {503, "We couldn't send the code. Please try again shortly."}
            _ -> {422, "Enter a valid email address."}
          end

        conn |> put_status(status) |> put_flash(:error, message) |> render(:new)
    end
  end

  def verify(conn, %{"code" => code}) do
    ip = client_ip(conn)

    case get_session(conn, :pending_otp_email) do
      nil ->
        conn
        |> put_flash(:error, "Your code request expired. Please start again.")
        |> redirect(to: ~p"/sign-in/otp")

      email ->
        case Otp.verify_sign_in(email, code, ip) do
          {:ok, user} ->
            conn
            |> configure_session(renew: true)
            |> delete_session(:pending_otp_email)
            |> store_in_session(user)
            |> assign(:current_user, user)
            |> put_flash(:info, "You are now signed in")
            |> redirect(to: ~p"/dashboard")

          {:error, :banned} ->
            conn
            |> put_flash(:error, "Incorrect email or code")
            |> render(:verify, email: email, error: "Incorrect email or code")

          {:error, :signup_disabled} ->
            conn
            |> put_flash(:error, "Incorrect email or code")
            |> render(:verify, email: email, error: "Incorrect email or code")

          {:error, _} ->
            conn
            |> render(:verify, email: email, error: "Incorrect or expired code")
        end
    end
  end

  defp client_ip(conn), do: to_string(:inet.ntoa(conn.remote_ip))
end
