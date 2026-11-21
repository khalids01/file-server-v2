defmodule App.Storage.Browser do
  @moduledoc "Read-only physical storage browsing within an owner's v2 application namespaces."
  alias App.Applications.Application
  alias App.Storage.Connection

  def drives(actor) do
    with user when not is_nil(user) <- App.Accounts.active_user(actor) do
      apps = Application |> Ash.Query.sort(name: :asc) |> Ash.read!(actor: user)
      connections = Ash.read!(Connection, actor: user)
      labels = Map.new(apps, &{&1.id, &1.name})

      local =
        Enum.map(
          apps,
          &%{
            id: "local-" <> &1.id,
            name: "Local disk",
            application_id: &1.id,
            application_name: &1.name,
            type: :local
          }
        )

      s3 =
        Enum.map(
          connections,
          &%{
            id: &1.id,
            name: &1.name,
            application_id: &1.application_id,
            application_name: Map.get(labels, &1.application_id),
            type: :s3
          }
        )

      {:ok, local ++ s3}
    else
      _ -> {:error, :forbidden}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def browse(actor, id, prefix \\ "", cursor \\ nil) do
    with {:ok, prefix} <- validate_prefix(prefix),
         {:ok, drives} <- drives(actor),
         %{} = drive <- Enum.find(drives, &(&1.id == id)) do
      result =
        case drive.type do
          :local ->
            local_page(actor.id, drive.application_id, prefix, cursor)

          :s3 ->
            with {:ok, %Connection{} = conn} <- Ash.get(Connection, drive.id, actor: actor) do
              App.Storage.S3.list(
                conn,
                actor.id <> "/" <> drive.application_id <> "/" <> prefix,
                cursor
              )
            end
        end

      case result do
        {:ok, page} -> {:ok, Map.merge(page, %{drive: drive, prefix: prefix})}
        _ -> {:error, :unavailable}
      end
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp validate_prefix(""), do: {:ok, ""}

  defp validate_prefix(prefix) when is_binary(prefix) and byte_size(prefix) <= 400 do
    parts = String.split(prefix, "/", trim: true)

    if String.ends_with?(prefix, "/") and not String.starts_with?(prefix, "/") and
         Enum.all?(parts, &safe_segment?/1) and Enum.join(parts, "/") <> "/" == prefix,
       do: {:ok, prefix},
       else: {:error, :invalid}
  end

  defp validate_prefix(_), do: {:error, :invalid}

  defp safe_segment?(s),
    do:
      s not in ["", ".", ".."] and not String.contains?(s, ["/", "\\", <<0>>]) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/u, s)

  defp local_page(user_id, app_id, prefix, cursor) do
    root = Elixir.Application.fetch_env!(:app, :local_storage_path) |> Path.expand()
    # Every ancestor is checked without following symlinks. No user path is joined
    # until its individual segments have passed validation.
    parts = [user_id, app_id] ++ String.split(prefix, "/", trim: true)

    with {:ok, offset} <- offset(cursor),
         {:ok, directory} <- directory(root, parts),
         {:ok, names} <- File.ls(directory) do
      names = Enum.sort(names)
      slice = names |> Enum.drop(offset) |> Enum.take(100)

      entries =
        Enum.flat_map(slice, fn name ->
          if safe_segment?(name) do
            case File.lstat(Path.join(directory, name)) do
              {:ok, %{type: :regular, size: size}} -> [%{name: name, size: size, type: :file}]
              {:ok, %{type: :directory}} -> [%{name: name <> "/", size: 0, type: :folder}]
              _ -> []
            end
          else
            []
          end
        end)

      {:ok,
       %{
         entries: entries,
         next_cursor: if(length(names) > offset + 100, do: to_string(offset + 100))
       }}
    else
      {:error, :enoent} when prefix == "" -> {:ok, %{entries: [], next_cursor: nil}}
      _ -> {:error, :unavailable}
    end
  end

  defp directory(path, parts) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        case parts do
          [] -> {:ok, path}
          [part | rest] -> directory(Path.join(path, part), rest)
        end

      {:error, :enoent} ->
        {:error, :enoent}

      _ ->
        {:error, :unavailable}
    end
  end

  defp offset(nil), do: {:ok, 0}
  defp offset(""), do: {:ok, 0}

  defp offset(value) when is_binary(value) and byte_size(value) <= 7 do
    case Integer.parse(value) do
      {n, ""} when n >= 0 and n <= 1_000_000 -> {:ok, n}
      _ -> {:error, :invalid}
    end
  end

  defp offset(_), do: {:error, :invalid}
end
