defmodule AppWeb.RegistrationTest do
  use AppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "sign-in links to name and email signup, with a sign-in link back", %{conn: conn} do
    doc = conn |> get("/sign-in") |> html_response(200) |> LazyHTML.from_document()
    assert [_] = LazyHTML.query(doc, "#sign-up-link[href='/register']") |> LazyHTML.to_tree()
    doc = conn |> get("/register") |> html_response(200) |> LazyHTML.from_document()
    assert [_] = LazyHTML.query(doc, "#sign-up-form[action='/register']") |> LazyHTML.to_tree()
    assert [_] = LazyHTML.query(doc, "#sign-up-name[required]") |> LazyHTML.to_tree()
    assert [_] = LazyHTML.query(doc, "#sign-up-email[type='email']") |> LazyHTML.to_tree()
    assert [_] = LazyHTML.query(doc, "#sign-in-link[href='/sign-in']") |> LazyHTML.to_tree()
  end

  test "configured GitHub signup uses the same trusted OAuth endpoint" do
    doc =
      render_component(&AppWeb.SessionHTML.register/1, github?: true, flash: %{})
      |> LazyHTML.from_document()

    assert [_] =
             LazyHTML.query(doc, "#github-sign-up[href='/auth/user/github']")
             |> LazyHTML.to_tree()
  end

  test "signup requires a name before sending mail", %{conn: conn} do
    conn |> post("/register", %{name: "  ", email: "invalid@example.com"}) |> html_response(422)
    refute_receive {:email, _}
  end

  test "email verification creates a named account and renders the reusable menu", %{conn: conn} do
    conn = post(conn, "/register", %{name: "  Khalid Khan  ", email: "signup@example.com"})
    html_response(conn, 200)
    assert Ash.count!(App.Accounts.User, authorize?: false) == 0
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is (\d{6})/, mail.text_body)
    conn = conn |> recycle() |> post("/sign-in/otp/verify", %{code: code})
    assert redirected_to(conn) == "/dashboard"
    [user] = Ash.read!(App.Accounts.User, authorize?: false)
    assert user.name == "Khalid Khan"
    assert get_session(conn, :pending_otp_name) == nil
    {:ok, view, _} = live(recycle(conn), "/dashboard")
    assert has_element?(view, "#user-menu-button span", "K")
    assert has_element?(view, "#user-menu a[href='/dashboard/profile']")
    assert has_element?(view, "#user-menu a[href='/sign-out']")
  end

  test "signup through an existing email does not overwrite the profile", %{conn: conn} do
    existing =
      Ash.create!(App.Accounts.User, %{email: "same@example.com", name: "Original"},
        action: :register_with_otp,
        authorize?: false
      )

    conn = post(conn, "/register", %{name: "Replacement", email: "same@example.com"})
    html_response(conn, 200)
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is (\d{6})/, mail.text_body)
    conn |> recycle() |> post("/sign-in/otp/verify", %{code: code})
    same = Ash.get!(App.Accounts.User, existing.id, authorize?: false)
    assert same.name == "Original"
  end
end
