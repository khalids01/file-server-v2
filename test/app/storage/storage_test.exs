defmodule App.StorageTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  import Phoenix.LiveViewTest
  alias App.Storage

  setup do
    root = Path.join(System.tmp_dir!(), "serve-storage-test-" <> Ecto.UUID.generate())
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    owner = user("storage-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Storage app", slug: "storage-app"},
        actor: owner
      )

    source = Path.join(System.tmp_dir!(), "serve-source-" <> Ecto.UUID.generate())
    File.write!(source, "private file bytes")
    on_exit(fn -> File.rm(source) end)
    %{owner: owner, app: app, source: source, root: root}
  end

  defp signed_in(conn, user),
    do: conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(user)

  defp s3_attrs,
    do: %{
      "name" => "My S3",
      "endpoint" => "https://s3.ap-northeast-1.idrivee2.com",
      "bucket" => "serve-test",
      "region" => "ap-northeast-1",
      "access_key_id" => "test-access-id",
      "secret_access_key" => "test-secret-key"
    }

  test "local upload, private download and deletion preserve ownership", %{
    conn: conn,
    owner: owner,
    app: app,
    source: source
  } do
    assert :ok = Storage.test_connection(owner, app.id, nil)
    assert {:ok, file} = Storage.upload(owner, app.id, source, "../../private.txt", "text/plain")
    assert file.filename == "private.txt"
    {:ok, stored_path} = Storage.Local.path(file.object_key)
    assert Bitwise.band(File.stat!(stored_path).mode, 0o777) == 0o600
    assert Bitwise.band(File.stat!(Path.dirname(stored_path)).mode, 0o777) == 0o700
    assert file.size == byte_size("private file bytes")
    assert Storage.counts(owner)[app.id] == 1
    assert [listed] = Storage.files(owner, app.id)
    assert listed.id == file.id
    conn = signed_in(conn, owner) |> get("/files/#{file.id}/download")
    assert response(conn, 200) == "private file bytes"
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    outsider = user("storage-outsider@example.com")
    assert Storage.files(outsider, app.id) == []
    assert {:error, _} = Storage.download(outsider, file.id)
    assert {:error, _} = Storage.delete(outsider, file.id)
    assert {:error, _} = Storage.upload(outsider, app.id, source, "bad.txt", "text/plain")
    build_conn() |> signed_in(outsider) |> get("/files/#{file.id}/download") |> response(404)
    assert build_conn() |> get("/files/#{file.id}/download") |> redirected_to() == "/sign-in"
    assert :ok = Storage.delete(owner, file.id)
    assert Storage.files(owner, app.id) == []
    assert {:error, _} = Storage.download(owner, file.id)
  end

  test "path traversal and symlink destinations are rejected", %{
    owner: owner,
    app: app,
    source: source,
    root: root
  } do
    assert {:error, _} = Storage.Local.path("../../secret", true)
    File.mkdir_p!(root)
    File.ln_s!(System.tmp_dir!(), Path.join(root, owner.id))
    assert {:error, _} = Storage.upload(owner, app.id, source, "safe.txt", "text/plain")
    assert Storage.files(owner, app.id) == []
  end

  test "size limits and stale banned actors are enforced by storage service", %{
    owner: owner,
    app: app,
    source: source
  } do
    old_limit = Application.get_env(:app, :max_file_size)
    Application.put_env(:app, :max_file_size, 1)
    on_exit(fn -> Application.put_env(:app, :max_file_size, old_limit) end)
    assert {:error, _} = Storage.upload(owner, app.id, source, "large.txt", "text/plain")
    Ash.update!(owner, %{}, action: :ban, authorize?: false)
    assert {:error, _} = Storage.upload(owner, app.id, source, "banned.txt", "text/plain")
    assert {:error, _} = Storage.test_connection(owner, app.id, nil)
  end

  test "S3 credentials are encrypted and cross-application destination injection is rejected", %{
    owner: owner,
    app: app
  } do
    assert {:ok, connection} = Storage.create_connection(owner, app.id, s3_attrs())

    [[ciphertext]] =
      App.Repo.query!("SELECT credentials FROM storage_connections WHERE id=$1", [
        Ecto.UUID.dump!(connection.id)
      ]).rows

    refute :binary.match(ciphertext, "test-secret-key") != :nomatch
    assert {:ok, plaintext} = App.Vault.decrypt(ciphertext)
    assert Jason.decode!(plaintext)["secret_access_key"] == "test-secret-key"

    app2 =
      Ash.create!(App.Applications.Application, %{name: "Other app", slug: "other-app"},
        actor: owner
      )

    assert {:error, _} = Ash.update(app2, %{storage_connection_id: connection.id}, actor: owner)
    outsider = user("s3-outsider@example.com")
    assert {:error, _} = Storage.create_connection(outsider, app.id, s3_attrs())
    assert {:error, _} = Ash.get(Storage.Connection, connection.id, actor: outsider)

    assert {:error, _} =
             Storage.create_connection(
               owner,
               app.id,
               Map.put(s3_attrs(), "endpoint", "http://127.0.0.1:8000")
             )
  end

  test "S3 upload/download/delete are signed and stored files retain their destination", %{
    owner: owner,
    app: app,
    source: source
  } do
    old = Application.get_env(:app, :storage_s3_request_options)
    Application.put_env(:app, :storage_s3_request_options, plug: {Req.Test, :storage_s3})

    on_exit(fn ->
      if old,
        do: Application.put_env(:app, :storage_s3_request_options, old),
        else: Application.delete_env(:app, :storage_s3_request_options)
    end)

    objects = start_supervised!({Agent, fn -> %{} end})

    Req.Test.stub(:storage_s3, fn conn ->
      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert authorization =~ "AWS4-HMAC-SHA256"
      path = conn.request_path
      assert String.starts_with?(path, "/serve-test/")

      case conn.method do
        "PUT" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          Agent.update(objects, &Map.put(&1, path, body))
          Plug.Conn.send_resp(conn, 200, "")

        "GET" ->
          Plug.Conn.send_resp(conn, 200, Agent.get(objects, &Map.fetch!(&1, path)))

        "HEAD" ->
          Plug.Conn.send_resp(conn, 200, "")

        "DELETE" ->
          Agent.update(objects, &Map.delete(&1, path))
          Plug.Conn.send_resp(conn, 204, "")
      end
    end)

    {:ok, connection} = Storage.create_connection(owner, app.id, s3_attrs())
    assert :ok = Storage.test_connection(owner, app.id, connection.id)
    assert Agent.get(objects, &map_size/1) == 0
    Ash.update!(app, %{storage_connection_id: connection.id}, actor: owner)
    assert {:ok, file} = Storage.upload(owner, app.id, source, "cloud.txt", "text/plain")
    assert file.connection_id == connection.id
    Ash.update!(app, %{storage_connection_id: nil}, actor: owner)
    assert {:ok, download} = Storage.download(owner, file.id)
    assert download.temporary?
    assert Bitwise.band(File.stat!(download.path).mode, 0o777) == 0o600
    assert File.read!(download.path) == "private file bytes"
    File.rm!(download.path)
    assert :ok = Storage.delete(owner, file.id)
    assert Agent.get(objects, &map_size/1) == 0
  end

  test "S3 failures preserve metadata and oversized downloads are rejected", %{
    owner: owner,
    app: app,
    source: source
  } do
    previous = Application.get_env(:app, :storage_s3_request_options)
    Application.put_env(:app, :storage_s3_request_options, plug: {Req.Test, :storage_failure})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:app, :storage_s3_request_options, previous),
        else: Application.delete_env(:app, :storage_s3_request_options)
    end)

    {:ok, connection} = Storage.create_connection(owner, app.id, s3_attrs())
    Ash.update!(app, %{storage_connection_id: connection.id}, actor: owner)

    Req.Test.stub(:storage_failure, fn conn -> Plug.Conn.send_resp(conn, 403, "Access denied") end)

    assert {:error, _} = Storage.upload(owner, app.id, source, "failed.txt", "text/plain")
    assert Storage.files(owner, app.id) == []
    Req.Test.stub(:storage_failure, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)
    {:ok, file} = Storage.upload(owner, app.id, source, "saved.txt", "text/plain")

    Req.Test.stub(:storage_failure, fn conn ->
      Plug.Conn.send_resp(conn, 200, String.duplicate("x", 100_000))
    end)

    assert {:error, _} = Storage.download(owner, file.id)
    Req.Test.stub(:storage_failure, fn conn -> Plug.Conn.send_resp(conn, 503, "Unavailable") end)
    assert {:error, _} = Storage.delete(owner, file.id)
    assert [remaining] = Storage.files(owner, app.id)
    assert remaining.id == file.id
  end

  test "S3 settings dialog clears secrets after saving and local test runs asynchronously", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    {:ok, view, _} = live(signed_in(conn, owner), "/dashboard/applications/#{app.id}")
    view |> element("#test-storage") |> render_click()
    render_async(view)
    assert has_element?(view, "#flash-info", "Storage connection is working")
    view |> element("#connect-s3") |> render_click()
    view |> form("#storage-connection-form", storage: s3_attrs()) |> render_submit()
    refute has_element?(view, "#storage-connection-dialog")
    assert has_element?(view, "#application-storage [data-select-label]", "My S3")
    refute render(view) =~ "test-secret-key"
    refute render(view) =~ "test-access-id"
    [connection] = Storage.connections(owner, app.id)

    assert Ash.get!(App.Applications.Application, app.id, actor: owner).storage_connection_id ==
             connection.id
  end

  test "environment configuration is copied into an encrypted immutable destination", %{
    owner: owner,
    app: app
  } do
    previous = Application.get_env(:app, :storage_environment)
    attrs = s3_attrs()

    env = %{
      "S3_ENDPOINT" => attrs["endpoint"],
      "S3_BUCKET" => attrs["bucket"],
      "S3_REGION" => attrs["region"],
      "S3_ACCESS_KEY_ID" => attrs["access_key_id"],
      "S3_SECRET_ACCESS_KEY" => attrs["secret_access_key"]
    }

    Application.put_env(:app, :storage_environment, env)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:app, :storage_environment, previous),
        else: Application.delete_env(:app, :storage_environment)
    end)

    assert Storage.environment_available?()
    assert {:ok, destination} = Storage.environment_connection(owner, app.id)
    Application.put_env(:app, :storage_environment, %{})
    refute Storage.environment_available?()
    assert destination.bucket == attrs["bucket"]

    assert Jason.decode!(App.Vault.decrypt!(destination.credentials))["secret_access_key"] ==
             attrs["secret_access_key"]
  end

  test "endpoint validation rejects credentials, queries, private URLs and lookalike provider hosts" do
    for endpoint <- [
          "http://127.0.0.1:9000",
          "https://169.254.169.254",
          "https://evil-idrivee2.com",
          "https://s3.idrivee2.com.attacker.test",
          "https://key:secret@s3.idrivee2.com",
          "https://s3.idrivee2.com?token=secret",
          "https://s3.idrivee2.com/bucket"
        ] do
      assert {:error, _} = Storage.Endpoint.validate(endpoint)
    end

    assert {:ok, "https://s3.ap-northeast-1.idrivee2.com"} =
             Storage.Endpoint.validate("https://s3.ap-northeast-1.idrivee2.com/")
  end

  test "only an operator's configured custom hosts permit private MinIO endpoints" do
    previous = Application.get_env(:app, :s3_allowed_hosts)
    Application.put_env(:app, :s3_allowed_hosts, ["minio.internal"])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:app, :s3_allowed_hosts, previous),
        else: Application.delete_env(:app, :s3_allowed_hosts)
    end)

    assert {:ok, "http://minio.internal:9000"} =
             Storage.Endpoint.validate("http://minio.internal:9000")

    assert {:error, _} = Storage.Endpoint.validate("http://other.internal:9000")
  end

  test "LiveView uploads and deletes a local file through shared controls", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    {:ok, view, _} = live(signed_in(conn, owner), "/dashboard/applications/#{app.id}?tab=files")

    upload =
      file_input(view, "#upload-files", :documents, [
        %{name: "hello.txt", content: "Hello from LiveView", type: "text/plain"}
      ])

    assert render_upload(upload, "hello.txt") =~ "hello.txt"
    view |> form("#upload-files") |> render_submit()
    assert has_element?(view, "#stored-files", "hello.txt")
    [file] = Storage.files(owner, app.id)
    assert {:ok, download} = Storage.download(owner, file.id)
    assert File.read!(download.path) == "Hello from LiveView"
    view |> element("#stored-files button[aria-label='Delete hello.txt']") |> render_click()
    view |> element("#confirm-delete-file") |> render_click()
    assert has_element?(view, "#files-empty")
    assert Storage.files(owner, app.id) == []
  end
end
