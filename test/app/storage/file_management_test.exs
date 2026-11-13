defmodule App.Storage.FileManagementTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  alias App.Storage
  alias App.Storage.FileManagement, as: Files

  setup do
    root = Path.join(System.tmp_dir!(), "serve-manage-#{Ecto.UUID.generate()}")
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)
    File.mkdir_p!(root)
    source = Path.join(root, "source.txt")
    File.write!(source, "management fixture")
    owner = user("manage-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Manage", slug: "manage"}, actor: owner)

    app2 =
      Ash.create!(App.Applications.Application, %{name: "Other", slug: "other"}, actor: owner)

    {:ok, file} = Storage.upload(owner, app.id, source, "one.txt", "text/plain", tags: ["First"])
    {:ok, other} = Storage.upload(owner, app2.id, source, "other.txt", "text/plain")

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    %{owner: owner, app: app, stored: file, other: other}
  end

  test "details reject same-owner cross-application and foreign actors", c do
    assert {:ok, _} = Files.details(c.owner, c.app.id, c.stored.id)
    assert {:error, :not_found} = Files.details(c.owner, c.app.id, c.other.id)
    outsider = user("manage-outsider@example.com")
    assert {:error, :not_found} = Files.details(outsider, c.app.id, c.stored.id)
  end

  test "bulk add remove and replace validate combined tags and ignore case", c do
    assert {:ok, %{succeeded: [_], failed: []}} =
             Files.bulk(c.owner, c.app.id, [c.stored.id], {:add, ["first", "Second"]})

    assert {:ok, %{tags: ["First", "Second"]}} = Files.details(c.owner, c.app.id, c.stored.id)

    assert {:ok, %{failed: []}} =
             Files.bulk(c.owner, c.app.id, [c.stored.id], {:remove, ["FIRST"]})

    assert {:ok, %{tags: ["Second"]}} = Files.details(c.owner, c.app.id, c.stored.id)
    assert {:ok, %{failed: []}} = Files.bulk(c.owner, c.app.id, [c.stored.id], {:replace, []})
    assert {:ok, %{tags: []}} = Files.details(c.owner, c.app.id, c.stored.id)

    assert {:error, :invalid_tags} =
             Files.bulk(c.owner, c.app.id, [c.stored.id], {:add, ["bad\nline"]})

    Storage.update_tags(c.owner, c.app.id, c.stored.id, Enum.map(1..20, &"tag-#{&1}"))

    assert {:ok, %{succeeded: [], failed: [%{reason: {:invalid_tags, _}}]}} =
             Files.bulk(c.owner, c.app.id, [c.stored.id], {:add, ["extra"]})
  end

  test "bulk selection is bounded and forged application IDs cannot delete", c do
    assert {:error, :invalid_selection} = Files.bulk(c.owner, c.app.id, [], :delete)

    assert {:error, :invalid_selection} =
             Files.bulk(c.owner, c.app.id, [c.stored.id, c.stored.id], :delete)

    assert {:error, :invalid_selection} = Files.bulk(c.owner, c.app.id, ["forged"], :delete)

    assert {:error, :invalid_selection} =
             Files.bulk(c.owner, c.app.id, [c.stored.id, String.upcase(c.stored.id)], :delete)

    assert {:error, :invalid_selection} =
             Files.bulk(
               c.owner,
               c.app.id,
               Enum.map(1..26, fn _ -> Ecto.UUID.generate() end),
               :delete
             )

    assert {:ok, %{succeeded: [id], failed: [%{id: denied}]}} =
             Files.bulk(c.owner, c.app.id, [c.stored.id, c.other.id], :delete)

    assert id == c.stored.id and denied == c.other.id
    assert {:ok, _} = Storage.download(c.owner, c.other.id)
    assert Storage.Quota.status_for_user(c.owner.id).used_bytes == c.other.size
  end

  test "physical deletion failure reports partial success and preserves accounting", c do
    {:ok, path} = Storage.Local.path(c.stored.object_key)
    File.rm!(path)
    File.ln_s!("/nonexistent-fixture-target", path)

    assert {:ok, %{succeeded: [], failed: [_]}} =
             Files.bulk(c.owner, c.app.id, [c.stored.id], :delete)

    assert Storage.Quota.status_for_user(c.owner.id).used_bytes == c.stored.size + c.other.size
  end
end
