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
end
