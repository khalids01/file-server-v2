defmodule AppWeb.OtpController do
  use AppWeb, :controller

  import AshAuthentication.Phoenix.Plug, only: [store_in_session: 2]

  alias App.Accounts.Otp

  def new(conn, _params) do
    conn
    |> render(:new)
  end

  def register(conn, params) do
    name = params["name"]

    if is_binary(name) and String.trim(name) != "" and String.length(String.trim(name)) <= 100 do
      request_email_code(conn, params["email"], String.trim(name))
    else
      conn
      |> put_status(422)
      |> put_flash(:error, "Enter your name (up to 100 characters).")
      |> put_view(html: AppWeb.SessionHTML)
      |> render(:register, github?: App.Accounts.Github.enabled?())
    end
  end

  def request_code(conn, %{"email" => email}), do: request_email_code(conn, email, nil)

  defp request_email_code(conn, email, name) do
    ip = client_ip(conn)

    case Otp.request_sign_in(email, ip) do
      :ok ->
        conn
        |> put_session(:pending_otp_email, email)
        |> put_session(:pending_otp_name, name)
        |> render(:verify, email: email, error: nil)

      {:error, reason} ->
        {status, message} =
          case reason do
            :rate_limited -> {429, "Too many requests. Please wait a minute and try again."}
            :delivery_failed -> {503, "We couldn't send the code. Please try again shortly."}
            _ -> {422, "Enter a valid email address."}
          end

        conn = conn |> put_status(status) |> put_flash(:error, message)

        if name do
          conn
          |> put_view(html: AppWeb.SessionHTML)
          |> render(:register, github?: App.Accounts.Github.enabled?())
        else
          render(conn, :new)
        end
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
        case Otp.verify_sign_in(email, code, ip, get_session(conn, :pending_otp_name)) do
          {:ok, user} ->
            conn
            |> configure_session(renew: true)
            |> delete_session(:pending_otp_email)
            |> delete_session(:pending_otp_name)
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
