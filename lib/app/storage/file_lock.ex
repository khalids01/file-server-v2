defmodule App.Storage.FileLock do
  @moduledoc "Dedicated PostgreSQL advisory lock; never returned to the Repo pool."
  @namespace 0x711E10C5

  def with_lock(file_id, timeout \\ 30_000, fun) do
    owner = self()
    ref = make_ref()
    {guard, monitor} = spawn_monitor(fn -> guard(owner, ref, file_id) end)

    receive do
      {^ref, :locked} ->
        try do
          fun.()
        after
          send(guard, {ref, :release})

          receive do
            {:DOWN, ^monitor, :process, ^guard, _} -> :ok
          end
        end

      {:DOWN, ^monitor, :process, ^guard, reason} ->
        {:error, {:lock_failed, reason}}
    after
      timeout ->
        Process.exit(guard, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^guard, _} -> :ok
        end

        {:error, :lock_timeout}
    end
  end

  defp guard(owner, ref, file_id) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)
    opts = App.Repo.config()
    opts = Keyword.merge(opts, Ecto.Repo.Supervisor.parse_url(opts[:url] || ""))

    opts =
      Keyword.take(opts, [
        :hostname,
        :port,
        :username,
        :password,
        :database,
        :ssl,
        :ssl_opts,
        :socket_dir,
        :parameters
      ])

    {:ok, conn} =
      Postgrex.start_link(Keyword.merge(opts, backoff_type: :stop, sync_connect: true))

    key = :erlang.phash2(file_id, 0x7FFFFFFF)
    acquire(conn, key, owner_monitor, owner)
    send(owner, {ref, :locked})

    receive do
      {^ref, :release} -> GenServer.stop(conn)
      {:DOWN, ^owner_monitor, :process, ^owner, _} -> GenServer.stop(conn)
      {:EXIT, ^conn, _} -> Process.exit(owner, :kill)
    end
  end

  defp acquire(conn, key, monitor, owner) do
    case Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1, $2)", [@namespace, key]) do
      %{rows: [[true]]} ->
        :ok

      _ ->
        receive do
          {:DOWN, ^monitor, :process, ^owner, _} ->
            GenServer.stop(conn)
            exit(:normal)

          {:EXIT, ^conn, reason} ->
            exit(reason)
        after
          25 -> acquire(conn, key, monitor, owner)
        end
    end
  end
end
