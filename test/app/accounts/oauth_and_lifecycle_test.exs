defmodule App.Accounts.OAuthAndLifecycleTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Accounts.User

  test "GitHub cannot auto-link a different subject to an existing email" do
    existing = user("existing-github@example.com")
    strategy = AshAuthentication.Info.strategy!(User, :github)

    assert {:error, _} =
             AshAuthentication.Strategy.action(strategy, :register, %{
               user_info: %{
                 "sub" => "attacker-subject",
                 "email" => to_string(existing.email),
                 "email_verified" => true
               },
               oauth_tokens: %{}
             })

    assert Ash.count!(App.Accounts.UserIdentity, authorize?: false) == 0
  end

  test "new GitHub identity is persisted without provider tokens and requires email proof" do
    strategy = AshAuthentication.Info.strategy!(User, :github)

    result =
      AshAuthentication.Strategy.action(strategy, :register, %{
        user_info: %{
          "sub" => "new-subject",
          "email" => "github-new@example.com",
          "name" => "GitHub user"
        },
        oauth_tokens: %{"access_token" => "must-not-be-stored"}
      })

    # The library can return an unconfirmed-user failure after persisting registration.
    assert match?({:ok, %User{}}, result) or
             match?(
               {:error,
                %AshAuthentication.Errors.AuthenticationFailed{
                  caused_by: %AshAuthentication.Errors.UnconfirmedUser{}
                }},
               result
             )

    user = Ash.get!(User, [email: "github-new@example.com"], authorize?: false)
    refute user.confirmed_at
    refute App.Accounts.active_user(user)
    [identity] = Ash.read!(App.Accounts.UserIdentity, authorize?: false)
    assert identity.user_id == user.id
    refute identity.access_token
    refute identity.refresh_token
    assert_receive {:email, mail}
    assert mail.subject == "Confirm your Serve account"
  end

  test "password reset can add a password to a verified account, revokes old tokens and cannot replay" do
    user = user("reset@example.com")
    strategy = AshAuthentication.Info.strategy!(User, :password)

    assert :ok =
             AshAuthentication.Strategy.action(strategy, :reset_request, %{
               email: "reset@example.com"
             })

    assert_receive {:email, mail}
    [_, token] = Regex.run(~r{/password-reset/([^\s]+)}, mail.text_body)

    params = %{
      "reset_token" => token,
      "password" => "a-new-long-password",
      "password_confirmation" => "a-new-long-password"
    }

    assert {:ok, updated} = AshAuthentication.Strategy.action(strategy, :reset, params)
    assert Bcrypt.verify_pass("a-new-long-password", updated.hashed_password)
    assert {:error, _} = AshAuthentication.Strategy.action(strategy, :reset, params)

    assert {:ok, signed_in} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               email: "reset@example.com",
               password: "a-new-long-password"
             })

    assert signed_in.id == user.id
    assert {:ok, %{"jti" => jti}} = AshAuthentication.Jwt.peek(user.__metadata__.token)
    stored = Ash.get!(App.Accounts.Token, jti, authorize?: false, not_found_error?: false)
    assert is_nil(stored) or stored.purpose == "revocation"
  end

  test "HTTP authentication requests have a separate IP budget" do
    for _ <- 1..60, do: assert(App.Accounts.RateLimit.allow_auth_ip?("192.0.2.99"))
    refute App.Accounts.RateLimit.allow_auth_ip?("192.0.2.99")
  end

  test "password attempts are bounded by a durable per-identity counter" do
    for _ <- 1..10, do: assert(App.Accounts.RateLimit.allow_password?("limit@example.com"))
    refute App.Accounts.RateLimit.allow_password?("limit@example.com")
  end
end
