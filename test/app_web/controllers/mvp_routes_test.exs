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
    assert length(LazyHTML.query(doc, "#password-sign-in") |> LazyHTML.to_tree()) == 1
    conn |> get("/register") |> html_response(200)
    conn |> get("/sign-in/otp") |> html_response(200)
    conn |> get("/forgot-password") |> html_response(200)
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
    assert has_element?(view, "#tenant-switcher")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(recycle(conn), "/dashboard/admin")
  end

  test "application form, key reveal/revoke and operator boundary", %{conn: conn} do
    user = user("dashboard@example.com")
    conn = signed_in(conn, user)
    assert {:ok, view, _} = live(conn, "/dashboard/applications")

    view
    |> form("#create-application", application: %{name: "Test app", slug: "test-app"})
    |> render_submit()

    assert has_element?(view, "#applications button", "Manage keys")
    view |> element("#applications button", "Manage keys") |> render_click()
    view |> form("#issue-key", key: %{name: "Test key", access: "read"}) |> render_submit()
    assert has_element?(view, "#new-api-key code")
    view |> element("#keys button", "Revoke") |> render_click()
    refute has_element?(view, "#keys button", "Revoke")
    operator = Ash.update!(user, %{}, action: :mark_operator, authorize?: false)
    assert {:ok, admin, _} = live(signed_in(build_conn(), operator), "/dashboard/admin")
    assert has_element?(admin, "#toggle-signup")
    admin |> element("#toggle-signup") |> render_click()
    refute App.Platform.signup_enabled?()
  end
end
