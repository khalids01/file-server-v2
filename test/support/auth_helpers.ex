defmodule App.AuthHelpers do
  import ExUnit.Assertions

  def request_magic_link(email) do
    strategy = AshAuthentication.Info.strategy!(App.Accounts.User, :magic_link)
    assert :ok = AshAuthentication.Strategy.action(strategy, :request, %{email: email})
    assert_receive {:email, message}
    [_, token] = Regex.run(~r{/magic_link/([^\s]+)}, message.text_body)
    {strategy, token}
  end

  def user(email) do
    {strategy, token} = request_magic_link(email)
    {:ok, user} = AshAuthentication.Strategy.action(strategy, :sign_in, %{token: token})
    user
  end

  def api_key(user, seconds \\ 3600) do
    App.Accounts.ApiKey
    |> Ash.Changeset.for_create(:create, %{expires_at: DateTime.add(DateTime.utc_now(), seconds)},
      actor: user
    )
    |> Ash.create!()
  end
end
