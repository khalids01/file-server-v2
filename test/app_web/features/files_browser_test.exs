defmodule AppWeb.FilesBrowserUITest do
  use AppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import App.AuthHelpers

  setup do
    root = Path.join(System.tmp_dir!(), "serve-browser-test-" <> Ecto.UUID.generate())
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    owner = user("browser-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Browser app", slug: "browser-app"},
        actor: owner
      )

    %{owner: owner, app: app}
  end

  defp login(conn, user),
    do: conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(user)

  defp create_file(owner, app, filename, size) do
    Ash.create!(
      App.Storage.StoredFile,
      %{
        filename: filename,
        size: size,
        content_type: "text/plain",
        object_key: "#{owner.id}/#{app.id}/#{Ecto.UUID.generate()}",
        application_id: app.id
      },
      actor: owner,
      authorize?: false
    )
  end

  test "files tab shows search, sort and pagination for more than 100 files", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    for i <- 1..105 do
      create_file(owner, app, "page-#{String.pad_leading(Integer.to_string(i), 3, "0")}.txt", i)
    end

    {:ok, view, _} =
      live(login(conn, owner), "/dashboard/applications/#{app.id}?tab=files")

    assert has_element?(view, "#file-search")
    assert has_element?(view, "#file-sort [data-select-value]")
    assert has_element?(view, "#file-pagination")
    assert has_element?(view, "#file-page-status", "Page 1 of 5")
    assert has_element?(view, "#file-page-next")
    refute has_element?(view, "#file-page-prev")

    view
    |> element("#file-page-next")
    |> render_click()

    assert has_element?(view, "#file-page-status", "Page 2 of 5")
    assert has_element?(view, "#file-page-prev")
    assert has_element?(view, "#file-page-next")

    view
    |> element("#file-page-prev")
    |> render_click()

    assert has_element?(view, "#file-page-status", "Page 1 of 5")
  end

  test "filter form resets page and persists search/sort in the URL", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    for i <- 1..30 do
      create_file(owner, app, "match-#{String.pad_leading(Integer.to_string(i), 3, "0")}.txt", i)
    end

    create_file(owner, app, "other.txt", 5)

    {:ok, view, _} =
      live(login(conn, owner), "/dashboard/applications/#{app.id}?tab=files&page=2")

    assert has_element?(view, "#file-page-status", "Page 2 of 2")

    view
    |> form("#file-filters", %{search: "other.txt"})
    |> render_submit()

    assert_patch(view, "/dashboard/applications/#{app.id}?search=other.txt&tab=files")
    refute has_element?(view, "#file-pagination")
    assert has_element?(view, "#file-search[value='other.txt']")

    render_hook(view, "filter_files", %{"search" => "", "sort" => "name"})
    assert_patch(view, "/dashboard/applications/#{app.id}?sort=name&tab=files")
  end

  test "search with no results shows the empty-search state", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    create_file(owner, app, "needle.txt", 1)

    {:ok, view, _} =
      live(login(conn, owner), "/dashboard/applications/#{app.id}?tab=files&search=zzz-nothing")

    assert has_element?(view, "#files-search-empty")
    refute has_element?(view, "#files-empty")
  end

  test "sort option persists through the files tab URL", %{conn: conn, owner: owner, app: app} do
    create_file(owner, app, "b.txt", 20)
    create_file(owner, app, "a.txt", 10)

    {:ok, view, _} =
      live(login(conn, owner), "/dashboard/applications/#{app.id}?tab=files&sort=name")

    assert has_element?(view, "#file-sort [data-select-value][value='name']")
  end

  test "malformed page and sort params fall back to defaults", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    for i <- 1..30 do
      create_file(owner, app, "mal-#{String.pad_leading(Integer.to_string(i), 3, "0")}.txt", i)
    end

    {:ok, view, _} =
      live(
        login(conn, owner),
        "/dashboard/applications/#{app.id}?tab=files&page=bogus&sort=whatever&search=mal"
      )

    assert has_element?(view, "#file-page-status", "Page 1 of 2")
  end

  test "outsider sees no files for another user's application", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    outsider = user("browser-outsider-#{Ecto.UUID.generate()}@example.com")
    create_file(owner, app, "private.txt", 1)

    assert {:error, {:live_redirect, %{to: "/dashboard/applications"}}} =
             live(login(conn, outsider), "/dashboard/applications/#{app.id}?tab=files")
  end

  test "deleting the last page clamps its URL and later uploads retain filters", %{
    conn: conn,
    owner: owner,
    app: app
  } do
    for i <- 1..25 do
      create_file(owner, app, "group-#{String.pad_leading(Integer.to_string(i), 3, "0")}.txt", i)
    end

    source = Path.join(System.tmp_dir!(), "serve-browser-source-" <> Ecto.UUID.generate())
    File.write!(source, "real stored bytes")
    on_exit(fn -> File.rm(source) end)
    {:ok, target} = App.Storage.upload(owner, app.id, source, "group-z-delete.txt", "text/plain")

    {:ok, view, _} =
      live(
        login(conn, owner),
        "/dashboard/applications/#{app.id}?tab=files&search=group-&sort=name&page=2"
      )

    assert has_element?(view, "#stored-files", target.filename)

    view
    |> element("#stored-files button[aria-label='Delete group-z-delete.txt']")
    |> render_click()

    view |> element("#confirm-delete-file") |> render_click()
    assert_patch(view, "/dashboard/applications/#{app.id}?sort=name&search=group-&tab=files")
    refute has_element?(view, "#file-pagination")
    assert has_element?(view, "#file-search[value='group-']")
    assert has_element?(view, "#file-sort [data-select-value][value='name']")
    assert {:error, _} = App.Storage.download(owner, target.id)

    upload =
      file_input(view, "#upload-files", :documents, [
        %{name: "group-zzz.txt", content: "new private bytes", type: "text/plain"}
      ])

    render_upload(upload, "group-zzz.txt")
    view |> form("#upload-files") |> render_submit()
    assert has_element?(view, "#file-search[value='group-']")
    assert has_element?(view, "#file-sort [data-select-value][value='name']")
    assert has_element?(view, "#file-page-status", "Page 1 of 2")
    view |> element("#file-page-next") |> render_click()
    assert has_element?(view, "#stored-files", "group-zzz.txt")
  end
end
