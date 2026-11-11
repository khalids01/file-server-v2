defmodule App.Accounts.OtpConcurrencyTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL.Sandbox

  test "two real database connections cannot consume one code twice" do
    email = "race-#{Ecto.UUID.generate()}@example.com"

    on_exit(fn ->
      Sandbox.unboxed_run(App.Repo, fn ->
        App.Repo.query!(
          "DELETE FROM tokens WHERE subject IN (SELECT 'user?id=' || id::text FROM users WHERE email=$1)",
          [email]
        )

        App.Repo.query!(
          "DELETE FROM user_identities WHERE user_id IN (SELECT id FROM users WHERE email=$1)",
          [email]
        )

        App.Repo.query!("DELETE FROM users WHERE email=$1", [email])
        App.Repo.query!("DELETE FROM otp_challenges WHERE identity=$1", [email])
      end)
    end)

    assert :ok =
             Sandbox.unboxed_run(App.Repo, fn ->
               App.Accounts.Otp.request_sign_in(email, "192.0.2.40")
             end)

    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is (\d{6})/, mail.text_body)

    supervisor = start_supervised!(Task.Supervisor)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.Supervisor.async(supervisor, fn ->
          Sandbox.unboxed_run(App.Repo, fn ->
            App.Accounts.Otp.verify_sign_in(email, code, "192.0.2.40")
          end)
        end)
      end)
      |> Enum.map(&Task.await(&1, 15_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
  end
end
