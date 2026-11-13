defmodule App.Storage.Workers.ImageProcessingWorker do
  @moduledoc "Processes uploaded images into fixed variants with bounded native execution."
  use Oban.Worker,
    queue: :image_processing,
    max_attempts: 5,
    unique: [
      period: 300,
      keys: [:file_id, :generation],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger
  alias App.Repo
  alias App.Storage
  alias App.Storage.StoredFile

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id, "generation" => generation}}) do
    with {:ok, file} <- fetch_file(file_id),
         true <- file.processing_generation == generation,
         true <- file.status in ["ready", "pending", "processing_failed", "processing"],
         :ok <- Storage.process_image(file) do
      :ok
    else
      {:error, :not_found} ->
        :ok

      false ->
        :ok

      {:error, :unsupported} ->
        :ok

      {:error, reason} ->
        Logger.warning("image processing failed for #{file_id}: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.warning("image processing skipped for #{file_id}: #{inspect(other)}")
        :ok
    end
  end

  defp fetch_file(id) do
    case Repo.get(StoredFile, id) |> maybe_load() do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp maybe_load(nil), do: nil

  defp maybe_load(%StoredFile{} = file),
    do: Ash.load!(file, [:variants, :connection, :application], authorize?: false)
end
