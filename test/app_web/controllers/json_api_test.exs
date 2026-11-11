defmodule AppWeb.JsonApiTest do
  use AppWeb.ConnCase, async: true
  import App.AuthHelpers

  test "API key authenticates JSON API and only returns its own user", %{conn: conn} do
    owner = user("api@example.com")
    other = user("private@example.com")
    key = api_key(owner)
    response = conn |> authenticate(key) |> get("/api/json/users") |> json_response(200)
    assert [%{"id" => id, "attributes" => %{"email" => "api@example.com"}}] = response["data"]
    assert id == owner.id
    conn |> authenticate(key) |> get("/api/json/users/#{other.id}") |> json_response(404)
  end

  test "missing, invalid, expired, and revoked keys cannot access user data", %{conn: conn} do
    conn |> get("/api/json/users") |> json_response(401)

    conn
    |> put_req_header("authorization", "Bearer invalid")
    |> get("/api/json/users")
    |> response(401)

    owner = user("expired@example.com")
    expired = api_key(owner, -60)
    conn |> authenticate(expired) |> get("/api/json/users") |> response(401)
    revoked = api_key(owner)
    Ash.destroy!(revoked, actor: owner)
    conn |> authenticate(revoked) |> get("/api/json/users") |> response(401)
  end

  test "OpenAPI documents the user routes", %{conn: conn} do
    schema = conn |> get("/api/json/open_api") |> json_response(200)
    assert Map.has_key?(schema["paths"], "/api/json/users")
  end

  defp authenticate(conn, key) do
    put_req_header(conn, "authorization", "Bearer #{key.__metadata__.plaintext_api_key}")
  end
end
