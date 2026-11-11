defmodule App.Accounts.AuthenticationTest do
  use App.DataCase, async: true
  import App.AuthHelpers

  test "magic link registers a user, signs in again, and cannot be replayed" do
    {strategy, token} = request_magic_link("magic@example.com")
    assert {:ok, user} = AshAuthentication.Strategy.action(strategy, :sign_in, %{token: token})
    assert to_string(user.email) == "magic@example.com"
    assert is_binary(user.__metadata__.token)
    assert {:error, _} = AshAuthentication.Strategy.action(strategy, :sign_in, %{token: token})
    assert user("magic@example.com").id == user.id

    assert {:error, _} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{token: "invalid"})
  end

  test "API keys belong to their actor and other users cannot revoke them" do
    owner = user("owner@example.com")
    other = user("other@example.com")
    key = api_key(owner)
    assert key.user_id == owner.id
    assert is_binary(key.__metadata__.plaintext_api_key)
    refute key.api_key_hash == key.__metadata__.plaintext_api_key
    assert {:error, _} = Ash.destroy(key, actor: other)
    assert :ok = Ash.destroy(key, actor: owner)
  end
end
