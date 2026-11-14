defmodule AppWeb.StorageInsightsTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  import Phoenix.LiveViewTest
  alias App.Storage
  alias App.Storage.Insights

  setup %{conn: conn} do
    root = Path.join(System.tmp_dir!(), "serve-insights-#{Ecto.UUID.generate()}")
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)
    File.mkdir_p!(root)
    source = Path.join(root, "source.txt")
    File.write!(source, "insights fixture")
    owner = user("insights-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Insights", slug: "insights"},
        actor: owner
      )

    other =
      Ash.create!(App.Applications.Application, %{name: "Other", slug: "other"}, actor: owner)

    {:ok, a} = Storage.upload(owner, app.id, source, "one.txt", "text/plain")
    {:ok, b} = Storage.upload(owner, other.id, source, "other.txt", "text/plain")

    login =
      conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(owner)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    %{owner: owner, app: app, other: other, a: a, b: b, root: root, source: source, login: login}
  end

  test "totals are scoped, include actual variants, and avoid multiplying originals", c do
    image_path = Path.join(c.root, "image.png")
    {:ok, image} = Image.new(64, 40, color: :red)
    {:ok, _} = Image.write(image, image_path)
    {:ok, img} = Storage.upload(c.owner, c.app.id, image_path, "image.png", "image/png")
    assert :ok = Storage.process_image(img.id)
    {:ok, processed} = Ash.get(Storage.StoredFile, img.id, actor: c.owner, load: [:variants])
    {:ok, %{metrics: metrics}} = Insights.application(c.owner, c.app.id)
    assert metrics.files == 2
    assert metrics.original_bytes == c.a.size + img.size
    assert metrics.variant_bytes == Enum.sum(Enum.map(processed.variants, & &1.size))
    {:ok, account} = Insights.account(c.owner)
    assert account.totals.files == 3
    assert account.quota.used_bytes == metrics.original_bytes + metrics.variant_bytes + c.b.size
    outsider = user("insights-outsider@example.com")
    assert {:error, _} = Insights.application(outsider, c.app.id)
    assert {:ok, %{totals: %{files: 0}}} = Insights.account(outsider)
    assert {:error, _} = Insights.retry(c.owner, c.app.id, c.b.id)
  end

  test "live usage updates on upload and actual cleanup, with safe recovery feedback", c do
    {:ok, path} = Storage.Local.path(c.a.object_key)
    File.rm!(path)
    File.ln_s!("/nonexistent-insights-fixture", path)
    assert {:error, _} = Storage.delete(c.owner, c.a.id)
    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=usage")
    assert has_element?(view, "#usage-file-count", "1")
    assert has_element?(view, "#usage-cleanup-pending", "1 awaiting recovery")
    assert has_element?(view, "#storage-issue-#{c.a.id}", "one.txt")
    refute has_element?(view, "#storage-issues", "other.txt")
    view |> element("#storage-issue-#{c.a.id} button") |> render_click()
    assert has_element?(view, "#flash-info", "Recovery queued")
    File.rm!(path)
    assert :ok = Storage.cleanup_delete(c.a.id)
    send(view.pid, :refresh_file_processing)
    assert has_element?(view, "#usage-file-count", "0")
    assert has_element?(view, "#usage-no-issues")
    assert has_element?(view, "#operations-guidance", "operator-managed")
    {:ok, _} = Storage.upload(c.owner, c.app.id, c.source, "new.txt", "text/plain")
    send(view.pid, :refresh_file_processing)
    assert has_element?(view, "#usage-file-count", "1")
  end

  test "failed images stay available and retry queues real processing state", c do
    {:ok, img} = Storage.upload(c.owner, c.app.id, c.source, "invalid.png", "image/png")
    assert :ok = Storage.process_image(img.id)
    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=usage")
    assert has_element?(view, "#usage-image-failed", "1 image failures")
    render_hook(view, "retry_storage_issue", %{"id" => c.b.id})
    assert has_element?(view, "#flash-error", "Unable to queue")
    view |> element("#storage-issue-#{img.id} button") |> render_click()
    assert has_element?(view, "#usage-image-pending", "1 images queued")
    assert has_element?(view, "#usage-image-failed", "0 image failures")
    assert {:ok, _} = Storage.download(c.owner, img.id)
  end

  test "application usage API exposes only credential application and requires read scope", c do
    {_, key} = App.Applications.issue_key!(c.owner, c.app.id, "Usage", ["files:read"])

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> key)
      |> get("/api/v2/application/usage")

    data = json_response(conn, 200)["data"]
    assert data["files"] == 1
    assert data["originalBytes"] == c.a.size
    assert data["applicationId"] == c.app.id
    refute Map.has_key?(data, "quota")
    refute Map.has_key?(data, "issues")
    {_, write} = App.Applications.issue_key!(c.owner, c.app.id, "Write", ["files:write"])

    build_conn()
    |> put_req_header("authorization", "Bearer " <> write)
    |> get("/api/v2/application/usage")
    |> response(403)

    build_conn() |> get("/api/v2/application/usage") |> response(401)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> key)
    |> get("/api/v2/application/usage?id=#{c.other.id}")
    |> response(400)
  end

  test "overview and application cards show current usage and private health probes", c do
    {:ok, view, _} = live(c.login, "/dashboard")
    assert has_element?(view, "#account-usage-summary", "2")
    assert :ok = Storage.delete(c.owner, c.a.id)
    send(view.pid, :refresh_file_processing)
    {:ok, account} = Insights.account(c.owner)
    assert account.totals.files == 1
    assert render(view) =~ "Account storage"
    {:ok, apps, _} = live(c.login, "/dashboard/applications")
    assert has_element?(apps, "a[aria-label='Usage for Insights']")
    assert build_conn() |> get("/health/live") |> json_response(200) == %{"status" => "ok"}
    assert build_conn() |> get("/health/ready") |> json_response(200) == %{"status" => "ready"}
  end

  test "active pending uploads retain reservations and become recoverable only when stale", c do
    held = c.root <> "-held"
    File.rename!(c.root, held)
    on_exit(fn -> File.rm_rf(held) end)
    File.write!(c.root, "blocked storage root")

    assert {:error, _} =
             Storage.upload(
               c.owner,
               c.app.id,
               Path.join(held, "source.txt"),
               "pending.txt",
               "text/plain"
             )

    {:ok, current} = Insights.application(c.owner, c.app.id)
    assert current.metrics.reserved_bytes == c.a.size
    assert current.metrics.upload_pending == 1
    assert current.metrics.cleanup_pending == 0
    assert current.issues == []

    pending =
      Ash.read!(Storage.StoredFile, authorize?: false) |> Enum.find(&(&1.status == "pending"))

    assert {:error, :not_retryable} = Insights.retry(c.owner, c.app.id, pending.id)

    App.Repo.query!("UPDATE stored_files SET created_at=now()-interval '1 hour' WHERE id=$1", [
      Ecto.UUID.dump!(pending.id)
    ])

    {:ok, stale} = Insights.application(c.owner, c.app.id)
    assert stale.metrics.cleanup_pending == 1
    assert [%{filename: "pending.txt", kind: "Interrupted upload"}] = stale.issues
    assert :ok = Insights.retry(c.owner, c.app.id, pending.id)
    File.rm!(c.root)
    File.rename!(held, c.root)
    assert :ok = Storage.reconcile_stale_upload(pending.id)
    {:ok, recovered} = Insights.application(c.owner, c.app.id)
    assert recovered.metrics.reserved_bytes == 0
    assert recovered.metrics.upload_pending == 0
    assert recovered.issues == []
    App.Repo.query!("UPDATE users SET banned=true WHERE id=$1", [Ecto.UUID.dump!(c.owner.id)])
    assert {:error, :forbidden} = Insights.account(c.owner)
    assert {:error, _} = Insights.application(c.owner, c.app.id)
    assert {:error, _} = Insights.retry(c.owner, c.app.id, c.a.id)
  end
end
