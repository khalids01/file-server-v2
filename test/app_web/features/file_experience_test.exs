defmodule AppWeb.FileExperienceTest do
  use AppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import App.AuthHelpers
  alias App.Storage

  setup %{conn: conn} do
    root = Path.join(System.tmp_dir!(), "serve-experience-#{Ecto.UUID.generate()}")
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)
    File.mkdir_p!(root)
    source = Path.join(root, "fixture.txt")
    File.write!(source, "private content")
    owner = user("experience-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Experience", slug: "experience"},
        actor: owner
      )

    {:ok, first} = Storage.upload(owner, app.id, source, "one.txt", "text/plain", tags: ["first"])
    {:ok, second} = Storage.upload(owner, app.id, source, "two.txt", "text/plain")

    login =
      conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(owner)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    %{login: login, owner: owner, app: app, first: first, second: second, root: root}
  end

  test "grid URL persists through filters and resets selection", c do
    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files")
    view |> element("#select-file-#{c.first.id}") |> render_click()
    assert has_element?(view, "#selected-file-count", "1 selected")
    view |> element("#files-view-grid") |> render_click()
    assert_patch(view, "/dashboard/applications/#{c.app.id}?view=grid&tab=files")
    assert has_element?(view, "#stored-files[data-view='grid']")
    refute has_element?(view, "#file-bulk-toolbar")
    render_hook(view, "filter_files", %{"search" => "one", "sort" => "name"})

    assert_patch(
      view,
      "/dashboard/applications/#{c.app.id}?view=grid&sort=name&search=one&tab=files"
    )

    assert has_element?(view, "#file-details-#{c.first.id}")
    refute has_element?(view, "#file-details-#{c.second.id}")
  end

  test "details and copy link are private; forged same-owner other-app access is denied", c do
    other_app =
      Ash.create!(App.Applications.Application, %{name: "Other", slug: "other"}, actor: c.owner)

    {:ok, other} =
      Storage.upload(
        c.owner,
        other_app.id,
        Path.join(c.root, "fixture.txt"),
        "other.txt",
        "text/plain"
      )

    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files")
    view |> element("#file-details-#{c.first.id}") |> render_click()
    assert has_element?(view, "#file-details-dialog", "one.txt")
    assert has_element?(view, "#file-details-dialog", "text/plain")
    assert has_element?(view, "#file-details-dialog", "sign-in")

    assert has_element?(
             view,
             "#copy-download-#{c.first.id}[data-download-path='/files/#{c.first.id}/download']"
           )

    refute has_element?(view, "[data-object-key]")
    view |> element("#file-details-dialog button[aria-label='Close dialog']") |> render_click()
    render_hook(view, "file_details", %{"id" => other.id})
    refute has_element?(view, "#file-details-dialog")
    render_hook(view, "toggle_file", %{"id" => other.id})
    refute has_element?(view, "#file-bulk-toolbar")
  end

  test "page selection bulk tag changes and clear work through shared controls", c do
    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files")
    view |> element("#select-page") |> render_click()
    assert has_element?(view, "#selected-file-count", "2 selected")
    view |> element("#bulk-tags-button") |> render_click()
    assert has_element?(view, "#bulk-tags-mode [role='listbox']")
    view |> form("#bulk-tags-form", %{tags: "Project\nproject"}) |> render_submit()
    assert has_element?(view, "#bulk-feedback", "2 succeeded · 0 failed")
    assert Enum.all?(Storage.files(c.owner, c.app.id), &Enum.member?(&1.tags, "Project"))
    view |> element("#select-page") |> render_click()
    view |> element("#clear-selection") |> render_click()
    refute has_element?(view, "#file-bulk-toolbar")
  end

  test "bulk deletion confirms and keeps failed files selected", c do
    {:ok, path} = Storage.Local.path(c.second.object_key)
    File.rm!(path)
    File.ln_s!("/nonexistent-fixture-target", path)
    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files")
    view |> element("#select-page") |> render_click()
    view |> element("#bulk-delete-button") |> render_click()
    assert has_element?(view, "#bulk-delete-dialog", "Permanently delete 2 files")
    view |> element("#confirm-bulk-delete") |> render_click()
    assert has_element?(view, "#bulk-feedback", "1 succeeded · 1 failed")
    assert has_element?(view, "#select-file-#{c.second.id}[aria-checked='true']")
    refute has_element?(view, "#file-details-#{c.first.id}")
    assert Storage.Quota.status_for_user(c.owner.id).used_bytes == c.second.size
    assert has_element?(view, "#bulk-errors", "two.txt")
    view |> element("#clear-selection") |> render_click()
    refute has_element?(view, "#bulk-errors")
  end

  test "upload cancellation progress and failure reselection feedback", c do
    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files")

    upload =
      file_input(view, "#upload-files", :documents, [
        %{name: "cancel.txt", content: "cancel", type: "text/plain"}
      ])

    render_upload(upload, "cancel.txt", 50)
    assert has_element?(view, "[role='progressbar'][aria-valuenow='50']")
    view |> element("button[aria-label='Remove cancel.txt']") |> render_click()
    refute has_element?(view, "[aria-label='cancel.txt']")
    :ok = Storage.Quota.ensure_account!(c.owner.id)

    App.Repo.query!("UPDATE account_storage SET quota_bytes=used_bytes WHERE user_id=$1", [
      Ecto.UUID.dump!(c.owner.id)
    ])

    upload =
      file_input(view, "#upload-files", :documents, [
        %{name: "failed.txt", content: "retry me", type: "text/plain"}
      ])

    render_upload(upload, "failed.txt")
    view |> form("#upload-files") |> render_submit()
    assert has_element?(view, "#upload-results", "failed.txt")
    assert has_element?(view, "#upload-results", "quota reached")
    view |> element("#upload-results button") |> render_click()
    assert has_element?(view, "#flash-info", "Choose or drop the failed file again")
  end

  test "grid pagination clears selection and never selects more than the page", c do
    for i <- 1..25 do
      {:ok, _} =
        Storage.upload(
          c.owner,
          c.app.id,
          Path.join(c.root, "fixture.txt"),
          "page-#{i}.txt",
          "text/plain"
        )
    end

    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files&view=grid")
    view |> element("#select-page") |> render_click()
    assert has_element?(view, "#selected-file-count", "25 selected")
    view |> element("#file-page-next") |> render_click()
    assert_patch(view, "/dashboard/applications/#{c.app.id}?view=grid&tab=files&page=2")
    assert has_element?(view, "#stored-files[data-view='grid']")
    refute has_element?(view, "#file-bulk-toolbar")
    assert has_element?(view, "#file-page-status", "Page 2 of 2")
  end

  test "switching applications clears selected files and queued upload bytes", c do
    other =
      Ash.create!(App.Applications.Application, %{name: "Other", slug: "other"}, actor: c.owner)

    {:ok, view, _} = live(c.login, "/dashboard/applications/#{c.app.id}?tab=files")
    view |> element("#select-page") |> render_click()

    upload =
      file_input(view, "#upload-files", :documents, [
        %{name: "queued.txt", content: "queued", type: "text/plain"}
      ])

    render_upload(upload, "queued.txt", 50)
    render_patch(view, "/dashboard/applications/#{other.id}?tab=files")
    refute has_element?(view, "#file-bulk-toolbar")
    refute has_element?(view, "[aria-label='queued.txt']")
    assert has_element?(view, "#files-empty")
    render_hook(view, "file_details", %{"id" => c.first.id})
    refute has_element?(view, "#file-details-dialog")
  end
end
