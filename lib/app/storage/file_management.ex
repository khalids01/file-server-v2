defmodule App.Storage.FileManagement do
  @moduledoc "Application-scoped file details and bounded bulk operations."
  alias App.Storage
  alias App.Storage.StoredFile

  def details(actor, app_id, id) do
    with {:ok, _} <- Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, %StoredFile{application_id: ^app_id, status: "ready"} = file} <-
           Ash.get(StoredFile, id, actor: actor, load: [:variants]) do
      {:ok, file}
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  def bulk(actor, app_id, ids, action) do
    with {:ok, ids} <- validate_ids(ids),
         :ok <- validate_action(action),
         {:ok, _} <- Ash.get(App.Applications.Application, app_id, actor: actor) do
      results = Enum.map(ids, fn id -> {id, apply_action(actor, app_id, id, action)} end)

      {:ok,
       %{
         succeeded: for({id, :ok} <- results, do: id),
         failed: for({id, {:error, reason}} <- results, do: %{id: id, reason: reason})
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp validate_ids(ids) when is_list(ids) and length(ids) in 1..25 do
    normalized =
      Enum.map(ids, fn id -> if is_binary(id), do: Ecto.UUID.cast(id), else: :error end)

    if Enum.all?(normalized, &match?({:ok, _}, &1)) and
         length(Enum.uniq(normalized)) == length(ids) do
      {:ok, Enum.map(normalized, &elem(&1, 1))}
    else
      {:error, :invalid_selection}
    end
  end

  defp validate_ids(_), do: {:error, :invalid_selection}
  defp validate_action(:delete), do: :ok

  defp validate_action({mode, tags}) when mode in [:add, :remove, :replace] do
    case Storage.validate_tags(tags) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_tags}
    end
  end

  defp validate_action(_), do: {:error, :invalid_action}

  defp apply_action(actor, app_id, id, action) do
    with {:ok, file} <- details(actor, app_id, id) do
      case action do
        :delete ->
          Storage.delete(actor, file.id)

        {mode, tags} ->
          case Storage.change_tags(actor, app_id, id, mode, tags) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
