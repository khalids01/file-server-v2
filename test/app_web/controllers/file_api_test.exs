defmodule AppWeb.FileApiTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers
  alias App.Applications
  alias App.Storage

  setup do
    root = Path.join(System.tmp_dir!(), "serve-api-test-" <> Ecto.UUID.generate())
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    owner = user("api-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(Applications.Application, %{name: "API project", slug: "api-project"},
        actor: owner
      )

    {key, token} =
      Applications.issue_key!(owner, app.id, "Manage key", [
        "files:read",
        "files:write",
        "files:delete"
      ])

    %{owner: owner, app: app, key: key, token: token}
  end

  defp authorized(token), do: build_conn() |> put_req_header("authorization", "Bearer " <> token)

  defp multipart(parts) do
    Enum.map_join(parts, "", fn {field, filename, bytes} ->
      "--serve-boundary\r\nContent-Disposition: form-data; name=\"#{field}\"" <>
        if(filename, do: "; filename=\"#{filename}\"\r\nContent-Type: text/plain", else: "") <>
        "\r\n\r\n#{bytes}\r\n"
    end) <> "--serve-boundary--\r\n"
  end

  defp upload(token, parts \\ [{"file", "hello-api.txt", "hello private API"}]) do
    authorized(token)
    |> put_req_header("content-type", "multipart/form-data; boundary=serve-boundary")
    |> post("/api/v2/files", multipart(parts))
  end

  defp upload_with_tags(token, filename, content, tags) do
    upload(token, [
      {"file", filename, content},
      {"tags", nil, Jason.encode!(tags)}
    ])
  end

  test "authenticated multipart upload, paginated list, metadata, content and delete", %{
    token: token,
    owner: owner,
    app: app
  } do
    created = upload(token) |> json_response(201)
    file = created["data"]
    id = file["id"]
    assert file["applicationId"] == app.id
    assert file["sizeBytes"] == byte_size("hello private API")
    assert file["urls"]["content"] == "/api/v2/files/#{id}/content"
    assert file["tags"] == []
    refute Map.has_key?(file, "object_key")
    refute Map.has_key?(file, "credentials")
    listing = authorized(token) |> get("/api/v2/files?limit=1&search=hello") |> json_response(200)
    assert [^file] = listing["data"]

    assert listing["pagination"] == %{
             "page" => 1,
             "limit" => 1,
             "total" => 1,
             "pages" => 1,
             "hasNext" => false,
             "hasPrev" => false
           }

    assert authorized(token) |> get("/api/v2/files/#{id}") |> json_response(200) == created
    download = authorized(token) |> get(file["urls"]["content"])
    assert response(download, 200) == "hello private API"
    assert get_resp_header(download, "cache-control") == ["private, no-store"]
    assert get_resp_header(download, "content-type") == ["application/octet-stream"]
    assert get_resp_header(download, "content-security-policy") == ["sandbox; default-src 'none'"]
    deleted = authorized(token) |> delete("/api/v2/files/#{id}") |> json_response(200)
    assert deleted == %{"data" => %{"id" => id, "deleted" => true}}
    authorized(token) |> get(file["urls"]["content"]) |> json_response(404)
    assert Storage.files(owner, app.id) == []
  end

  test "same-owner applications cannot list, read, download or delete each other's files", %{
    token: token,
    owner: owner
  } do
    id = (upload(token) |> json_response(201))["data"]["id"]

    other_app =
      Ash.create!(Applications.Application, %{name: "Other project", slug: "other-project"},
        actor: owner
      )

    {_, other_token} =
      Applications.issue_key!(owner, other_app.id, "Other key", ["files:read", "files:delete"])

    assert (authorized(other_token) |> get("/api/v2/files") |> json_response(200))["data"] == []

    for suffix <- ["", "/content"] do
      assert (authorized(other_token)
              |> get("/api/v2/files/#{id}#{suffix}")
              |> json_response(404))["error"]["code"] == "FILE_NOT_FOUND"
    end

    authorized(other_token) |> delete("/api/v2/files/#{id}") |> json_response(404)

    assert (authorized(token) |> get("/api/v2/files/#{id}") |> json_response(200))["data"]["id"] ==
             id

    assert upload(token, [{"file", "bad.txt", "data"}, {"applicationId", nil, other_app.id}])
           |> json_response(400)
  end

  test "scopes are enforced independently and credentials stay server-side", %{
    token: token,
    owner: owner,
    app: app
  } do
    {_, read} = Applications.issue_key!(owner, app.id, "Read key", ["files:read"])
    {_, write} = Applications.issue_key!(owner, app.id, "Write key", ["files:write"])
    assert (upload(read) |> json_response(403))["error"]["code"] == "INSUFFICIENT_SCOPE"
    id = (upload(write) |> json_response(201))["data"]["id"]
    authorized(write) |> get("/api/v2/files") |> json_response(403)
    authorized(read) |> delete("/api/v2/files/#{id}") |> json_response(403)

    authorized(token)
    |> put_req_header("origin", "https://example.com")
    |> get("/api/v2/files")
    |> json_response(403)

    authorized(token)
    |> put_req_header("sec-fetch-site", "same-origin")
    |> get("/api/v2/files")
    |> json_response(403)

    build_conn() |> get("/api/v2/files?api_key=#{token}") |> json_response(401)

    assert build_conn()
           |> put_req_header("x-api-key", read)
           |> get("/api/v2/files")
           |> json_response(200)

    assert authorized(token) |> get("/files/#{id}/download") |> redirected_to() == "/sign-in"
  end

  test "revoked, expired and banned credentials stop working immediately", %{
    owner: owner,
    app: app,
    key: key,
    token: token
  } do
    Ash.update!(key, %{}, action: :revoke, actor: owner)
    authorized(token) |> get("/api/v2/files") |> json_response(401)

    {expired, expired_token} =
      Applications.issue_key!(owner, app.id, "Expired key", ["files:read"])

    App.Repo.query!(
      "UPDATE application_keys SET expires_at=now()-interval '1 minute' WHERE id=$1",
      [Ecto.UUID.dump!(expired.id)]
    )

    authorized(expired_token) |> get("/api/v2/files") |> json_response(401)
    {_, valid} = Applications.issue_key!(owner, app.id, "Active key", ["files:read"])
    authorized(valid) |> get("/api/v2/files") |> json_response(200)
    Ash.update!(owner, %{}, action: :ban, authorize?: false)
    authorized(valid) |> get("/api/v2/files") |> json_response(401)
  end

  test "authentication runs before malformed or oversized bodies are parsed", %{token: token} do
    build_conn()
    |> put_req_header("content-type", "multipart/form-data; boundary=bad")
    |> put_req_header("content-length", "999999999")
    |> post("/api/v2/files", "malformed")
    |> json_response(401)

    authorized(token)
    |> put_req_header("content-type", "multipart/form-data; boundary=bad")
    |> put_req_header("content-length", "999999999")
    |> post("/api/v2/files", "malformed")
    |> json_response(413)

    authorized(token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/v2/files", "{}")
    |> json_response(415)
  end

  test "pagination has stable boundaries and accurate totals", %{token: token} do
    for name <- ["alpha.txt", "bravo.txt", "charlie.txt"],
        do: upload(token, [{"file", name, name}]) |> json_response(201)

    first = authorized(token) |> get("/api/v2/files?limit=2") |> json_response(200)
    second = authorized(token) |> get("/api/v2/files?limit=2&page=2") |> json_response(200)
    assert length(first["data"]) == 2
    assert length(second["data"]) == 1
    assert first["pagination"]["total"] == 3
    assert first["pagination"]["hasNext"]
    assert second["pagination"]["hasPrev"]
    refute second["pagination"]["hasNext"]

    assert MapSet.disjoint?(
             MapSet.new(first["data"], & &1["id"]),
             MapSet.new(second["data"], & &1["id"])
           )
  end

  test "key request limits return JSON and a retry header", %{token: token, key: key} do
    for _ <- 1..120, do: assert(App.Accounts.RateLimit.allow_api_key?(key.id))
    conn = authorized(token) |> get("/api/v2/files")
    assert json_response(conn, 429)["error"]["code"] == "RATE_LIMITED"
    assert get_resp_header(conn, "retry-after") == ["60"]
  end

  test "invalid input, duplicate files and size limits return JSON without storing metadata", %{
    token: token,
    owner: owner,
    app: app
  } do
    previous = Application.get_env(:app, :max_file_size)
    Application.put_env(:app, :max_file_size, 4)
    on_exit(fn -> Application.put_env(:app, :max_file_size, previous) end)
    assert upload(token, [{"file", "large.txt", "12345"}]) |> json_response(413)
    assert upload(token, [{"file", "empty.txt", ""}]) |> json_response(400)

    assert upload(token, [{"file", "one.txt", "1"}, {"file", "two.txt", "2"}])
           |> json_response(400)

    for query <- [
          "page=0",
          "limit=101",
          "page[]=1",
          "applicationId=#{app.id}",
          "tags=bad",
          "tags[]="
        ] do
      authorized(token) |> get("/api/v2/files?#{query}") |> json_response(400)
    end

    authorized(token) |> get("/api/v2/files/invalid-id") |> json_response(404)
    assert Storage.files(owner, app.id) == []
  end

  test "upload accepts optional tags, serializes tags and supports AND tag filters", %{
    token: token
  } do
    one = upload_with_tags(token, "a.txt", "a", ["alpha", "beta"]) |> json_response(201)
    two = upload_with_tags(token, "b.txt", "b", ["alpha"]) |> json_response(201)
    _three = upload_with_tags(token, "c.txt", "c", ["beta"]) |> json_response(201)

    assert one["data"]["tags"] == ["alpha", "beta"]
    assert two["data"]["tags"] == ["alpha"]

    filtered =
      authorized(token)
      |> get("/api/v2/files?tags[]=alpha&tags[]=beta")
      |> json_response(200)

    assert Enum.map(filtered["data"], & &1["id"]) == [one["data"]["id"]]

    assert (authorized(token) |> get("/api/v2/files?tags[]=gamma") |> json_response(200))["data"] ==
             []
  end

  test "invalid upload tags are rejected without storing files", %{
    token: token,
    owner: owner,
    app: app
  } do
    assert upload_with_tags(token, "bad.txt", "x", [""]) |> json_response(400)
    assert upload_with_tags(token, "bad2.txt", "x", ["bad\nline"]) |> json_response(400)

    assert upload(token, [
             {"file", "bad3.txt", "x"},
             {"file", "tags", Jason.encode!(["a"])}
           ])
           |> json_response(400)

    assert upload(token, [{"file", "bad4.txt", "x"}, {"tags", nil, "not-json"}])
           |> json_response(400)

    assert upload(token, [
             {"file", "bad5.txt", "x"},
             {"tags", nil, Jason.encode!(["a"])},
             {"tags", nil, Jason.encode!(["b"])}
           ])
           |> json_response(400)

    assert Storage.files(owner, app.id) == []
  end

  test "PATCH /api/v2/files/:id updates tags with files:write and isolation", %{
    token: token,
    owner: owner,
    app: app
  } do
    {_, read} = Applications.issue_key!(owner, app.id, "Read key", ["files:read"])
    {_, write} = Applications.issue_key!(owner, app.id, "Write key", ["files:write"])

    id =
      (upload_with_tags(token, "tagged.txt", "body", ["old"]) |> json_response(201))["data"]["id"]

    read_resp =
      read
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{id}", Jason.encode!(%{tags: ["x"]}))

    assert json_response(read_resp, 403)["error"]["code"] == "INSUFFICIENT_SCOPE"

    updated =
      write
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{id}", Jason.encode!(%{tags: [" one ", "one", "two"]}))

    assert json_response(updated, 200)["data"]["tags"] == ["one", "two"]

    cleared =
      token
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{id}", Jason.encode!(%{tags: []}))

    assert json_response(cleared, 200)["data"]["tags"] == []

    bad =
      token
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{id}", Jason.encode!(%{tags: ["bad\nline"]}))

    assert json_response(bad, 400)["error"]["code"] == "INVALID_TAGS"

    missing =
      token
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{id}", Jason.encode!(%{other: 1}))

    assert json_response(missing, 400)["error"]["code"] == "INVALID_TAGS"

    other_app =
      Ash.create!(Applications.Application, %{name: "Other project", slug: "other-project-2"},
        actor: owner
      )

    {_, other_write} =
      Applications.issue_key!(owner, other_app.id, "Other write", ["files:write"])

    cross =
      other_write
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{id}", Jason.encode!(%{tags: ["x"]}))

    assert json_response(cross, 404)["error"]["code"] == "FILE_NOT_FOUND"

    assert (authorized(token) |> get("/api/v2/files/#{id}") |> json_response(200))["data"]["tags"] ==
             []
  end

  test "mixed-case tag filtering matches normalized labels without widening results", %{
    token: token,
    owner: owner,
    app: app
  } do
    created =
      upload_with_tags(token, "finance.txt", "finance bytes", ["Finance", "finance", "Quarter 1"])
      |> json_response(201)

    assert created["data"]["tags"] == ["Finance", "Quarter 1"]
    upload_with_tags(token, "other.txt", "other bytes", ["Quarter 1"]) |> json_response(201)

    filtered =
      authorized(token)
      |> get("/api/v2/files?tags[]=FINANCE&tags[]=quarter+1")
      |> json_response(200)

    assert Enum.map(filtered["data"], & &1["id"]) == [created["data"]["id"]]
    page = Storage.files_page(owner, app.id, tags: ["finance", "QUARTER 1"])
    assert page.total == 1
    assert Enum.map(page.files, & &1.id) == [created["data"]["id"]]
    query = URI.encode_query([{"tags[]", "Finance' OR 1=1 --"}, {"page", "9"}])
    empty = authorized(token) |> get("/api/v2/files?" <> query) |> json_response(200)
    assert empty["data"] == []
    assert empty["pagination"]["pages"] == 0
    assert empty["pagination"]["page"] == 9
  end

  test "PATCH tag updates authenticate before bounded JSON parsing", %{token: token} do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", "999999999")
    |> patch("/api/v2/files/#{Ecto.UUID.generate()}", "malformed")
    |> json_response(401)

    conn =
      token
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", "999999999")
      |> patch("/api/v2/files/#{Ecto.UUID.generate()}", "malformed")

    assert json_response(conn, 413)["error"]["code"] == "FILE_TOO_LARGE"

    bad_type =
      token
      |> authorized()
      |> put_req_header("content-type", "text/plain")
      |> patch("/api/v2/files/#{Ecto.UUID.generate()}", "tags")

    assert json_response(bad_type, 415)["error"]["code"] == "INVALID_BODY"

    authorized(token)
    |> put_req_header("content-type", "application/json-invalid")
    |> patch("/api/v2/files/#{Ecto.UUID.generate()}", Jason.encode!(%{tags: []}))
    |> json_response(415)

    authorized(token)
    |> put_req_header("content-type", "application/json; charset=utf-8")
    |> patch("/api/v2/files/not-a-uuid", Jason.encode!(%{tags: []}))
    |> json_response(404)

    unknown =
      token
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/v2/files/#{Ecto.UUID.generate()}", Jason.encode!(%{tags: [], extra: 1}))

    assert json_response(unknown, 400)["error"]["code"] == "INVALID_TAGS"

    oversized =
      token
      |> authorized()
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/v2/files/#{Ecto.UUID.generate()}",
        ~s({"tags":["#{String.duplicate("a", 70000)}"]})
      )

    assert json_response(oversized, 413)["error"]["code"] == "FILE_TOO_LARGE"
  end
end
