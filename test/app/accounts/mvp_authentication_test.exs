defmodule App.Accounts.MvpAuthenticationTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Accounts.Otp

  test "code verification is single-use" do
    code = request_code("otp@example.com")
    assert {:ok, _} = Otp.verify_sign_in("otp@example.com", code, nil)
    assert {:error, _} = Otp.verify_sign_in("otp@example.com", code, nil)
  end

  test "three wrong codes exhaust the challenge and resend is throttled" do
    code = request_code("wrong@example.com")
    wrong = if code == "000000", do: "111111", else: "000000"
    for _ <- 1..3, do: assert({:error, _} = Otp.verify_sign_in("wrong@example.com", wrong, nil))
    assert {:error, _} = Otp.verify_sign_in("wrong@example.com", code, nil)
    assert {:error, :rate_limited} = Otp.request_sign_in("wrong@example.com", "127.0.0.1")
  end

  test "expired codes fail and resend revokes the old challenge" do
    code = request_code("expiry@example.com")

    App.Repo.query!(
      "UPDATE otp_challenges SET expires_at=now()-interval '1 minute',created_at=now()-interval '2 minutes' WHERE identity=$1",
      ["expiry@example.com"]
    )

    assert {:error, _} = Otp.verify_sign_in("expiry@example.com", code, nil)
    next = request_code("expiry@example.com")

    assert App.Repo.one!(
             from c in App.Accounts.OtpChallengeRecord,
               where: c.identity == "expiry@example.com" and not is_nil(c.revoked_at),
               select: count()
           ) == 1

    assert {:ok, _} = Otp.verify_sign_in("expiry@example.com", next, nil)
  end

  test "bans reject stale actors and pending codes" do
    operator =
      user("ban-operator@example.com")
      |> Ash.update!(%{}, action: :mark_operator, authorize?: false)

    member = user("ban-member@example.com")

    App.Repo.query!(
      "UPDATE otp_challenges SET created_at=now()-interval '2 minutes' WHERE identity=$1",
      [to_string(member.email)]
    )

    code = request_code(to_string(member.email))
    Ash.update!(member, %{}, action: :ban, actor: operator)
    refute App.Accounts.active_user(member)
    assert {:error, _} = Otp.verify_sign_in(to_string(member.email), code, nil)

    assert {:error, _} =
             Ash.update(member, %{name: "bypass"}, action: :update_profile, actor: member)
  end
end
