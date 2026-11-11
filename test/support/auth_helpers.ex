defmodule App.AuthHelpers do
  import ExUnit.Assertions

  def request_code(email, ip \\ "127.0.0.1") do
    assert :ok = App.Accounts.Otp.request_sign_in(email, ip)
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is (\d{6})/, mail.text_body)
    code
  end

  def user(email) do
    code = request_code(email)
    {:ok, user} = App.Accounts.Otp.verify_sign_in(email, code, "127.0.0.1")
    user
  end
end
