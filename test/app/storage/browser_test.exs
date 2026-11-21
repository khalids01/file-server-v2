defmodule App.Storage.BrowserTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  import Phoenix.LiveViewTest
  alias App.Storage
  alias App.Storage.Browser

  setup %{conn: conn} do
    root = Path.join(System.tmp_dir!(), "serve-browser-#{Ecto.UUID.generate()}")
    previous = Application.get_env(:app, :local_storage_path)
    options = Application.get_env(:app, :storage_s3_request_options)
    Application.put_env(:app, :local_storage_path, root)
    Application.put_env(:app, :storage_s3_request_options, plug: {Req.Test, :browser_s3})
    File.mkdir_p!(root)
    source = Path.join(root, "source.txt")
    File.write!(source, "test bytes")
    owner = user("browser-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Browser app", slug: "browser"},
        actor: owner
      )

    {:ok, file} = Storage.upload(owner, app.id, source, "hello.txt", "text/plain")

    {:ok, connection} =
      Storage.create_connection(owner, app.id, %{
        "name" => "IDrive fixture",
        "endpoint" => "https://s3.ap-northeast-1.idrivee2.com",
        "region" => "ap-northeast-1",
        "bucket" => "browser-fixture",
        "access_key_id" => "fixture-key",
        "secret_access_key" => "fixture-secret"
      })

    login =
      conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(owner)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)

      if options,
        do: Application.put_env(:app, :storage_s3_request_options, options),
        else: Application.delete_env(:app, :storage_s3_request_options)

      File.rm_rf!(root)
    end)

    %{root: root, owner: owner, app: app, stored_file: file, connection: connection, login: login}
  end

  defp connection_attrs(app_id) do
    %{
      "application_id" => app_id,
      "name" => "New IDrive storage",
      "endpoint" => "https://s3.ap-northeast-1.idrivee2.com",
      "region" => "ap-northeast-1",
      "bucket" => "new-fixture",
      "access_key_id" => "new-fixture-key",
      "secret_access_key" => "new-fixture-secret"
    }
  end

  test "Storage connects S3 directly and displays the saved connection without provider calls",
       c do
    {:ok, view, _} = live(c.login, "/dashboard/storage")
    view |> element("#storage-connect-s3") |> render_click()
    assert has_element?(view, "#storage-connect-form")
    view |> form("#storage-connect-form", storage: connection_attrs(c.app.id)) |> render_submit()
    refute has_element?(view, "#storage-connect-dialog")
    connections = Storage.connections(c.owner, c.app.id)
    connection = Enum.find(connections, &(&1.name == "New IDrive storage"))
    assert connection
    assert has_element?(view, "#storage-drive-#{connection.id}", "New IDrive storage")
    assert has_element?(view, "#flash-info", "S3 connection saved")
    refute render(view) =~ "new-fixture-key"
    refute render(view) =~ "new-fixture-secret"
    assert {:ok, plaintext} = App.Vault.decrypt(connection.credentials)
    assert Jason.decode!(plaintext)["secret_access_key"] == "new-fixture-secret"

    assert Ash.get!(App.Applications.Application, c.app.id, actor: c.owner).storage_connection_id ==
             nil
  end

  test "Storage connection errors preserve public fields and reject foreign applications", c do
    {:ok, view, _} = live(c.login, "/dashboard/storage")
    view |> element("#storage-connect-s3") |> render_click()
    attrs = Map.put(connection_attrs(c.app.id), "endpoint", "http://127.0.0.1")
    view |> form("#storage-connect-form", storage: attrs) |> render_submit()
    assert has_element?(view, "#storage-connect-error")
    assert has_element?(view, "input[name='storage[name]'][value='New IDrive storage']")
    refute render(view) =~ "new-fixture-secret"
    outsider = user("connect-other-#{Ecto.UUID.generate()}@example.com")

    other =
      Ash.create!(App.Applications.Application, %{name: "Other", slug: "other"}, actor: outsider)

    render_hook(view, "create_storage", %{"storage" => connection_attrs(other.id)})
    assert has_element?(view, "#storage-connect-error")
    assert Storage.connections(outsider, other.id) == []
    assert length(Storage.connections(c.owner, c.app.id)) == 1
    view |> element("#storage-connect-dialog button[phx-click='close_storage']") |> render_click()
    refute has_element?(view, "#storage-connect-dialog")
  end

  test "Connect S3 is discoverable before the first application exists", c do
    owner = user("connect-empty-#{Ecto.UUID.generate()}@example.com")

    login =
      build_conn()
      |> init_test_session(%{})
      |> AshAuthentication.Phoenix.Plug.store_in_session(owner)

    {:ok, view, _} = live(login, "/dashboard/storage")
    view |> element("#storage-connect-s3") |> render_click()
    assert has_element?(view, "#storage-connect-no-app a[href='/dashboard/applications']")
    refute has_element?(view, "#storage-connect-form")
    render_hook(view, "create_storage", %{"storage" => connection_attrs(c.app.id)})
    assert {:ok, []} = Browser.drives(owner)
  end

  test "drive catalog and physical local listings stay owner scoped", c do
    {:ok, drives} = Browser.drives(c.owner)
    assert Enum.any?(drives, &(&1.id == c.connection.id))
    refute inspect(drives) =~ "fixture-secret"
    {:ok, page} = Browser.browse(c.owner, "local-" <> c.app.id)
    assert [%{name: name, size: 10, type: :file}] = page.entries
    assert name == c.stored_file.id
    outsider = user("outside-#{Ecto.UUID.generate()}@example.com")
    assert {:ok, []} = Browser.drives(outsider)
    assert {:error, _} = Browser.browse(outsider, c.connection.id)
    assert {:error, _} = Browser.browse(outsider, "local-" <> c.app.id)
    assert {:error, _} = Browser.browse(c.owner, "not-a-drive")
  end

  test "local browse rejects traversal and symlinks and pages actual entries", c do
    directory = Path.join([c.root, c.owner.id, c.app.id])
    File.ln_s!(System.tmp_dir!(), Path.join(directory, "escape"))

    for prefix <- ["../", "/", "x/../../", "escape/", "x\\y/", "x//"] do
      assert {:error, _} = Browser.browse(c.owner, "local-" <> c.app.id, prefix)
    end

    for i <- 1..101, do: File.write!(Path.join(directory, "object-#{i}"), "x")
    {:ok, first} = Browser.browse(c.owner, "local-" <> c.app.id)
    assert first.next_cursor == "100"
    refute Enum.any?(first.entries, &(&1.name == "escape/"))
    {:ok, second} = Browser.browse(c.owner, "local-" <> c.app.id, "", first.next_cursor)
    assert second.next_cursor == nil
    assert length(first.entries ++ second.entries) == 102
    File.mkdir_p!(Path.join(directory, "folder"))
    File.write!(Path.join(directory, "folder/nested"), "nested")

    assert {:ok, %{entries: [%{name: "nested"}]}} =
             Browser.browse(c.owner, "local-" <> c.app.id, "folder/")

    assert {:error, _} = Browser.browse(c.owner, "local-" <> c.app.id, "", "bad")
    held = c.root <> "-held"
    File.rename!(c.root, held)
    File.ln_s!(held, c.root)
    on_exit(fn -> File.rm_rf!(held) end)
    assert {:error, _} = Browser.browse(c.owner, "local-" <> c.app.id)
  end

  test "S3 lists signed namespace-only entries, decoded names, folders and cursor", c do
    prefix = c.owner.id <> "/" <> c.app.id <> "/"

    Req.Test.stub(:browser_s3, fn conn ->
      query = URI.decode_query(conn.query_string)
      assert query["list-type"] == "2"
      assert query["prefix"] == prefix
      assert query["max-keys"] == "100"
      assert query["delimiter"] == "/"
      assert query["encoding-type"] == "url"
      assert query["continuation-token"] == "opaque=="
      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert authorization =~ "AWS4-HMAC-SHA256"

      body = """
      <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Contents><Key>#{URI.encode(prefix <> "hello file.txt", &URI.char_unreserved?/1)}</Key><Size>4</Size></Contents>
      <Contents><Key>other-owner/private</Key><Size>9</Size></Contents>
      <Contents><Key>#{URI.encode(prefix <> "../escape", &URI.char_unreserved?/1)}</Key><Size>9</Size></Contents>
      <CommonPrefixes><Prefix>#{URI.encode(prefix <> "folder/", &URI.char_unreserved?/1)}</Prefix></CommonPrefixes>
      <IsTruncated>true</IsTruncated><NextContinuationToken>next==</NextContinuationToken>
      </ListBucketResult>
      """

      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert {:ok, %{entries: entries, next_cursor: "next=="}} =
             Browser.browse(c.owner, c.connection.id, "", "opaque==")

    assert %{name: "hello file.txt", type: :file, size: 4} in entries
    assert %{name: "folder/", type: :folder, size: 0} in entries
    assert length(entries) == 2
  end

  test "S3 malformed, oversized, external entity and provider errors stay generic", c do
    for body <- [
          "<broken>",
          "<Other/>",
          "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><ListBucketResult>&e;</ListBucketResult>",
          String.duplicate("x", 1_048_577)
        ] do
      Req.Test.stub(:browser_s3, fn conn -> Plug.Conn.send_resp(conn, 200, body) end)
      assert {:error, :unavailable} = Browser.browse(c.owner, c.connection.id)
    end

    Req.Test.stub(:browser_s3, fn conn -> Plug.Conn.send_resp(conn, 403, "provider-secret") end)
    assert {:error, :unavailable} = Browser.browse(c.owner, c.connection.id)
    App.Repo.query!("UPDATE users SET banned=true WHERE id=$1", [Ecto.UUID.dump!(c.owner.id)])
    assert {:error, _} = Browser.browse(c.owner, c.connection.id)
  end

  test "Storage sidebar, cards, async local browsing and errors render safely", c do
    {:ok, view, _} = live(c.login, "/dashboard/storage")
    assert has_element?(view, "#app-sidebar a[href='/dashboard/files']")
    assert has_element?(view, "#app-sidebar a[href='/dashboard/storage']")
    assert has_element?(view, "#storage-drive-#{c.connection.id}", "IDrive fixture")
    {:ok, browser, _} = live(c.login, "/dashboard/storage/local-#{c.app.id}")
    render_async(browser)
    assert has_element?(browser, "#storage-objects", c.stored_file.id)
    refute render(browser) =~ c.root
    refute render(browser) =~ "fixture-secret"
    assert :ok = Storage.delete(c.owner, c.stored_file.id)

    case :sys.get_state(browser.pid).socket.assigns.refresh_pending do
      nil -> :ok
      token -> send(browser.pid, {:refresh_storage, token})
    end

    _ = render(browser)
    render_async(browser)
    refute has_element?(browser, "#storage-objects", c.stored_file.id)
    render_patch(browser, "/dashboard/storage/not-a-drive")
    render_async(browser)
    assert has_element?(browser, "#storage-browser-error")
  end
end
