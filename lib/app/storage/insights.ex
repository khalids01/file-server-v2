defmodule App.Storage.Insights do
  @moduledoc "Owner-scoped application storage totals and recoverable file issues."
  alias App.{Repo, Storage}
  alias App.Storage.StoredFile

  @zero %{
    files: 0,
    original_bytes: 0,
    variant_bytes: 0,
    reserved_bytes: 0,
    image_pending: 0,
    image_failed: 0,
    cleanup_pending: 0,
    upload_pending: 0
  }

  def account(actor) do
    with %{} = actor <- App.Accounts.active_user(actor) do
      apps = metrics(actor.id, nil)

      totals =
        Enum.reduce(Map.values(apps), @zero, fn row, acc ->
          Map.merge(acc, row, fn _, a, b -> a + b end)
        end)

      {:ok,
       %{
         applications: apps,
         totals: totals,
         application_count: Ash.count!(App.Applications.Application, actor: actor),
         quota: Storage.Quota.status_for_user(actor.id)
       }}
    else
      _ -> {:error, :forbidden}
    end
  end

  def application(actor, app_id) do
    with {:ok, app} <- Ash.get(App.Applications.Application, app_id, actor: actor) do
      rows = metrics(app.user_id, app.id)
      {:ok, %{metrics: Map.get(rows, app.id, @zero), issues: issues(actor, app.id)}}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def retry(actor, app_id, file_id) do
    with {:ok, _} <- Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, %StoredFile{application_id: ^app_id} = file} <-
           Ash.get(StoredFile, file_id, actor: actor) do
      cond do
        file.delete_requested_at ->
          queued(Storage.enqueue_cleanup(file.id, file.processing_generation, "delete_file"))

        file.status == "failed" ->
          queued(
            Storage.enqueue_cleanup(file.id, file.processing_generation, "cleanup_failed_upload")
          )

        file.status == "pending" and stale?(file.created_at) ->
          queued(Storage.enqueue_cleanup(file.id, file.processing_generation, "reconcile_stale"))

        file.status == "ready" and file.processing_state == "failed" ->
          queued(Storage.retry_processing(actor, file.id))

        true ->
          {:error, :not_retryable}
      end
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp queued({:ok, _}), do: :ok
  defp queued(_), do: {:error, :unavailable}
  defp stale?(date), do: DateTime.diff(DateTime.utc_now(), date) >= 900

  defp metrics(user_id, app_id) do
    # Aggregate variants independently to avoid multiplying original bytes/counts.
    result =
      Repo.query!(
        """
        SELECT f.application_id,
          count(*) FILTER (WHERE f.ready_at IS NOT NULL),
          coalesce(sum(f.size) FILTER (WHERE f.ready_at IS NOT NULL),0),
          coalesce(sum(v.bytes),0), coalesce(sum(f.reserved_bytes),0),
          count(*) FILTER (WHERE f.status='ready' AND f.processing_state IN ('queued','processing') AND f.delete_requested_at IS NULL),
          count(*) FILTER (WHERE f.status='ready' AND f.processing_state='failed' AND f.delete_requested_at IS NULL),
          count(*) FILTER (WHERE f.delete_requested_at IS NOT NULL OR f.status='failed' OR (f.status='pending' AND f.created_at < now()-interval '15 minutes')),
          count(*) FILTER (WHERE f.status='pending')
        FROM stored_files f
        JOIN applications a ON a.id=f.application_id AND a.user_id=$1
        LEFT JOIN (SELECT sv.file_id, sum(sv.size) AS bytes FROM stored_file_variants sv JOIN stored_files sf ON sf.id=sv.file_id WHERE sv.status='ready' AND sf.user_id=$1 AND ($2::uuid IS NULL OR sf.application_id=$2) GROUP BY sv.file_id) v ON v.file_id=f.id
        WHERE f.user_id=$1 AND ($2::uuid IS NULL OR f.application_id=$2)
        GROUP BY f.application_id
        """,
        [Ecto.UUID.dump!(user_id), if(app_id, do: Ecto.UUID.dump!(app_id))]
      )

    Map.new(result.rows, fn [id | values] ->
      keys = [
        :files,
        :original_bytes,
        :variant_bytes,
        :reserved_bytes,
        :image_pending,
        :image_failed,
        :cleanup_pending,
        :upload_pending
      ]

      {Ecto.UUID.load!(id), Map.new(Enum.zip(keys, Enum.map(values, &integer/1)))}
    end)
  end

  defp integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer(value), do: value

  defp issues(actor, app_id) do
    require Ash.Query
    cutoff = DateTime.add(DateTime.utc_now(), -900)

    StoredFile
    |> Ash.Query.filter(
      application_id == ^app_id and
        (not is_nil(delete_requested_at) or status == "failed" or
           (status == "pending" and created_at < ^cutoff) or
           (status == "ready" and processing_state == "failed"))
    )
    |> Ash.Query.sort(created_at: :asc, id: :asc)
    |> Ash.Query.limit(25)
    |> Ash.read!(actor: actor)
    |> Enum.map(fn file ->
      {kind, message} =
        cond do
          file.delete_requested_at ->
            {"Deletion pending", "Storage removal must succeed before bytes are released."}

          file.status == "failed" ->
            {"Upload cleanup", "A failed write is awaiting cleanup; reserved bytes are retained."}

          file.status == "pending" ->
            {"Interrupted upload",
             "This upload is over 15 minutes old. Recovery will recheck it under a file lock."}

          true ->
            {"Image processing failed",
             "The original remains available. Retry after checking the image or storage connection."}
        end

      %{
        id: file.id,
        filename: file.filename,
        kind: kind,
        message: message,
        attempts: file.delete_attempts
      }
    end)
  end
end
