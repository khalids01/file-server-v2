defmodule App.Accounts.User.Senders.SendOtpEmail do
  @moduledoc "Sends a six-digit sign-in code."

  use AppWeb, :verified_routes

  import Swoosh.Email
  alias App.Mailer

  def send(email, code) do
    new()
    |> from({"Serve", Application.fetch_env!(:app, :mail_from)})
    |> to(to_string(email))
    |> subject("Your Serve sign-in code")
    |> text_body("Your Serve sign-in code is #{code}. It expires in 10 minutes.")
    |> html_body("""
    <p>Your Serve sign-in code is:</p>
    <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">#{code}</p>
    <p>It expires in 10 minutes.</p>
    """)
    |> Mailer.deliver!()
  end
end
