defmodule App.Accounts.AuthenticationTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Accounts.{User, Otp}

  test "GitHub is the only framework sign-in strategy; codes use the normal session tokens" do
    assert Enum.map(AshAuthentication.Info.list_strategies(User), & &1.name) == [:github]
    user = user("session@example.com")
    assert user.confirmed_at

    assert {:ok, %{"sub" => subject}, _} =
             AshAuthentication.Jwt.verify(user.__metadata__.token, User)

    assert {:ok, restored} = AshAuthentication.subject_to_user(subject, User)
    assert restored.id == user.id
    refute user.operator
  end

  test "ordinary users cannot promote themselves and operators cannot self-ban" do
    member = user("member@example.com")
    assert {:error, _} = Ash.update(member, %{}, action: :mark_operator, actor: member)
    operator = Ash.update!(member, %{}, action: :mark_operator, authorize?: false)
    assert {:error, _} = Ash.update(operator, %{}, action: :ban, actor: operator)
  end

  test "signup closure blocks in-flight OTP registration but permits existing accounts" do
    operator =
      user("operator@example.com") |> Ash.update!(%{}, action: :mark_operator, authorize?: false)

    existing = user("existing@example.com")
    pending = request_code("pending@example.com")
    App.Platform.set_signup_enabled!(false, operator)
    assert {:error, _} = Otp.verify_sign_in("pending@example.com", pending, nil)
    assert :ok = Otp.request_sign_in("new@example.com", "192.0.2.1")
    refute_receive {:email, _}

    App.Repo.query!(
      "UPDATE otp_challenges SET created_at=now()-interval '2 minutes' WHERE identity=$1",
      [to_string(existing.email)]
    )

    code = request_code(to_string(existing.email))
    assert {:ok, same} = Otp.verify_sign_in(to_string(existing.email), code, nil)
    assert same.id == existing.id
  end
end
