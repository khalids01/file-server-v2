defmodule App.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc "Sends a password reset link."

  use AshAuthentication.Sender
  use AppWeb, :verified_routes

  import Swoosh.Email
  alias App.Mailer

  @impl true
  def send(user, token, _opts) do
    link = url(~p"/password-reset/#{token}")

    new()
    |> from({"Serve", Application.fetch_env!(:app, :mail_from)})
    |> to(to_string(user.email))
    |> subject("Reset your Serve password")
    |> text_body("Reset your Serve password by visiting: #{link}")
    |> html_body("""
    <p>Reset your Serve password by clicking the link below.</p>
    <p><a href="#{link}">Reset my password</a></p>
    """)
    |> Mailer.deliver!()
  end
end
