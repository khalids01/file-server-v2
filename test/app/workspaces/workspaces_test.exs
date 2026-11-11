defmodule App.WorkspacesTest do
  use App.DataCase, async: true
  import App.AuthHelpers
  alias App.Workspaces
  alias App.Workspaces.{Application, ApplicationKey}

  test "onboarding is idempotent and only owned workspaces are visible" do
    owner = user("tenant-owner@example.com")
    other = user("tenant-other@example.com")
    first = Workspaces.ensure_personal!(owner)
    assert Workspaces.ensure_personal!(owner).id == first.id
    second = Workspaces.create_tenant!(owner, "Second workspace")

    assert Enum.sort(Enum.map(Workspaces.tenants(owner), & &1.id)) ==
             Enum.sort([first.id, second.id])

    assert Workspaces.tenants(other) == []
    assert {:error, _} = Ash.get(Workspaces.Tenant, first.id, actor: other)
  end

  test "tenant scope is required and cross-tenant application/key injection is rejected" do
    owner = user("scope-owner@example.com")
    outsider = user("scope-other@example.com")
    a = Workspaces.ensure_personal!(owner)
    b = Workspaces.create_tenant!(owner, "Other owned workspace")

    app =
      Ash.create!(Application, %{name: "Project", slug: "project"}, actor: owner, tenant: a.id)

    assert {:error, _} = Ash.read(Application, actor: owner)
    assert Ash.read!(Application, actor: owner, tenant: b.id) == []

    assert {:error, _} =
             Ash.create(Application, %{name: "Intrusion", slug: "intrusion"},
               actor: outsider,
               tenant: a.id
             )

    assert {:error, _} =
             Ash.create(
               ApplicationKey,
               %{
                 name: "Bad key",
                 application_id: app.id,
                 key_hash: "forged",
                 fingerprint: "forged"
               },
               actor: owner,
               tenant: b.id
             )

    assert_raise Ash.Error.Invalid, fn ->
      Workspaces.issue_key!(owner, b.id, app.id, "Wrong scope", ["files:read"])
    end
  end

  test "application key has explicit scopes, cannot cross apps, and revokes immediately" do
    owner = user("keys-owner@example.com")
    other = user("keys-other@example.com")
    tenant = Workspaces.ensure_personal!(owner)

    app =
      Ash.create!(Application, %{name: "Project", slug: "project"},
        actor: owner,
        tenant: tenant.id
      )

    {key, raw} = Workspaces.issue_key!(owner, tenant.id, app.id, "Read key", ["files:read"])
    assert key.user_id == owner.id
    refute key.key_hash == raw
    assert {:ok, %{application: authenticated}} = Workspaces.authenticate_key(raw, "files:read")
    assert authenticated.id == app.id
    assert {:error, _} = Workspaces.authenticate_key(raw, "files:delete")
    assert {:error, _} = Ash.update(key, %{}, action: :revoke, actor: other, tenant: tenant.id)
    Ash.update!(key, %{}, action: :revoke, actor: owner, tenant: tenant.id)
    assert {:error, _} = Workspaces.authenticate_key(raw, "files:read")
  end
end
