defmodule App.Storage.Workers.CleanupWorker do
  @moduledoc "Durably cleans up failed/stale uploads and requested deletions."
  use Oban.Worker,
    queue: :storage_cleanup,
    max_attempts: 20,
    unique: [
      period: 60,
      keys: [:file_id, :action, :generation],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias App.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id, "action" => action} = args}) do
    generation = Map.get(args, "generation")

    case action do
      "cleanup_failed_upload" -> Storage.cleanup_failed_upload(file_id, generation)
      "delete_file" -> Storage.cleanup_delete(file_id, generation)
      "reconcile_stale" -> Storage.reconcile_stale_upload(file_id)
      _ -> :ok
    end
  end
end
