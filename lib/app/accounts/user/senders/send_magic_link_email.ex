defmodule App.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic link email
  """

  use AshAuthentication.Sender
  use AppWeb, :verified_routes

  import Swoosh.Email
  alias App.Mailer

  @impl true
  def send(user_or_email, token, _) do
    # if you get a user, its for a user that already exists.
    # if you get an email, then the user does not yet exist.

    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    new()
    |> from({"App v2", Application.fetch_env!(:app, :mail_from)})
    |> to(to_string(email))
    |> subject("Your login link")
    |> text_body("Sign in to App v2: #{url(~p"/magic_link/#{token}")}")
    |> html_body(body(token: token, email: email))
    |> Mailer.deliver!()
  end

  defp body(params) do
    # NOTE: You may have to change this to match your magic link acceptance URL.

    """
    <p>Hello! Click this link to sign in:</p>
    <p><a href="#{url(~p"/magic_link/#{params[:token]}")}">#{url(~p"/magic_link/#{params[:token]}")}</a></p>
    """
  end
end
