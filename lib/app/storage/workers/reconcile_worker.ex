defmodule App.Storage.Workers.ReconcileWorker do
  @moduledoc "Periodic reconciliation for stale pending uploads and stuck deletions."
  use Oban.Worker, queue: :storage_cleanup, max_attempts: 10

  import Ecto.Query
  alias App.Repo
  alias App.Storage
  alias App.Storage.StoredFile

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    stale_before = DateTime.add(now, -15 * 60, :second)

    stale_ids =
      from(f in StoredFile,
        where: f.status == "pending" and f.created_at < ^stale_before,
        select: f.id,
        order_by: [asc: f.delete_attempts, asc: f.created_at],
        limit: 100
      )
      |> Repo.all()

    Enum.each(stale_ids, fn id ->
      _ = Storage.enqueue_cleanup(to_string(id), 0, "reconcile_stale")
    end)

    delete_ids =
      from(f in StoredFile,
        where: not is_nil(f.delete_requested_at),
        select: {f.id, f.processing_generation},
        order_by: [asc: f.delete_attempts, asc: f.created_at],
        limit: 100
      )
      |> Repo.all()

    Enum.each(delete_ids, fn {id, gen} ->
      _ = Storage.enqueue_cleanup(to_string(id), gen || 0, "delete_file")
    end)

    from(f in StoredFile,
      where: f.status == "failed",
      order_by: [asc: f.delete_attempts, asc: f.created_at],
      select: {f.id, f.processing_generation},
      limit: 100
    )
    |> Repo.all()
    |> Enum.each(fn {id, gen} -> Storage.enqueue_cleanup(id, gen, "cleanup_failed_upload") end)

    from(f in StoredFile,
      where:
        f.status == "ready" and f.processing_state in ["queued", "processing"] and
          is_nil(f.delete_requested_at),
      select: {f.id, f.processing_generation},
      limit: 100
    )
    |> Repo.all()
    |> Enum.each(fn {id, gen} ->
      %{file_id: id, generation: gen}
      |> App.Storage.Workers.ImageProcessingWorker.new()
      |> Oban.insert!()
    end)

    :ok
  end
end
