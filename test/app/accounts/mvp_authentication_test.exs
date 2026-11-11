defmodule App.Accounts.MvpAuthenticationTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Accounts.{Otp, User}

  defp request_code(email, ip \\ "127.0.0.1") do
    assert :ok = Otp.request_sign_in(email, ip)
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is (\d{6})/, mail.text_body)
    code
  end

  test "email code registers a verified user and persisted session; replay fails" do
    email = "otp@example.com"
    code = request_code(email)
    assert {:ok, user} = Otp.verify_sign_in(email, code, "127.0.0.1")
    assert user.confirmed_at
    assert user.operator == false
    assert App.Accounts.active_user(user)

    assert {:ok, %{"sub" => subject}, _} =
             AshAuthentication.Jwt.verify(user.__metadata__.token, User)

    assert {:ok, restored} = AshAuthentication.subject_to_user(subject, User)
    assert restored.id == user.id
    assert {:error, _} = Otp.verify_sign_in(email, code, "127.0.0.1")
  end

  test "three wrong codes exhaust the challenge and resend is throttled" do
    email = "wrong@example.com"
    code = request_code(email)
    wrong = if code == "000000", do: "111111", else: "000000"
    for _ <- 1..3, do: assert({:error, _} = Otp.verify_sign_in(email, wrong, nil))
    assert {:error, _} = Otp.verify_sign_in(email, code, nil)
    assert {:error, :rate_limited} = Otp.request_sign_in(email, "127.0.0.1")
  end

  test "expired codes fail and superseded codes cannot authenticate" do
    email = "expiry@example.com"
    code = request_code(email)

    App.Repo.query!(
      "UPDATE otp_challenges SET expires_at = now() - interval '1 minute', created_at = now() - interval '2 minutes' WHERE identity = $1",
      [email]
    )

    assert {:error, _} = Otp.verify_sign_in(email, code, nil)
    next = request_code(email)
    # Verify using the revoked challenge, even in the rare event both random codes match.
    assert App.Repo.one!(
             from c in App.Accounts.OtpChallengeRecord,
               where: c.identity == ^email and not is_nil(c.revoked_at),
               select: count()
           ) == 1

    assert {:ok, _} = Otp.verify_sign_in(email, next, nil)
  end

  test "password registration requires real email confirmation, then supports login" do
    password = "a-long-test-password"
    strategy = AshAuthentication.Info.strategy!(User, :password)

    assert {:error,
            %AshAuthentication.Errors.AuthenticationFailed{
              caused_by: %AshAuthentication.Errors.UnconfirmedUser{}
            }} =
             AshAuthentication.Strategy.action(strategy, :register, %{
               email: "password@example.com",
               password: password,
               password_confirmation: password,
               name: "Test"
             })

    user = Ash.get!(User, [email: "password@example.com"], authorize?: false)
    assert is_nil(user.confirmed_at)

    assert {:error, _} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               email: "password@example.com",
               password: password
             })

    assert_receive {:email, mail}
    [_, token] = Regex.run(~r{/confirm_new_user/([^\s]+)}, mail.text_body)
    confirmation = AshAuthentication.Info.strategy!(User, :confirm_new_user)

    assert {:ok, confirmed} =
             AshAuthentication.Strategy.action(confirmation, :confirm, %{"confirm" => token})

    assert confirmed.confirmed_at

    assert {:ok, signed_in} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               email: "password@example.com",
               password: password
             })

    assert signed_in.id == user.id

    assert {:error, _} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               email: "password@example.com",
               password: "wrong"
             })
  end

  test "operator privileges cannot be self-granted and signup policy covers in-flight auth" do
    operator =
      user("operator@example.com") |> Ash.update!(%{}, action: :mark_operator, authorize?: false)

    member = user("member@example.com")
    assert {:error, _} = Ash.update(member, %{}, action: :mark_operator, actor: member)
    assert {:error, _} = Ash.update(operator, %{}, action: :ban, actor: operator)
    {strategy, pending} = request_magic_link("pending@example.com")
    App.Platform.set_signup_enabled!(false, operator)
    assert {:error, _} = AshAuthentication.Strategy.action(strategy, :sign_in, %{token: pending})
    assert :ok = Otp.request_sign_in("new@example.com", "192.0.2.1")
    refute_receive {:email, %{subject: "Your Serve sign-in code"}}

    {existing_strategy, existing_token} = request_magic_link("member@example.com")

    assert {:ok, _} =
             AshAuthentication.Strategy.action(existing_strategy, :sign_in, %{
               token: existing_token
             })

    password = AshAuthentication.Info.strategy!(User, :password)

    assert {:error, _} =
             AshAuthentication.Strategy.action(password, :register, %{
               email: "closed@example.com",
               password: "test-password-long",
               password_confirmation: "test-password-long"
             })
  end

  test "bans invalidate stale actors and key authentication" do
    operator =
      user("ban-operator@example.com")
      |> Ash.update!(%{}, action: :mark_operator, authorize?: false)

    member = user("ban-member@example.com")
    key = api_key(member)
    Ash.update!(member, %{}, action: :ban, actor: operator)
    refute App.Accounts.active_user(member)

    assert {:error, _} =
             Ash.update(member, %{name: "bypass"}, action: :update_profile, actor: member)

    strategy = AshAuthentication.Info.strategy!(User, :api_key)

    assert {:error, _} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               api_key: key.__metadata__.plaintext_api_key
             })
  end
end
