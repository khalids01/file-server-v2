defmodule AppWeb.FileApiSmokeTest do
  use AppWeb.ConnCase, async: false
  import App.AuthHelpers

  test "Node example client exercises the real HTTP API using separate scoped keys" do
    root = Path.join(System.tmp_dir!(), "serve-client-#{Ecto.UUID.generate()}")
    previous = Application.get_env(:app, :local_storage_path)
    Application.put_env(:app, :local_storage_path, root)

    on_exit(fn ->
      Application.put_env(:app, :local_storage_path, previous)
      File.rm_rf!(root)
    end)

    owner = user("smoke-#{Ecto.UUID.generate()}@example.com")

    app =
      Ash.create!(App.Applications.Application, %{name: "Client fixture", slug: "client"},
        actor: owner
      )

    keys =
      for {name, scopes} <- [
            {"READ", ["files:read"]},
            {"WRITE", ["files:write"]},
            {"DELETE", ["files:delete"]},
            {"REVOKED", ["files:read"]}
          ] do
        {key, token} = App.Applications.issue_key!(owner, app.id, name, scopes)
        if name == "REVOKED", do: Ash.update!(key, %{}, action: :revoke, actor: owner)
        {"FILE_API_#{name}_KEY", token}
      end

    server = start_supervised!({Bandit, plug: AppWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    {output, status} =
      System.cmd("node", ["scripts/file_api_smoke.mjs"],
        env: [{"FILE_API_BASE_URL", "http://127.0.0.1:#{port}"} | keys],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "smoke passed: 8 checks including revoked key"
    assert App.Storage.files(owner, app.id) == []
  end
end
