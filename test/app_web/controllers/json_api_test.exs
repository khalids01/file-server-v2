defmodule AppWeb.JsonApiTest do
  use AppWeb.ConnCase, async: true
  import App.AuthHelpers

  test "email/GitHub browser session only sees its own JSON API user", %{conn: conn} do
    owner = user("api@example.com")
    other = user("private@example.com")

    authenticated =
      conn |> init_test_session(%{}) |> AshAuthentication.Phoenix.Plug.store_in_session(owner)

    data = authenticated |> get("/api/json/users") |> json_response(200)
    assert [%{"id" => id, "attributes" => %{"email" => "api@example.com"}}] = data["data"]
    assert id == owner.id
    authenticated |> get("/api/json/users/#{other.id}") |> json_response(404)
  end

  test "anonymous or bearer-only requests cannot access user data", %{conn: conn} do
    conn |> get("/api/json/users") |> json_response(401)

    conn
    |> put_req_header("authorization", "Bearer invalid")
    |> get("/api/json/users")
    |> json_response(401)
  end

  test "OpenAPI documents the user routes", %{conn: conn} do
    schema = conn |> get("/api/json/open_api") |> json_response(200)
    assert Map.has_key?(schema["paths"], "/api/json/users")
  end
end
