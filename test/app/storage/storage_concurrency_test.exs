defmodule App.Storage.StorageConcurrencyTest do
  use ExUnit.Case, async: false
  alias App.Storage.{Quota, FileLock}
  alias App.Repo

  # Separate actual committed connections: Sandbox's shared connection cannot prove row-lock contention.
  test "simultaneous reservations cannot exceed an account quota" do
    id = Ecto.UUID.generate()
    raw = Ecto.UUID.dump!(id)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("INSERT INTO users (id,email) VALUES ($1,$2)", [raw, "quota-#{id}@example.com"])
      Quota.ensure_account!(id)
      Repo.query!("UPDATE account_storage SET quota_bytes=100 WHERE user_id=$1", [raw])
    end)

    try do
      results =
        1..12
        |> Task.async_stream(
          fn _ ->
            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> Quota.reserve(id, 30) end)
          end,
          max_concurrency: 12
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 3
      assert Enum.count(results, &(&1 == {:error, :quota_exceeded})) == 9

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        assert Quota.status_for_user(id).reserved_bytes == 90
      end)
    after
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM users WHERE id=$1", [raw])
      end)
    end
  end

  test "file lock survives acquisition timeout and releases on owner death" do
    key = Ecto.UUID.generate()
    parent = self()

    owner =
      spawn(fn ->
        FileLock.with_lock(key, 50, fn ->
          send(parent, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held, 2_000

    assert {:error, :lock_timeout} =
             FileLock.with_lock(key, 100, fn -> flunk("entered active lock") end)

    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _}
    assert :released = FileLock.with_lock(key, 2_000, fn -> :released end)
  end
end
