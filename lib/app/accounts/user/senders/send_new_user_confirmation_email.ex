defmodule App.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc "Sends an email confirmation link for newly registered users."

  use AshAuthentication.Sender
  use AppWeb, :verified_routes

  import Swoosh.Email
  alias App.Mailer

  @impl true
  def send(user, token, _opts) do
    link = url(~p"/confirm_new_user/#{token}")

    new()
    |> from({"Serve", Application.fetch_env!(:app, :mail_from)})
    |> to(to_string(user.email))
    |> subject("Confirm your Serve account")
    |> text_body("Confirm your Serve account by visiting: #{link}")
    |> html_body("""
    <p>Confirm your Serve account by clicking the link below.</p>
    <p><a href="#{link}">Confirm my account</a></p>
    """)
    |> Mailer.deliver!()
  end
end
