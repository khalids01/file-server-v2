defmodule AppWeb.DashboardUITest do
  use AppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import App.AuthHelpers

  defp login(conn, user),
    do: conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(user)

  test "profile is full width and header places the logo before its sidebar toggle", %{conn: conn} do
    {:ok, view, _} = live(login(conn, user("layout@example.com")), "/dashboard/profile")
    assert has_element?(view, "#dashboard-heading h1", "Profile")
    assert has_element?(view, "header a[aria-label='File Server home'] + #sidebar-toggle svg")
    refute has_element?(view, "header .ui-badge")

    refute has_element?(
             view,
             "a[href='/dashboard/settings'], #tenant-switcher, section.max-w-2xl"
           )

    view |> form("#profile-form", profile: %{name: "Updated name"}) |> render_submit()
    assert has_element?(view, "#user-menu-button[aria-label='Account menu for Updated name']")
  end

  test "v1-style dialog, card grid and application settings save real data", %{conn: conn} do
    owner = user("cards@example.com")
    {:ok, view, _} = live(login(conn, owner), "/dashboard/applications")
    assert has_element?(view, "#applications-empty")
    view |> element("#new-application") |> render_click()
    assert has_element?(view, "dialog#create-application-dialog")

    view
    |> form("#create-application", application: %{name: "My Website", slug: "my-website"})
    |> render_submit()

    refute has_element?(view, "dialog")
    refute has_element?(view, "#applications-empty")
    [app] = App.Applications.applications(owner)

    assert has_element?(
             view,
             "#applications a[href='/dashboard/applications/#{app.id}']",
             "Manage"
           )

    {:ok, details, _} = live(login(build_conn(), owner), "/dashboard/applications/#{app.id}")

    details
    |> form("#application-settings", application: %{name: "Renamed site"})
    |> render_submit()

    assert Ash.get!(App.Applications.Application, app.id, actor: owner).name == "Renamed site"

    {:ok, keys, _} =
      live(login(build_conn(), owner), "/dashboard/applications/#{app.id}?tab=keys")

    assert has_element?(keys, "[role=combobox]")
    refute has_element?(keys, "select")
    assert has_element?(keys, "input[type=hidden][name='key[access]'][value=read]")
    outsider = user("details-outsider@example.com")

    assert {:error, {:live_redirect, %{to: "/dashboard/applications"}}} =
             live(login(build_conn(), outsider), "/dashboard/applications/#{app.id}")
  end

  test "dashboard edits tags and filters with URL-preserved search/sort/page state", %{conn: conn} do
    owner = user("tags-ui@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Tags app", slug: "tags-ui-app"},
        actor: owner
      )

    for i <- 1..30 do
      Ash.create!(
        App.Storage.StoredFile,
        %{
          filename: "match-#{String.pad_leading(Integer.to_string(i), 3, "0")}.txt",
          size: i,
          content_type: "text/plain",
          object_key: "#{owner.id}/#{app.id}/#{Ecto.UUID.generate()}",
          application_id: app.id,
          tags: if(i == 30, do: ["alpha"], else: [])
        },
        actor: owner,
        authorize?: false
      )
    end

    {:ok, view, _} =
      live(
        login(conn, owner),
        "/dashboard/applications/#{app.id}?tab=files&search=match&sort=name&page=2"
      )

    assert has_element?(view, "#file-page-status", "Page 2 of 2")
    assert render(view) =~ "alpha"

    view
    |> element("button[aria-label='Edit tags for match-030.txt']")
    |> render_click()

    assert has_element?(view, "#edit-file-tags-dialog")

    view
    |> form("#edit-file-tags-form", %{tags: "alpha\nbeta"})
    |> render_submit()

    assert has_element?(view, "#file-page-status", "Page 2 of 2")
    assert render(view) =~ "beta"

    view
    |> form("#file-filters", %{search: "match", sort: "name", tags: "beta"})
    |> render_submit()

    path = assert_patch(view)
    assert path =~ "tab=files"
    assert path =~ "search=match"
    assert path =~ "sort=name"
    assert path =~ "tags%5B%5D=beta" or path =~ "tags[]=beta"
    refute path =~ "page="
    assert render(view) =~ "match-030.txt"
  end
end
