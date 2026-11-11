defmodule App.Accounts.OAuthAndLifecycleTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Accounts.User

  defp github(info),
    do:
      AshAuthentication.Strategy.action(
        AshAuthentication.Info.strategy!(User, :github),
        :register,
        %{user_info: info, oauth_tokens: %{"access_token" => "must-not-be-stored"}}
      )

  test "unverified and missing GitHub emails cannot register or take over existing users" do
    existing = user("existing-github@example.com")

    assert {:error, _} =
             github(%{
               "sub" => "unverified",
               "email" => to_string(existing.email),
               "email_verified" => false
             })

    assert {:error, _} = github(%{"sub" => "missing", "email_verified" => true})
    assert Ash.count!(App.Accounts.UserIdentity, authorize?: false) == 0
  end

  test "verified GitHub registration signs in immediately and stores no OAuth tokens" do
    assert {:ok, user} =
             github(%{
               "sub" => "new-subject",
               "email" => "github-new@example.com",
               "email_verified" => true,
               "name" => "GitHub user",
               "picture" => "https://avatars.githubusercontent.com/u/123"
             })

    assert user.avatar_url == "https://avatars.githubusercontent.com/u/123"
    assert user.confirmed_at
    assert App.Accounts.active_user(user)
    [identity] = Ash.read!(App.Accounts.UserIdentity, authorize?: false)
    assert identity.user_id == user.id
    refute identity.access_token
    refute identity.refresh_token
    refute_receive {:email, _}

    assert {:ok, returning} =
             github(%{
               "sub" => "new-subject",
               "email" => "github-new@example.com",
               "email_verified" => true
             })

    assert returning.id == user.id
  end

  test "a verified primary GitHub email can link to the same email-code account" do
    existing = user("link@example.com")

    assert {:ok, linked} =
             github(%{
               "sub" => "verified-link",
               "email" => "link@example.com",
               "email_verified" => true
             })

    assert linked.id == existing.id
    assert Ash.count!(User, authorize?: false) == 1

    assert {:error, _} =
             github(%{
               "sub" => "different-github",
               "email" => "link@example.com",
               "email_verified" => true
             })
  end

  test "verified GitHub email can confirm a legacy account, without confirming a different stored email" do
    existing = user("legacy@example.com")
    App.Repo.query!("UPDATE users SET confirmed_at=NULL WHERE email=$1", ["legacy@example.com"])

    assert {:ok, confirmed} =
             github(%{
               "sub" => "legacy-provider",
               "email" => "legacy@example.com",
               "email_verified" => true
             })

    assert confirmed.id == existing.id
    assert App.Accounts.active_user(confirmed)

    assert {:ok, returning} =
             github(%{
               "sub" => "legacy-provider",
               "email" => "changed@example.com",
               "email_verified" => true
             })

    assert returning.id == existing.id
    assert to_string(returning.email) == "legacy@example.com"
    assert returning.confirmed_at == confirmed.confirmed_at
  end

  test "HTTP authentication attempts have a shared IP budget" do
    for _ <- 1..60, do: assert(App.Accounts.RateLimit.allow_auth_ip?("192.0.2.99"))
    refute App.Accounts.RateLimit.allow_auth_ip?("192.0.2.99")
  end
end
