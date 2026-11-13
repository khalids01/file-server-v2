defmodule App.Storage.Local do
  @moduledoc "Private local storage rooted in an operator-configured directory, never a user path."
  def path(key, create? \\ false) do
    root = Application.fetch_env!(:app, :local_storage_path) |> Path.expand()
    parts = String.split(key, "/")

    if length(parts) == 3 and Enum.all?(parts, &(Ecto.UUID.cast(&1) != :error)) do
      with :ok <- root_directory(root, create?),
           :ok <- directories(root, Enum.take(parts, 2), create?) do
        path = Path.join([root | parts])

        case File.lstat(path) do
          {:ok, %{type: :regular}} -> {:ok, path}
          {:error, :enoent} when create? -> {:ok, path}
          {:error, :enoent} -> {:error, :enoent}
          _ -> {:error, :unavailable}
        end
      end
    else
      {:error, :unavailable}
    end
  end

  defp root_directory(root, create?) do
    if create?, do: File.mkdir_p!(root)

    case File.lstat(root) do
      {:ok, %{type: :directory}} -> if create?, do: File.chmod(root, 0o700), else: :ok
      _ -> {:error, :unavailable}
    end
  end

  defp directories(_, [], _), do: :ok

  defp directories(root, [part | rest], create?) do
    next = Path.join(root, part)
    if create?, do: File.mkdir(next)

    case File.lstat(next) do
      {:ok, %{type: :directory}} ->
        with :ok <- if(create?, do: File.chmod(next, 0o700), else: :ok),
             do: directories(next, rest, create?)

      _ ->
        {:error, :unavailable}
    end
  end

  def put(key, source) do
    with {:ok, path} <- path(key, true),
         {:ok, io} <- File.open(path, [:write, :binary, :exclusive]) do
      try do
        File.chmod!(path, 0o600)
        source |> File.stream!(65_536) |> Enum.each(fn chunk -> :ok = IO.binwrite(io, chunk) end)
        :ok
      rescue
        _ ->
          File.rm(path)
          {:error, :unavailable}
      after
        File.close(io)
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  def delete(key) do
    case path(key) do
      {:ok, path} -> File.rm(path)
      {:error, :enoent} -> :ok
      {:error, _} -> {:error, :unavailable}
    end
  end
end
