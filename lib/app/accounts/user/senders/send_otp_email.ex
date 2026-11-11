defmodule App.Accounts.User.Senders.SendOtpEmail do
  import Swoosh.Email

  def send(email, code) do
    sender = Application.fetch_env!(:app, :mail_sender)

    message =
      new()
      |> from(sender)
      |> to(to_string(email))
      |> subject("Your File Server sign-in code")
      |> text_body(
        "Your File Server sign-in code is #{code}. It expires in 10 minutes. If you didn't request this, ignore this email."
      )
      |> html_body("""
      <div style="background:#fafafa;padding:40px 16px;font-family:Arial,sans-serif;color:#18181b">
        <div style="max-width:440px;margin:auto;border:1px solid #e4e4e7;border-radius:12px;background:#fff;padding:32px">
          <p style="font-size:13px;font-weight:600;margin:0 0 28px">FILE SERVER</p>
          <h1 style="font-size:24px;letter-spacing:-.6px">Your sign-in code</h1>
          <p style="color:#71717a;font-size:14px;line-height:24px">Enter this one-time code to securely sign in:</p>
          <div style="margin:28px 0;padding:20px;background:#f4f4f5;border-radius:8px;font-size:32px;letter-spacing:8px;text-align:center;font-weight:700">#{code}</div>
          <p style="color:#71717a;font-size:13px;line-height:22px">This code expires in 10 minutes and can only be used once. If you didn't request it, you can safely ignore this email.</p>
        </div>
      </div>
      """)

    case App.Mailer.deliver(message) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :delivery_failed}
    end
  end
end
