defmodule App.Storage do
  @moduledoc "Private application files on local disk or immutable S3 destinations."
  use Ash.Domain, otp_app: :app
  require Ash.Query
  alias App.Storage.{Connection, StoredFile, Local, S3}

  resources do
    resource Connection
    resource StoredFile
  end

  def max_file_size, do: Application.get_env(:app, :max_file_size, 50 * 1024 * 1024)

  def connections(actor, app_id),
    do: Connection |> Ash.Query.filter(application_id == ^app_id) |> Ash.read!(actor: actor)

  def files(actor, app_id),
    do:
      StoredFile
      |> Ash.Query.filter(application_id == ^app_id)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: actor)

  @file_per_page 25
  @file_sorts %{
    "newest" => [created_at: :desc, id: :desc],
    "oldest" => [created_at: :asc, id: :asc],
    "name" => [filename: :asc, id: :asc],
    "size" => [size: :desc, id: :desc]
  }

  def file_sorts, do: Map.keys(@file_sorts)
  def files_per_page, do: @file_per_page

  def files_page(actor, app_id, opts \\ []) do
    search = normalize_search(Keyword.get(opts, :search))

    sort =
      if Keyword.get(opts, :sort) in Map.keys(@file_sorts),
        do: Keyword.get(opts, :sort),
        else: "newest"

    page = normalize_page(Keyword.get(opts, :page))

    query = StoredFile |> Ash.Query.filter(application_id == ^app_id)

    query =
      if search == "", do: query, else: Ash.Query.filter(query, contains(filename, ^search))

    total = Ash.count!(query, actor: actor)
    pages = Kernel.max(ceil(total / @file_per_page), 1)
    page = Kernel.min(page, pages)

    files =
      query
      |> Ash.Query.sort(@file_sorts[sort])
      |> Ash.Query.offset((page - 1) * @file_per_page)
      |> Ash.Query.limit(@file_per_page)
      |> Ash.read!(actor: actor)

    %{
      files: files,
      total: total,
      page: page,
      limit: @file_per_page,
      pages: pages,
      search: search,
      sort: sort
    }
  end

  defp normalize_search(nil), do: ""

  defp normalize_search(value) when is_binary(value) do
    String.trim(value) |> String.slice(0, 200)
  end

  defp normalize_search(_), do: ""

  defp normalize_page(value) when is_integer(value) and value >= 1, do: Kernel.min(value, 100_000)

  defp normalize_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 -> Kernel.min(n, 100_000)
      _ -> 1
    end
  end

  defp normalize_page(_), do: 1

  def counts(actor) do
    StoredFile
    |> Ash.Query.select([:application_id])
    |> Ash.read!(actor: actor)
    |> Enum.frequencies_by(& &1.application_id)
  end

  def valid_connection?(actor, app_id, nil), do: not is_nil(actor) and is_binary(app_id)

  def valid_connection?(actor, app_id, id) do
    case Ash.get(Connection, id, actor: actor) do
      {:ok, %Connection{application_id: ^app_id}} -> true
      _ -> false
    end
  end

  def create_connection(actor, app_id, attrs) do
    with {:ok, %App.Applications.Application{}} <-
           Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, endpoint} <- App.Storage.Endpoint.validate(attrs["endpoint"]),
         true <- valid?(attrs["bucket"], ~r/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/),
         true <- valid?(attrs["region"], ~r/^[a-z0-9-]{1,64}$/),
         true <-
           Enum.all?(["access_key_id", "secret_access_key"], fn key ->
             is_binary(attrs[key]) and byte_size(attrs[key]) in 1..2048
           end),
         {:ok, encrypted} <-
           App.Vault.encrypt(
             Jason.encode!(Map.take(attrs, ["access_key_id", "secret_access_key"]))
           ) do
      Ash.create(
        Connection,
        %{
          name: attrs["name"],
          endpoint: endpoint,
          bucket: attrs["bucket"],
          region: attrs["region"],
          credentials: encrypted,
          application_id: app_id
        },
        actor: actor,
        authorize?: false
      )
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "Check the connection fields and application permissions."}
    end
  rescue
    _ -> {:error, "Unable to save the storage connection."}
  end

  def environment_available? do
    env = environment()

    Enum.all?(
      ~w(S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_BUCKET S3_REGION S3_ENDPOINT),
      &(is_binary(env[&1]) and env[&1] != "")
    )
  end

  def environment_connection(actor, app_id) do
    env = environment()

    create_connection(actor, app_id, %{
      "name" => "S3 from environment",
      "endpoint" => env["S3_ENDPOINT"],
      "bucket" => env["S3_BUCKET"],
      "region" => env["S3_REGION"],
      "access_key_id" => env["S3_ACCESS_KEY_ID"],
      "secret_access_key" => env["S3_SECRET_ACCESS_KEY"]
    })
  end

  def test_connection(actor, app_id, nil) do
    with {:ok, %App.Applications.Application{}} <-
           Ash.get(App.Applications.Application, app_id, actor: actor) do
      key = actor.id <> "/" <> app_id <> "/" <> Ecto.UUID.generate()
      source = Path.join(System.tmp_dir!(), "serve-test-" <> Ecto.UUID.generate())

      try do
        File.write!(source, "storage-check", [:exclusive])

        with :ok <- Local.put(key, source),
             {:ok, path} <- Local.path(key),
             {:ok, "storage-check"} <- File.read(path),
             :ok <- Local.delete(key),
             do: :ok
      after
        File.rm(source)
        Local.delete(key)
      end
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def test_connection(actor, app_id, id) do
    with {:ok, %Connection{application_id: ^app_id} = conn} <-
           Ash.get(Connection, id, actor: actor) do
      # Exercise the same object permissions used by uploads and deletion, without listing a bucket.
      key = actor.id <> "/" <> app_id <> "/check-" <> Ecto.UUID.generate()

      result =
        with :ok <- S3.request(conn, :put, key, body: "storage-check"),
             do: S3.request(conn, :head, key)

      cleanup = S3.request(conn, :delete, key)
      if result == :ok and cleanup == :ok, do: :ok, else: {:error, :unavailable}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def upload(actor, app_id, path, filename, content_type) do
    limit = max_file_size()

    with {:ok, %App.Applications.Application{} = app} <-
           Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, %{type: :regular, size: size}} when size <= limit <- File.stat(path) do
      id = Ecto.UUID.generate()
      key = actor.id <> "/" <> app.id <> "/" <> id

      connection =
        if app.storage_connection_id,
          do: Ash.get!(Connection, app.storage_connection_id, actor: actor)

      result = if connection, do: S3.put(connection, key, path, size), else: Local.put(key, path)

      with :ok <- result do
        case Ash.create(
               StoredFile,
               %{
                 filename: filename(filename),
                 size: size,
                 content_type: content_type || "application/octet-stream",
                 object_key: key,
                 application_id: app.id,
                 connection_id: app.storage_connection_id
               },
               actor: actor,
               authorize?: false
             ) do
          {:ok, file} ->
            {:ok, file}

          error ->
            remove_object(connection, key)
            error
        end
      end
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def download(actor, id) do
    with {:ok, %StoredFile{} = file} <- Ash.get(StoredFile, id, actor: actor) do
      if file.connection_id do
        connection = Ash.get!(Connection, file.connection_id, actor: actor)
        path = Path.join(System.tmp_dir!(), "serve-download-" <> Ecto.UUID.generate())

        if S3.download(connection, file.object_key, path, file.size) == :ok do
          {:ok, %{path: path, filename: file.filename, temporary?: true}}
        else
          File.rm(path)
          {:error, :unavailable}
        end
      else
        with {:ok, path} <- Local.path(file.object_key),
             do: {:ok, %{path: path, filename: file.filename, temporary?: false}}
      end
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def delete(actor, id) do
    with {:ok, %StoredFile{} = file} <- Ash.get(StoredFile, id, actor: actor) do
      connection =
        if file.connection_id, do: Ash.get!(Connection, file.connection_id, actor: actor)

      with :ok <- remove_object(connection, file.object_key),
           do: Ash.destroy(file, authorize?: false)
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp remove_object(nil, key), do: Local.delete(key)
  defp remove_object(connection, key), do: S3.request(connection, :delete, key)
  defp valid?(value, regex), do: is_binary(value) and Regex.match?(regex, value)

  defp environment,
    do:
      Application.get_env(:app, :storage_environment) ||
        Map.take(
          System.get_env(),
          ~w(S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_BUCKET S3_REGION S3_ENDPOINT)
        )

  defp filename(name) do
    name =
      name
      |> to_string()
      |> String.replace("\\", "/")
      |> Path.basename()
      |> String.replace(~r/[\x00-\x1f\x7f]/u, "")
      |> String.slice(0, 255)

    if name in ["", ".", ".."], do: "download", else: name
  end
end
