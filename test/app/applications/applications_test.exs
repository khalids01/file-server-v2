defmodule App.ApplicationsTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Applications
  alias App.Applications.{Application, ApplicationKey}

  test "applications belong directly to their creator and are isolated between users" do
    owner = user("app-owner@example.com")
    outsider = user("app-outsider@example.com")
    app = Ash.create!(Application, %{name: "Project", slug: "project"}, actor: owner)
    assert app.user_id == owner.id
    assert Enum.map(Applications.applications(owner), & &1.id) == [app.id]
    assert Applications.applications(outsider) == []
    assert {:error, _} = Ash.get(Application, app.id, actor: outsider)
    assert {:error, _} = Ash.update(app, %{name: "Intrusion"}, actor: outsider)
    assert {:error, _} = Ash.create(Application, %{name: "No actor", slug: "no-actor"})

    assert {:error, _} =
             Ash.create(Application, %{name: "Duplicate", slug: "project"}, actor: owner)

    assert Ash.create!(Application, %{name: "Other project", slug: "project"}, actor: outsider).user_id ==
             outsider.id
  end

  test "an outsider cannot inject an application into their API key" do
    owner = user("inject-owner@example.com")
    outsider = user("inject-outsider@example.com")
    app = Ash.create!(Application, %{name: "Project", slug: "project"}, actor: owner)

    assert {:error, _} =
             Ash.create(
               ApplicationKey,
               %{
                 name: "Bad key",
                 application_id: app.id,
                 key_hash: "forged",
                 fingerprint: "forged"
               },
               actor: outsider
             )
  end

  test "keys enforce application ownership, scope, expiry, revocation and bans" do
    owner = user("keys-owner@example.com")
    other = user("keys-other@example.com")
    app = Ash.create!(Application, %{name: "Project", slug: "project"}, actor: owner)
    {key, raw} = Applications.issue_key!(owner, app.id, "Read key", ["files:read"])
    assert key.user_id == owner.id
    refute key.key_hash == raw
    assert {:ok, %{application: authenticated}} = Applications.authenticate_key(raw, "files:read")
    assert authenticated.id == app.id
    assert {:error, _} = Applications.authenticate_key(raw, "files:delete")
    assert {:error, _} = Ash.update(key, %{}, action: :revoke, actor: other)
    Ash.update!(key, %{}, action: :revoke, actor: owner)
    assert {:error, _} = Applications.authenticate_key(raw, "files:read")
    {_key, expiring} = Applications.issue_key!(owner, app.id, "Expired key", ["files:read"])

    App.Repo.query!(
      "UPDATE application_keys SET expires_at=now()-interval '1 minute' WHERE fingerprint=$1",
      [String.slice(expiring, -6, 6)]
    )

    assert {:error, _} = Applications.authenticate_key(expiring, "files:read")
    {_key, banned} = Applications.issue_key!(owner, app.id, "Banned key", ["files:read"])
    Ash.update!(owner, %{}, action: :ban, authorize?: false)
    assert {:error, _} = Applications.authenticate_key(banned, "files:read")

    assert {:error, _} =
             Ash.create(Application, %{name: "Banned project", slug: "banned-project"},
               actor: owner
             )
  end
end
