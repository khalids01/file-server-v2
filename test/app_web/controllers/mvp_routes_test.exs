defmodule AppWeb.MvpRoutesTest do
  use AppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import App.AuthHelpers

  defp signed_in(conn, user) do
    conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(user)
  end

  test "landing and auth pages expose working forms and disabled GitHub is graceful", %{
    conn: conn
  } do
    doc = conn |> get("/sign-in") |> html_response(200) |> LazyHTML.from_document()
    assert length(LazyHTML.query(doc, "#otp-request") |> LazyHTML.to_tree()) == 1
    conn |> get("/register") |> html_response(200)
    conn |> get("/sign-in/otp") |> html_response(200)
    conn |> get("/forgot-password") |> response(404)
    assert conn |> get("/auth/user/github") |> redirected_to() == "/sign-in"
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, "/dashboard")
  end

  test "email code creates a real browser session and dashboard onboarding", %{conn: conn} do
    conn = conn |> init_test_session(%{}) |> post("/sign-in/otp", %{email: "browser@example.com"})
    assert html_response(conn, 200)
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is (\d{6})/, mail.text_body)
    conn = conn |> recycle() |> post("/sign-in/otp/verify", %{code: code})
    assert redirected_to(conn) == "/dashboard"
    assert {:ok, view, _} = live(recycle(conn), "/dashboard")
    assert has_element?(view, "#dashboard-heading")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(recycle(conn), "/dashboard/admin")
  end

  test "password, reset, magic-link and personal API-key login routes are absent", %{conn: conn} do
    for path <- [
          "/auth/user/password/sign_in",
          "/auth/user/password/register",
          "/auth/user/password/reset_request",
          "/auth/user/magic_link/request",
          "/auth/user/api_key"
        ] do
      conn |> init_test_session(%{}) |> post(path, %{}) |> response(404)
    end

    for path <- ["/password-reset/token", "/magic_link/token", "/confirm_new_user/token"] do
      conn |> get(path) |> response(404)
    end
  end

  test "stored theme preference is rendered before app JS and invalid values fall back safely", %{
    conn: conn
  } do
    doc =
      conn
      |> put_req_cookie("file-server-theme", "dark")
      |> get("/sign-in")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert length(LazyHTML.query(doc, "html.dark[data-theme=dark]") |> LazyHTML.to_tree()) == 1
    assert length(LazyHTML.query(doc, "[data-theme-choice]") |> LazyHTML.to_tree()) == 3
    assert AppWeb.Layouts.theme_preference(%{"file-server-theme" => "malicious"}) == "system"
  end

  test "HTTP application keys authenticate only their application and reject browser origin", %{
    conn: conn
  } do
    owner = user("http-key@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "API app", slug: "api-app"}, actor: owner)

    {key, raw} = App.Applications.issue_key!(owner, app.id, "API key", ["files:read"])

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> raw)
      |> get("/api/v2/application")
      |> json_response(200)

    assert response["data"]["id"] == app.id
    assert response["storage_ready"]
    refute response["sdk_v1_compatible"]

    conn
    |> put_req_header("authorization", "Bearer " <> raw)
    |> put_req_header("origin", "https://example.com")
    |> get("/api/v2/application")
    |> json_response(403)

    conn
    |> put_req_header("authorization", "Bearer " <> raw)
    |> get("/api/json/users")
    |> response(401)

    Ash.update!(key, %{}, action: :revoke, actor: owner)

    conn
    |> put_req_header("authorization", "Bearer " <> raw)
    |> get("/api/v2/application")
    |> json_response(401)
  end

  test "banning an account ends access for an already-mounted dashboard", %{conn: conn} do
    member = user("stale-live@example.com")

    operator =
      user("stale-admin@example.com")
      |> Ash.update!(%{}, action: :mark_operator, authorize?: false)

    assert {:ok, view, _} = live(signed_in(conn, member), "/dashboard/applications")
    view |> element("#new-application") |> render_click()
    Ash.update!(member, %{}, action: :ban, actor: operator)

    view
    |> form("#create-application", application: %{name: "Denied", slug: "denied"})
    |> render_submit()

    assert_redirect(view, "/sign-in")
  end

  test "application form, key reveal/revoke and operator boundary", %{conn: conn} do
    user = user("dashboard@example.com")
    conn = signed_in(conn, user)
    assert {:ok, view, _} = live(conn, "/dashboard/applications")

    view |> element("#new-application") |> render_click()

    view
    |> form("#create-application", application: %{name: "Test app", slug: "test-app"})
    |> render_submit()

    assert has_element?(view, "#applications a", "Manage")
    [app] = App.Applications.applications(user)
    {:ok, view, _} = live(conn, "/dashboard/applications/#{app.id}?tab=keys")
    view |> form("#issue-key", key: %{name: "Test key", access: "read"}) |> render_submit()
    assert has_element?(view, "#new-api-key code")
    view |> element("#keys button", "Revoke") |> render_click()
    view |> element("#confirm-revoke-key") |> render_click()
    refute has_element?(view, "#keys button", "Revoke")
    operator = Ash.update!(user, %{}, action: :mark_operator, authorize?: false)
    assert {:ok, admin, _} = live(signed_in(build_conn(), operator), "/dashboard/admin")
    assert has_element?(admin, "#toggle-signup")
    admin |> element("#toggle-signup") |> render_click()
    admin |> element("#confirm-operator-action") |> render_click()
    refute App.Platform.signup_enabled?()
  end
end
