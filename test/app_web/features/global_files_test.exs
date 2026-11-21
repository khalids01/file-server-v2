defmodule AppWeb.GlobalFilesTest do
  use AppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import App.AuthHelpers
  alias App.Storage

  setup do
    root = Path.join(System.tmp_dir!(), "serve-global-#{Ecto.UUID.generate()}")
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)
    File.mkdir_p!(root)
    source = Path.join(root, "fixture.txt")
    File.write!(source, "global fixture")
    owner = user("global-owner-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Alpha app", slug: "alpha-app"},
        actor: owner
      )

    other_app =
      Ash.create!(App.Applications.Application, %{name: "Beta app", slug: "beta-app"},
        actor: owner
      )

    {:ok, first} =
      Storage.upload(owner, app.id, source, "alpha-report.txt", "text/plain", tags: ["finance"])

    {:ok, second} =
      Storage.upload(owner, other_app.id, source, "beta-image.png", "image/png", tags: ["media"])

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    %{
      owner: owner,
      app: app,
      other_app: other_app,
      first: first,
      second: second,
      source: source,
      root: root
    }
  end

  defp login(conn, user),
    do: conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(user)

  # Deterministically set a pending debounce token without waiting on the timer.
  defp put_pending_refresh(view, token) do
    :sys.replace_state(view.pid, fn %{socket: socket} = state ->
      %{state | socket: %{socket | assigns: Map.put(socket.assigns, :refresh_pending, token)}}
    end)
  end

  # Fire the debounced reload for a real PubSub invalidation without sleeping.
  defp flush_refresh(view) do
    case :sys.get_state(view.pid).socket.assigns.refresh_pending do
      nil -> :ok
      token -> send(view.pid, {:refresh_files, token})
    end

    render(view)
  end

  # ---- storage entry point ----

  test "global listing spans applications and can narrow by application", c do
    result = Storage.global_files_page(c.owner)
    assert result.total == 2
    assert Enum.all?(result.files, &(&1.user_id == c.owner.id))

    filtered = Storage.global_files_page(c.owner, application_id: c.app.id)
    assert filtered.total == 1
    assert [only] = filtered.files
    assert only.id == c.first.id
  end

  test "global filters share search/sort/tag logic and reject malformed input", c do
    assert Storage.global_files_page(c.owner, search: "alpha").total == 1
    assert Storage.global_files_page(c.owner, tags: ["finance"]).total == 1
    assert Storage.global_files_page(c.owner, tags: ["finance", "media"]).total == 0
    assert {:error, :invalid_tags} = Storage.global_files_page(c.owner, tags: "finance")
    assert Storage.global_files_page(c.owner, sort: "name").sort == "name"

    assert Storage.global_files_page(c.owner, application_id: "not-a-uuid").total == 0
  end

  test "global listing excludes another owner's files" do
    outsider = user("global-outsider-#{Ecto.UUID.generate()}@example.com")
    assert Storage.global_files_page(outsider).total == 0
    assert {:error, :unauthorized} = Storage.global_files_page(nil)
  end

  # ---- live view ----

  test "global page lists files with application labels and pagination URL", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    assert has_element?(view, "#global-stored-files", "alpha-report.txt")
    assert has_element?(view, "#global-stored-files", "beta-image.png")
    assert has_element?(view, "#global-file-app-#{c.first.id}", "Alpha app")
    assert has_element?(view, "#global-file-app-#{c.second.id}", "Beta app")
    assert has_element?(view, "#global-file-app-filter [data-select-value][value='']")
    assert has_element?(view, "#global-file-search")

    view |> element("#global-files-view-grid") |> render_click()
    assert_patch(view, "/dashboard/files?view=grid")
    assert has_element?(view, "#global-stored-files[data-view='grid']")
  end

  test "global filter form persists search/sort/app/tags in the URL", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    render_hook(view, "filter_files", %{
      "search" => "beta",
      "sort" => "name",
      "app" => c.other_app.id
    })

    assert_patch(
      view,
      "/dashboard/files?sort=name&search=beta&app=#{c.other_app.id}"
    )

    assert has_element?(view, "#global-stored-files", "beta-image.png")
    refute has_element?(view, "#global-stored-files", "alpha-report.txt")

    render_hook(view, "filter_files", %{"search" => "", "sort" => "newest", "tags" => "media"})

    assert_patch(view, "/dashboard/files?tags%5B%5D=media")

    assert has_element?(view, "#global-stored-files", "beta-image.png")
    refute has_element?(view, "#global-stored-files", "alpha-report.txt")

    render_hook(view, "filter_files", %{"search" => "zzz-nothing"})
    assert has_element?(view, "#global-files-search-empty")
  end

  test "global details and download use the stored application", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    view |> element("#global-file-details-#{c.second.id}") |> render_click()
    assert has_element?(view, "#global-file-details-dialog", "beta-image.png")
    assert has_element?(view, "#global-file-details-dialog", "Beta app")
    assert has_element?(view, "#global-file-details-dialog", "sign-in")

    assert has_element?(
             view,
             "#copy-download-#{c.second.id}[data-download-path='/files/#{c.second.id}/download']"
           )
  end

  test "global tag editing uses the file's actual application", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    view |> element("button[aria-label='Edit tags for beta-image.png']") |> render_click()
    assert has_element?(view, "#global-edit-file-tags-dialog")
    view |> form("#global-edit-file-tags-form", %{tags: "media\nbeta"}) |> render_submit()

    assert has_element?(view, "#global-stored-files", "beta")

    assert {:ok, %{tags: ["media", "beta"]}} =
             App.Storage.FileManagement.details(c.owner, c.other_app.id, c.second.id)
  end

  test "global delete requires confirmation and removes the file", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    view |> element("button[aria-label='Delete alpha-report.txt']") |> render_click()
    assert has_element?(view, "#global-delete-file-dialog", "alpha-report.txt")
    view |> element("#global-confirm-delete-file") |> render_click()

    refute has_element?(view, "#global-stored-files", "alpha-report.txt")
    assert {:error, _} = Storage.download(c.owner, c.first.id)
  end

  test "forged file IDs from another application never mutate or disclose", %{conn: conn} = c do
    outsider = user("global-forge-#{Ecto.UUID.generate()}@example.com")

    outside_app =
      Ash.create!(App.Applications.Application, %{name: "Secret", slug: "secret"},
        actor: outsider
      )

    {:ok, outside_file} =
      Storage.upload(outsider, outside_app.id, c.source, "secret.txt", "text/plain")

    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    render_hook(view, "file_details", %{"id" => outside_file.id})
    refute has_element?(view, "#global-file-details-dialog")

    render_hook(view, "edit_file_tags", %{"id" => outside_file.id})
    refute has_element?(view, "#global-edit-file-tags-dialog")

    render_hook(view, "delete_file", %{"id" => outside_file.id})
    refute has_element?(view, "#global-delete-file-dialog")

    assert {:ok, _} = Storage.download(outsider, outside_file.id)

    render_hook(view, "confirm_delete_file", %{"id" => outside_file.id})
    assert {:ok, _} = Storage.download(outsider, outside_file.id)
  end

  test "outsider sees only their own files on the global page", %{conn: conn} = c do
    outsider = user("global-other-#{Ecto.UUID.generate()}@example.com")

    outside_app =
      Ash.create!(App.Applications.Application, %{name: "Theirs", slug: "theirs"},
        actor: outsider
      )

    {:ok, _} = Storage.upload(outsider, outside_app.id, c.source, "theirs.txt", "text/plain")

    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")
    refute has_element?(view, "#global-stored-files", "theirs.txt")

    {:ok, other_view, _} = live(login(conn, outsider), "/dashboard/files")
    assert has_element?(other_view, "#global-stored-files", "theirs.txt")
    refute has_element?(other_view, "#global-stored-files", "alpha-report.txt")

    {:ok, other_view, _} =
      live(login(conn, outsider), "/dashboard/files?app=#{c.other_app.id}")

    refute has_element?(other_view, "#global-stored-files", "beta-image.png")
  end

  test "navigation applies params while a refresh is pending and invalidates its token",
       %{
         conn: conn
       } = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    stale = make_ref()
    put_pending_refresh(view, stale)

    render_patch(view, "/dashboard/files?search=beta&sort=name")

    assert has_element?(view, "#global-file-search[value='beta']")
    assert has_element?(view, "#global-file-sort [data-select-value][value='name']")
    assert has_element?(view, "#global-stored-files", "beta-image.png")
    refute has_element?(view, "#global-stored-files", "alpha-report.txt")
    assert :sys.get_state(view.pid).socket.assigns.refresh_pending == nil

    # The stale debounce message from before navigation must not clobber the filters.
    send(view.pid, {:refresh_files, stale})
    _ = render(view)
    assert has_element?(view, "#global-file-search[value='beta']")
    refute has_element?(view, "#global-stored-files", "alpha-report.txt")
  end

  test "external notifications reload or close an open details dialog", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    view |> element("#global-file-details-#{c.second.id}") |> render_click()
    assert has_element?(view, "#global-file-details-dialog", "beta-image.png")

    {:ok, _} = Storage.update_tags(c.owner, c.other_app.id, c.second.id, ["external-tag"])
    flush_refresh(view)
    assert has_element?(view, "#global-file-details-dialog", "external-tag")

    assert :ok = Storage.delete(c.owner, c.second.id)
    flush_refresh(view)
    refute has_element?(view, "#global-file-details-dialog")
    refute has_element?(view, "#global-stored-files", "beta-image.png")
  end

  test "malformed and non-UUID file IDs are rejected without raising", %{conn: conn} = c do
    {:ok, view, _} = live(login(conn, c.owner), "/dashboard/files")

    for bad_id <- ["not-a-uuid", "123", "", "00000000-0000-0000-0000-00000000zzzz"] do
      render_hook(view, "file_details", %{"id" => bad_id})
      refute has_element?(view, "#global-file-details-dialog")

      render_hook(view, "delete_file", %{"id" => bad_id})
      refute has_element?(view, "#global-delete-file-dialog")

      render_hook(view, "edit_file_tags", %{"id" => bad_id})
      refute has_element?(view, "#global-edit-file-tags-dialog")
    end

    # The view is still healthy and a valid ID continues to work.
    view |> element("#global-file-details-#{c.first.id}") |> render_click()
    assert has_element?(view, "#global-file-details-dialog", "alpha-report.txt")
  end

  test "banned actor is redirected away from the global page", %{conn: conn} = c do
    Ash.update!(c.owner, %{}, action: :ban, authorize?: false)

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(login(conn, c.owner), "/dashboard/files")
  end
end
