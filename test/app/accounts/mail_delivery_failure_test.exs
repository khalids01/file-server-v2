defmodule App.Accounts.MailDeliveryFailureTest do
  use App.DataCase, async: false

  test "failed SMTP delivery revokes the generated code and returns a safe error" do
    original = Application.fetch_env!(:app, App.Mailer)
    Application.put_env(:app, App.Mailer, adapter: App.FailingMailAdapter)
    on_exit(fn -> Application.put_env(:app, App.Mailer, original) end)

    assert {:error, :delivery_failed} =
             App.Accounts.Otp.request_sign_in("failure@example.test", "192.0.2.71")

    assert_receive {:attempted_email, email}
    [_, code] = Regex.run(~r/code is (\d{6})/, email.text_body)
    assert {:error, _} = App.Accounts.Otp.verify_sign_in("failure@example.test", code, nil)

    assert App.Repo.one!(
             from c in App.Accounts.OtpChallengeRecord,
               where: c.identity == "failure@example.test" and not is_nil(c.revoked_at),
               select: count()
           ) == 1
  end
end
