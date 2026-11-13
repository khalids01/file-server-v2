defmodule App.Storage.Quota do
  @moduledoc "Atomic per-account storage quota reservations and accounting."
  alias App.Repo

  @default_quota 5 * 1024 * 1024 * 1024

  def default_quota, do: Application.get_env(:app, :storage_quota_bytes, @default_quota)

  def ensure_account!(repo \\ Repo, user_id) when not is_nil(user_id) do
    %Postgrex.Result{} =
      repo.query!(
        "INSERT INTO account_storage (user_id, quota_bytes, used_bytes, reserved_bytes) VALUES ($1, $2, 0, 0) ON CONFLICT (user_id) DO NOTHING",
        [dump!(user_id), default_quota()]
      )

    :ok
  end

  def status_for_user(user_id) do
    ensure_account!(user_id)

    case Repo.query(
           "SELECT quota_bytes, used_bytes, reserved_bytes FROM account_storage WHERE user_id = $1",
           [dump!(user_id)]
         ) do
      {:ok, %{rows: [[quota, used, reserved]]}} ->
        quota = quota || default_quota()
        used = used || 0
        reserved = reserved || 0

        if used < 0 or reserved < 0 or quota < 0 do
          raise "account storage accounting corrupted for user #{inspect(user_id)}"
        end

        %{
          quota_bytes: quota,
          used_bytes: used,
          reserved_bytes: reserved,
          available_bytes: max(quota - used - reserved, 0)
        }

      _ ->
        raise "account storage usage unavailable"
    end
  end

  def reserve(user_id, bytes) when is_integer(bytes) and bytes >= 0 do
    Repo.transaction(fn ->
      case reserve_in(repo_tx(), user_id, bytes) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize()
  end

  def adjust(user_id, used_delta, reserved_delta)
      when is_integer(used_delta) and is_integer(reserved_delta) do
    Repo.transaction(fn ->
      case adjust_in(repo_tx(), user_id, used_delta, reserved_delta) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize()
  end

  # Use Repo inside transaction blocks (Ecto routes to checked-out connection).
  defp repo_tx, do: Repo

  def reserve_in(repo, user_id, bytes) when is_integer(bytes) and bytes >= 0 do
    ensure_account!(repo, user_id)
    id = dump!(user_id)

    case repo.query(
           "SELECT quota_bytes, used_bytes, reserved_bytes FROM account_storage WHERE user_id = $1 FOR UPDATE",
           [id]
         ) do
      {:ok, %{rows: [[quota, used, reserved]]}} ->
        quota = quota || default_quota()
        used = used || 0
        reserved = reserved || 0

        cond do
          used < 0 or reserved < 0 or quota < 0 ->
            {:error, :accounting_corrupt}

          used + reserved + bytes > quota ->
            {:error, :quota_exceeded}

          true ->
            %Postgrex.Result{num_rows: 1} =
              repo.query!(
                "UPDATE account_storage SET reserved_bytes = $2, updated_at = now() WHERE user_id = $1",
                [id, reserved + bytes]
              )

            :ok
        end

      _ ->
        {:error, :not_found}
    end
  end

  def adjust_in(repo, user_id, used_delta, reserved_delta)
      when is_integer(used_delta) and is_integer(reserved_delta) do
    ensure_account!(repo, user_id)
    id = dump!(user_id)

    case repo.query(
           "SELECT quota_bytes, used_bytes, reserved_bytes FROM account_storage WHERE user_id = $1 FOR UPDATE",
           [id]
         ) do
      {:ok, %{rows: [[quota, used, reserved]]}} ->
        quota = quota || default_quota()
        used = used || 0
        reserved = reserved || 0
        new_used = used + used_delta
        new_reserved = reserved + reserved_delta

        cond do
          used < 0 or reserved < 0 or quota < 0 ->
            {:error, :accounting_corrupt}

          new_used < 0 or new_reserved < 0 ->
            {:error, :accounting_corrupt}

          true ->
            %Postgrex.Result{num_rows: 1} =
              repo.query!(
                "UPDATE account_storage SET used_bytes = $2, reserved_bytes = $3, updated_at = now() WHERE user_id = $1",
                [id, new_used, new_reserved]
              )

            :ok
        end

      _ ->
        {:error, :not_found}
    end
  end

  def dump!(id) when is_binary(id), do: Ecto.UUID.dump!(id)
  def dump!(id), do: id

  defp normalize({:ok, v}), do: {:ok, v}
  defp normalize({:error, reason}), do: {:error, reason}
end
