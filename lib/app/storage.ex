defmodule App.Storage do
  @moduledoc "Private application files on local disk or immutable S3 destinations."
  use Ash.Domain, otp_app: :app
  require Ash.Query
  alias App.Repo

  alias App.Storage.{
    AccountStorage,
    Connection,
    StoredFile,
    StoredFileVariant,
    Local,
    S3,
    Quota,
    ImageProcessing,
    FileLock
  }

  alias App.Storage.Workers.{CleanupWorker, ImageProcessingWorker}

  resources do
    resource AccountStorage
    resource Connection
    resource StoredFile
    resource StoredFileVariant
  end

  def max_file_size, do: Application.get_env(:app, :max_file_size, 50 * 1024 * 1024)
  def quota_bytes, do: Application.get_env(:app, :storage_quota_bytes, 5 * 1024 * 1024 * 1024)

  def image_processing_timeout_ms,
    do: Application.get_env(:app, :image_processing_timeout_ms, 10_000)

  def image_max_input_pixels, do: Application.get_env(:app, :image_max_input_pixels, 40_000_000)

  def image_max_output_bytes,
    do: Application.get_env(:app, :image_max_output_bytes, 5 * 1024 * 1024)

  def image_max_header_bytes, do: 50 * 1024 * 1024

  @max_tags 20
  @max_tag_length 64
  @max_tag_bytes 256
  @stale_pending_seconds 15 * 60

  def max_tags, do: @max_tags
  def max_tag_length, do: @max_tag_length
  def max_tag_bytes, do: @max_tag_bytes

  # ---- tags ----
  def validate_tags(tags) when is_list(tags) do
    if length(tags) > @max_tags do
      {:error, "Too many tags. Use at most #{@max_tags} tags."}
    else
      tags
      |> Enum.reduce_while({:ok, []}, fn tag, {:ok, acc} ->
        case normalize_tag(tag) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          {:error, message} -> {:halt, {:error, message}}
        end
      end)
      |> case do
        {:ok, reversed} -> {:ok, reversed |> Enum.reverse() |> Enum.uniq_by(&String.downcase/1)}
        error -> error
      end
    end
  end

  def validate_tags(_), do: {:error, "Tags must be a list of strings."}

  defp normalize_tag(tag) when is_binary(tag) do
    if String.contains?(tag, ["\n", "\r", "\t"]) or String.contains?(tag, <<0>>) or
         String.match?(tag, ~r/[\x00-\x1f\x7f]/u) do
      {:error, "Tags cannot contain line breaks or control characters."}
    else
      trimmed = String.trim(tag)

      cond do
        trimmed == "" ->
          {:error, "Tags cannot be empty."}

        String.length(trimmed) > @max_tag_length ->
          {:error, "Tags cannot exceed #{@max_tag_length} characters."}

        byte_size(trimmed) > @max_tag_bytes ->
          {:error, "Tags cannot exceed #{@max_tag_bytes} bytes."}

        true ->
          {:ok, trimmed}
      end
    end
  end

  defp normalize_tag(_), do: {:error, "Tags must be strings."}

  # ---- listing ----
  def connections(actor, app_id),
    do: Connection |> Ash.Query.filter(application_id == ^app_id) |> Ash.read!(actor: actor)

  def files(actor, app_id),
    do:
      StoredFile
      |> Ash.Query.filter(application_id == ^app_id and status == "ready")
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.Query.load(:variants)
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

    case validate_tags_filter(Keyword.get(opts, :tags)) do
      {:ok, tags} ->
        sort =
          if Keyword.get(opts, :sort) in Map.keys(@file_sorts),
            do: Keyword.get(opts, :sort),
            else: "newest"

        page = normalize_page(Keyword.get(opts, :page))
        query = StoredFile |> Ash.Query.filter(application_id == ^app_id and status == "ready")

        query =
          if search == "", do: query, else: Ash.Query.filter(query, contains(filename, ^search))

        query =
          Enum.reduce(tags, query, fn tag, acc ->
            Ash.Query.filter(
              acc,
              fragment(
                "EXISTS (SELECT 1 FROM unnest(?) AS t(value) WHERE lower(t.value) = lower(?))",
                tags,
                ^tag
              )
            )
          end)

        total = Ash.count!(query, actor: actor)
        pages = Kernel.max(ceil(total / @file_per_page), 1)
        page = Kernel.min(page, pages)

        files =
          query
          |> Ash.Query.sort(@file_sorts[sort])
          |> Ash.Query.offset((page - 1) * @file_per_page)
          |> Ash.Query.limit(@file_per_page)
          |> Ash.Query.load(:variants)
          |> Ash.read!(actor: actor)

        %{
          files: files,
          total: total,
          page: page,
          limit: @file_per_page,
          pages: pages,
          search: search,
          sort: sort,
          tags: tags
        }

      {:error, _} ->
        {:error, :invalid_tags}
    end
  end

  def validate_tags_filter(nil), do: {:ok, []}

  def validate_tags_filter(tags) when is_list(tags) do
    cond do
      Enum.any?(tags, &(not is_binary(&1))) -> {:error, "Tags must be a list of strings."}
      Enum.any?(tags, &(String.trim(&1) == "")) -> {:error, "Tags cannot be empty."}
      true -> validate_tags(tags)
    end
  end

  def validate_tags_filter(_), do: {:error, "Tags must be a list of strings."}

  defp normalize_search(nil), do: ""
  defp normalize_search(v) when is_binary(v), do: String.trim(v) |> String.slice(0, 200)
  defp normalize_search(_), do: ""
  defp normalize_page(v) when is_integer(v) and v >= 1, do: Kernel.min(v, 100_000)

  defp normalize_page(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n >= 1 -> Kernel.min(n, 100_000)
      _ -> 1
    end
  end

  defp normalize_page(_), do: 1

  def counts(actor) do
    StoredFile
    |> Ash.Query.filter(status == "ready")
    |> Ash.Query.select([:application_id])
    |> Ash.read!(actor: actor)
    |> Enum.frequencies_by(& &1.application_id)
  end

  def quota_status(actor, app_id) do
    with {:ok, app} <- Ash.get(App.Applications.Application, app_id, actor: actor) do
      Quota.status_for_user(app.user_id)
    else
      _ ->
        %{
          quota_bytes: quota_bytes(),
          used_bytes: 0,
          reserved_bytes: 0,
          available_bytes: quota_bytes()
        }
    end
  end

  # ---- tags update ----
  def update_tags(actor, app_id, file_id, tags),
    do: change_tags(actor, app_id, file_id, :replace, tags)

  def change_tags(actor, app_id, file_id, mode, tags) when mode in [:add, :remove, :replace] do
    with {:ok, _app} <- Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, normalized} <- validate_tags(tags) do
      FileLock.with_lock(file_id, fn ->
        with {:ok, %StoredFile{status: "ready"} = file} <-
               fetch_scoped_file(actor, file_id, app_id) do
          updated =
            case mode do
              :replace ->
                normalized

              :add ->
                (file.tags ++ normalized) |> Enum.uniq_by(&String.downcase/1)

              :remove ->
                removed = MapSet.new(Enum.map(normalized, &String.downcase/1))
                Enum.reject(file.tags, &MapSet.member?(removed, String.downcase(&1)))
            end

          with {:ok, validated} <- validate_tags(updated) do
            file
            |> Ash.Changeset.for_update(:update_tags, %{tags: validated}, actor: actor)
            |> internal_update()
          else
            {:error, message} -> {:error, {:invalid_tags, message}}
          end
        else
          _ -> {:error, :not_found}
        end
      end)
    else
      {:error, message} when is_binary(message) -> {:error, {:invalid_tags, message}}
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp fetch_scoped_file(actor, file_id, app_id) do
    with {:ok, %StoredFile{} = file} <-
           Ash.get(StoredFile, file_id, actor: actor, load: [:variants]),
         true <- file.application_id == app_id do
      {:ok, file}
    else
      _ -> {:error, :not_found}
    end
  end

  # ---- connections ----
  def valid_connection?(actor, app_id, nil), do: not is_nil(actor) and is_binary(app_id)

  def valid_connection?(actor, app_id, id) do
    case Ash.get(Connection, id, actor: actor) do
      {:ok, %Connection{application_id: ^app_id}} -> true
      _ -> false
    end
  end

  def create_connection(actor, app_id, attrs) do
    with {:ok, _} <- Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, endpoint} <- App.Storage.Endpoint.validate(attrs["endpoint"]),
         true <- valid?(attrs["bucket"], ~r/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/),
         true <- valid?(attrs["region"], ~r/^[a-z0-9-]{1,64}$/),
         true <-
           Enum.all?(["access_key_id", "secret_access_key"], fn k ->
             is_binary(attrs[k]) and byte_size(attrs[k]) in 1..2048
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
    with {:ok, _} <- Ash.get(App.Applications.Application, app_id, actor: actor) do
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

  # ---- upload lifecycle ----
  def upload(actor, app_id, path, filename, content_type, opts \\ []) do
    limit = max_file_size()

    with :ok <- validate_optional_tags(Keyword.get(opts, :tags)),
         {:ok, app} <- Ash.get(App.Applications.Application, app_id, actor: actor),
         {:ok, %{type: :regular, size: size}} when size > 0 and size <= limit <- File.stat(path),
         {:ok, file, conn} <-
           reserve_and_create_pending(
             actor,
             app,
             path,
             filename(filename),
             content_type || "application/octet-stream",
             size,
             validated_tags(Keyword.get(opts, :tags))
           ) do
      perform_upload_io(file, conn, path, size)
    else
      {:error, :quota_exceeded} -> {:error, :quota_exceeded}
      {:error, {:invalid_tags, message}} -> {:error, {:invalid_tags, message}}
      {:error, :too_large} -> {:error, :too_large}
      {:ok, %{size: size}} when size > limit -> {:error, :too_large}
      {:ok, %{size: 0}} -> {:error, :invalid}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp reserve_and_create_pending(actor, app, _path, filename, content_type, size, tags) do
    file_id = Ecto.UUID.generate()
    object_key = actor.id <> "/" <> app.id <> "/" <> file_id
    op_id = Ecto.UUID.generate()

    conn =
      if app.storage_connection_id,
        do: Ash.get!(Connection, app.storage_connection_id, actor: actor)

    candidate = ImageProcessing.candidate?(content_type, filename)

    processing_state =
      if match?({:ok, _}, candidate) or match?({:skip, _}, candidate),
        do: "pending",
        else: "not_applicable"

    transaction(fn ->
      case Quota.reserve_in(Repo, app.user_id, size) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      attrs = %{
        id: file_id,
        filename: filename,
        size: size,
        content_type: content_type,
        object_key: object_key,
        application_id: app.id,
        connection_id: app.storage_connection_id,
        tags: tags,
        status: "pending",
        processing_state: processing_state,
        reserved_bytes: size,
        upload_operation_id: op_id,
        pending_object_keys: [object_key],
        processing_generation: 1
      }

      file =
        case StoredFile
             |> Ash.Changeset.for_create(:create, Map.delete(attrs, :id), actor: actor)
             |> Ash.Changeset.force_change_attribute(:id, file_id)
             |> internal_create() do
          {:ok, f} -> f
          _ -> Repo.rollback(:create_failed)
        end

      # Schedule recovery atomically before any I/O.
      case enqueue_cleanup_tx(file.id, 1, "reconcile_stale", schedule_in: @stale_pending_seconds) do
        {:ok, _} -> {file, conn, candidate}
        _ -> Repo.rollback(:enqueue_failed)
      end
    end)
    |> case do
      {:ok, {file, conn, _candidate}} -> {:ok, file, conn}
      {:error, :quota_exceeded} -> {:error, :quota_exceeded}
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp perform_upload_io(file, conn, path, size) do
    # Hold file lock across remote/local write and DB finalize to prevent races.
    with_lock(file.id, fn -> do_upload_io_locked(file, conn, path, size) end)
  end

  defp do_upload_io_locked(file, conn, path, size) do
    fresh = Repo.get(StoredFile, file.id)

    if is_nil(fresh) or fresh.status != "pending" or fresh.delete_requested_at,
      do: throw(:stale_upload)

    case put_object(conn, file.object_key, path, size) do
      :ok ->
        finalize_after_write_locked(file)

      _ ->
        mark_upload_write_failed_locked(file.id)
        {:error, :unavailable}
    end
  end

  defp finalize_after_write_locked(file) do
    transaction(fn ->
      locked = Repo.get!(StoredFile, file.id) |> system_load(:application)

      cond do
        is_nil(locked) ->
          Repo.rollback(:missing)

        locked.status != "pending" ->
          Repo.rollback(:stale)

        not is_nil(locked.delete_requested_at) ->
          Repo.rollback(:deleting)

        true ->
          candidate = ImageProcessing.candidate?(locked.content_type, locked.filename)

          {pstate, perror} =
            case candidate do
              {:ok, _} -> {"queued", nil}
              {:skip, reason} -> {"skipped", to_string(reason)}
              :not_image -> {"not_applicable", nil}
            end

          if (locked.reserved_bytes || 0) != locked.size do
            Repo.rollback(:accounting_corrupt)
          end

          case Quota.adjust_in(Repo, locked.user_id, locked.size, -locked.reserved_bytes) do
            :ok -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end

          {:ok, updated} =
            locked
            |> Ash.Changeset.for_update(
              :internal_update,
              %{
                status: "ready",
                processing_state: pstate,
                processing_error: perror,
                ready_at: DateTime.utc_now(),
                reserved_bytes: 0,
                last_error: nil
              },
              authorize?: false
            )
            |> internal_update()

          if pstate == "queued" do
            case enqueue_image_processing_tx(updated.id, updated.processing_generation) do
              {:ok, _} -> :ok
              _ -> Repo.rollback(:enqueue_failed)
            end
          end

          updated
      end
    end)
    |> case do
      {:ok, updated} ->
        {:ok, Ash.load!(updated, [:variants], authorize?: false)}

      {:error, _} ->
        _ = enqueue_cleanup(file.id, file.processing_generation, "cleanup_failed_upload")
        {:error, :unavailable}
    end
  end

  defp mark_upload_write_failed_locked(file_id) do
    transaction(fn ->
      locked = Repo.get(StoredFile, file_id) |> system_load(:application)

      if (locked && locked.status == "pending") and is_nil(locked.delete_requested_at) do
        # write may have partially happened; do NOT release reservation here.
        {:ok, _} =
          locked
          |> Ash.Changeset.for_update(
            :internal_update,
            %{
              status: "failed",
              processing_state: "failed",
              processing_error: "upload_write_failed",
              last_error: "upload_write_failed"
            },
            authorize?: false
          )
          |> internal_update()

        _ =
          enqueue_cleanup_tx(file_id, locked.processing_generation || 1, "cleanup_failed_upload")
      end
    end)

    :ok
  rescue
    _ ->
      _ = enqueue_cleanup(file_id, 1, "cleanup_failed_upload")
      :ok
  end

  # ---- download ----
  def download(actor, id) do
    with {:ok, %StoredFile{} = file} <- Ash.get(StoredFile, id, actor: actor, load: [:variants]),
         true <- file.status == "ready" do
      conn = load_connection(file.connection_id)
      fetch_download_object(conn, file.object_key, file.filename, file.size, file.content_type)
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def download_variant(actor, id, variant_name)
      when variant_name in ["thumbnail", "display_webp", "display_jpeg"] do
    with {:ok, %StoredFile{} = file} <- Ash.get(StoredFile, id, actor: actor, load: [:variants]),
         true <- file.status == "ready",
         %StoredFileVariant{} = v <-
           Enum.find(file.variants || [], &(&1.name == variant_name and &1.status == "ready")) do
      conn = load_connection(file.connection_id)
      ct = if variant_name == "thumbnail", do: "image/webp", else: v.content_type
      fetch_download_object(conn, v.object_key, file.filename, v.size, ct)
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def download_variant(_, _, _), do: {:error, :unavailable}

  defp fetch_download_object(nil, key, filename, _size, content_type) do
    with {:ok, path} <- Local.path(key),
         do:
           {:ok,
            %{
              path: path,
              filename: filename,
              temporary?: false,
              content_type: content_type || "application/octet-stream"
            }}
  end

  defp fetch_download_object(conn, key, filename, size, content_type) do
    path = Path.join(System.tmp_dir!(), "serve-download-" <> Ecto.UUID.generate())

    if S3.download(conn, key, path, size) == :ok do
      {:ok,
       %{
         path: path,
         filename: filename,
         temporary?: true,
         content_type: content_type || "application/octet-stream"
       }}
    else
      File.rm(path)
      {:error, :unavailable}
    end
  end

  # ---- delete ----
  def delete(actor, id) do
    with {:ok, %StoredFile{} = file} <- Ash.get(StoredFile, id, actor: actor, load: [:variants]) do
      with :ok <- request_delete(file), do: cleanup_delete(file.id)
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp request_delete(file) do
    with_lock(file.id, fn ->
      transaction(fn ->
        locked = Repo.get(StoredFile, file.id)

        cond do
          is_nil(locked) ->
            Repo.rollback(:not_found)

          not is_nil(locked.delete_requested_at) ->
            {:ok, locked}

          locked.status not in [
            "ready",
            "failed",
            "pending",
            "processing",
            "processing_failed",
            "deleting"
          ] ->
            Repo.rollback(:unavailable)

          true ->
            {:ok, updated} =
              locked
              |> Ash.Changeset.for_update(
                :internal_update,
                %{delete_requested_at: DateTime.utc_now()},
                authorize?: false
              )
              |> internal_update()

            case enqueue_cleanup_tx(locked.id, locked.processing_generation || 0, "delete_file") do
              {:ok, _} -> {:ok, updated}
              _ -> Repo.rollback(:enqueue_failed)
            end
        end
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, :not_found} -> {:error, :not_found}
        _ -> {:error, :unavailable}
      end
    end)
  end

  # ---- workers / cleanup ----
  def cleanup_delete(file_id, generation \\ nil) do
    with_lock(file_id, fn ->
      case load_system_file(file_id) do
        {:ok, file} ->
          cond do
            not is_nil(generation) and file.processing_generation != generation -> :ok
            is_nil(file.delete_requested_at) -> :ok
            true -> do_cleanup_delete(file)
          end

        _ ->
          :ok
      end
    end)
  end

  defp do_cleanup_delete(file) do
    conn = load_connection(file.connection_id)
    keys = tracked_object_keys(file)

    case delete_objects(conn, keys) do
      :ok ->
        transaction(fn ->
          locked = Repo.get!(StoredFile, file.id) |> system_load([:variants, :application])
          if is_nil(locked) or is_nil(locked.delete_requested_at), do: Repo.rollback(:done)

          # release used/reserved accounting atomically before destroying metadata
          {used_delta, reserved_delta} = accounting_release_deltas(locked)

          if used_delta != 0 or reserved_delta != 0 do
            case Quota.adjust(locked.user_id, used_delta, reserved_delta) do
              {:ok, _} -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
          end

          destroy_variants_rows!(locked.variants || [])

          case internal_destroy(locked) do
            :ok -> :ok
            _ -> Repo.rollback(:destroy_failed)
          end
        end)
        |> case do
          {:ok, _} ->
            :ok

          {:error, :done} ->
            :ok

          {:error, reason} ->
            bump_delete_attempt(file, reason)
            {:error, reason}
        end

      {:error, reason} ->
        bump_delete_attempt(file, reason)
        {:error, reason}
    end
  end

  def cleanup_failed_upload(file_id, generation \\ nil) do
    with_lock(file_id, fn ->
      case load_system_file(file_id) do
        {:ok, file} ->
          cond do
            not is_nil(generation) and file.processing_generation != generation -> :ok
            file.status not in ["failed", "pending"] -> :ok
            not is_nil(file.delete_requested_at) -> :ok
            true -> do_cleanup_failed(file)
          end

        _ ->
          :ok
      end
    end)
  end

  defp do_cleanup_failed(file) do
    conn = load_connection(file.connection_id)
    keys = tracked_object_keys(file)

    case delete_objects(conn, keys) do
      :ok ->
        transaction(fn ->
          locked = Repo.get!(StoredFile, file.id) |> system_load([:variants, :application])

          if is_nil(locked) or locked.status not in ["failed", "pending"],
            do: Repo.rollback(:done)

          # release reservation (and any partial used if somehow set) only after confirmed object removal
          reserved = locked.reserved_bytes || 0
          used_delta = if locked.status == "ready", do: -(locked.size || 0), else: 0
          reserved_delta = -reserved

          if used_delta != 0 or reserved_delta != 0 do
            case Quota.adjust(locked.user_id, used_delta, reserved_delta) do
              {:ok, _} -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
          end

          destroy_variants_rows!(locked.variants || [])

          case internal_destroy(locked) do
            :ok -> :ok
            _ -> Repo.rollback(:destroy_failed)
          end
        end)
        |> case do
          {:ok, _} ->
            :ok

          {:error, :done} ->
            :ok

          {:error, reason} ->
            bump_delete_attempt(file, reason)
            {:error, reason}
        end

      {:error, reason} ->
        bump_delete_attempt(file, reason)
        {:error, reason}
    end
  end

  def reconcile_stale_upload(file_id) do
    with_lock(file_id, fn ->
      case load_system_file(file_id) do
        {:ok, file} ->
          cond do
            file.status != "pending" -> :ok
            not is_nil(file.delete_requested_at) -> :ok
            not older_than?(file.created_at, @stale_pending_seconds) -> :ok
            true -> do_cleanup_failed(%{file | status: "failed"})
          end

        _ ->
          :ok
      end
    end)
  end

  # ---- image processing ----
  def process_image(file_or_id) do
    id =
      case file_or_id do
        %StoredFile{} = f -> f.id
        other -> other
      end

    with_lock(id, fn ->
      case load_system_file(id) do
        {:ok, file} ->
          cond do
            file.status != "ready" -> :ok
            file.processing_state not in ["queued", "processing"] -> :ok
            not is_nil(file.delete_requested_at) -> :ok
            true -> do_process_image(file)
          end

        _ ->
          :ok
      end
    end)
  end

  defp do_process_image(%{size: size} = file) when size > 50 * 1024 * 1024,
    do: mark_skipped(file, "image_too_large", nil)

  defp do_process_image(file) do
    case fetch_source_to_temp(file) do
      {:ok, path, tmp} ->
        try do
          case ImageProcessing.validate_magic(path, file.content_type) do
            {:ok, info} ->
              case generate_and_store_variants(file, path, info) do
                :ok -> mark_processed(file, info)
                {:skip, reason} -> mark_skipped(file, reason, info)
                {:error, reason} -> mark_processing_failed(file, reason)
              end

            {:skip, reason} ->
              mark_skipped(file, reason, nil)

            {:error, _} ->
              mark_processing_failed(file, "invalid_image")
          end
        after
          if tmp, do: File.rm(path)
        end

      _ ->
        mark_processing_failed(file, "source_unavailable")
    end
  end

  def retry_processing(actor, file_id) do
    with {:ok, file} <- Ash.get(StoredFile, file_id, actor: actor, load: [:variants]),
         true <- file.status == "ready",
         true <- file.processing_state in ["failed", "skipped"] do
      with_lock(file.id, fn ->
        transaction(fn ->
          locked = Repo.get(StoredFile, file.id)

          if is_nil(locked) or locked.status != "ready" or
               locked.processing_state not in ["failed", "skipped"] do
            Repo.rollback(:unavailable)
          end

          gen = (locked.processing_generation || 0) + 1

          {:ok, updated} =
            locked
            |> Ash.Changeset.for_update(
              :internal_update,
              %{
                processing_state: "queued",
                processing_error: nil,
                processing_generation: gen,
                last_error: nil
              },
              authorize?: false
            )
            |> internal_update()

          case enqueue_image_processing_tx(updated.id, gen) do
            {:ok, _} -> updated
            _ -> Repo.rollback(:enqueue_failed)
          end
        end)
      end)
      |> case do
        {:ok, updated} -> {:ok, updated}
        _ -> {:error, :unavailable}
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  # ---- internals ----
  def load_system_file(file_id) do
    id = file_id

    case id && Repo.get(StoredFile, id) |> maybe_preload() do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp system_load(nil, _), do: nil
  defp system_load(file, fields), do: Ash.load!(file, fields, authorize?: false)

  defp maybe_preload(nil), do: nil
  defp maybe_preload(file), do: system_load(file, [:variants, :application, :connection])

  defp with_lock(file_id, fun) do
    case FileLock.with_lock(to_string(file_id), 30_000, fun) do
      {:error, :lock_timeout} -> {:error, :lock_timeout}
      other -> other
    end
  end

  defp load_connection(nil), do: nil

  defp load_connection(id) do
    case dump(id) do
      nil -> nil
      _bin -> Repo.get!(Connection, id)
    end
  end

  defp tracked_object_keys(file) do
    variant_keys = Enum.map(file.variants || [], & &1.object_key)
    pending = file.pending_object_keys || []
    [file.object_key | variant_keys ++ pending] |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp delete_objects(_conn, []), do: :ok

  defp delete_objects(conn, [k | rest]) do
    case remove_object(conn, k) do
      :ok -> delete_objects(conn, rest)
      err -> err
    end
  end

  defp remove_object(nil, key), do: Local.delete(key)
  defp remove_object(conn, key), do: S3.request(conn, :delete, key)

  defp accounting_release_deltas(file) do
    # called under lock/tx with locked fresh file
    variant_bytes =
      Enum.reduce(file.variants || [], 0, fn v, acc ->
        acc + if(v.status == "ready", do: v.size, else: 0)
      end)

    original_used = if file.ready_at, do: file.size, else: 0
    # if failed/pending and never finalized, original not in used
    original_used =
      if file.status in ["failed", "pending"] and file.ready_at == nil, do: 0, else: original_used

    used_delta = -(original_used + variant_bytes)
    reserved_delta = -(file.reserved_bytes || 0)
    {used_delta, reserved_delta}
  end

  defp destroy_variants_rows!(variants) do
    Enum.each(variants, fn v ->
      case internal_destroy(v) do
        :ok -> :ok
        other -> raise "variant_destroy_failed: #{inspect(other)}"
      end
    end)
  end

  defp bump_delete_attempt(file, reason) do
    try do
      file
      |> Ash.Changeset.for_update(
        :internal_update,
        %{delete_attempts: (file.delete_attempts || 0) + 1, last_error: inspect(reason)},
        authorize?: false
      )
      |> internal_update()
    rescue
      _ -> :ok
    end
  end

  defp put_object(nil, key, path, _size), do: Local.put(key, path)
  defp put_object(conn, key, path, size), do: S3.put(conn, key, path, size)

  def enqueue_cleanup(file_id, generation, action) do
    %{file_id: to_string(file_id), generation: generation || 0, action: action}
    |> CleanupWorker.new()
    |> Oban.insert()
  end

  defp enqueue_cleanup_tx(file_id, generation, action, opts \\ []) do
    %{file_id: to_string(file_id), generation: generation || 0, action: action}
    |> CleanupWorker.new(opts)
    |> Oban.insert()
  end

  defp enqueue_image_processing_tx(file_id, generation) do
    %{file_id: to_string(file_id), generation: generation || 0}
    |> ImageProcessingWorker.new()
    |> Oban.insert()
  end

  defp fetch_source_to_temp(file) do
    conn = load_connection(file.connection_id)

    case conn do
      nil ->
        case Local.path(file.object_key) do
          {:ok, path} -> {:ok, path, false}
          _ -> {:error, :unavailable}
        end

      c ->
        path = Path.join(System.tmp_dir!(), "serve-src-" <> Ecto.UUID.generate())

        if S3.download(c, file.object_key, path, file.size) == :ok,
          do: {:ok, path, true},
          else:
            (
              File.rm(path)
              {:error, :unavailable}
            )
    end
  end

  defp generate_and_store_variants(file, source_path, info) do
    dir = Path.join(System.tmp_dir!(), "serve-vars-" <> Ecto.UUID.generate())
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    try do
      fresh = Repo.get!(StoredFile, file.id) |> system_load(:variants)
      :ok = rollback_unready_variants(fresh)
      ready_names = for v <- fresh.variants, v.status == "ready", do: v.name
      variants_to_make = Enum.reject(variant_specs(info.format), &(&1.name in ready_names))
      conn = load_connection(file.connection_id)

      Enum.reduce_while(variants_to_make, {:ok, []}, fn spec, {:ok, acc} ->
        case create_variant(source_path, dir, spec.name, spec.max_dim, spec.format) do
          {:ok, v} ->
            case persist_and_account_variant(file, conn, v) do
              :ok -> {:cont, {:ok, [v | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:skip, reason} ->
            {:halt, {:skip, reason}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, _} ->
          :ok

        {:skip, reason} ->
          {:skip, reason}

        {:error, reason} ->
          {:error, reason}
      end
    after
      File.rm_rf(dir)
    end
  rescue
    _ -> {:error, :variant_failed}
  end

  defp variant_specs(:jpeg),
    do: [
      %{name: "thumbnail", max_dim: 320, format: :webp},
      %{name: "display_webp", max_dim: 1280, format: :webp},
      %{name: "display_jpeg", max_dim: 1280, format: :jpeg}
    ]

  defp variant_specs(:png),
    do: [
      %{name: "thumbnail", max_dim: 320, format: :webp},
      %{name: "display_webp", max_dim: 1280, format: :webp},
      %{name: "display_jpeg", max_dim: 1280, format: :jpeg}
    ]

  defp variant_specs(:webp),
    do: [
      %{name: "thumbnail", max_dim: 320, format: :webp},
      %{name: "display_webp", max_dim: 1280, format: :webp},
      %{name: "display_jpeg", max_dim: 1280, format: :jpeg}
    ]

  defp variant_specs(_), do: []

  defp create_variant(source_path, dir, name, max_dim, format) do
    timeout = image_processing_timeout_ms()

    {out, status, timed_out} =
      run_variant_port(source_path, dir, name, max_dim, format, image_max_output_bytes(), timeout)

    cond do
      timed_out ->
        {:error, :timeout}

      status == 0 ->
        case Jason.decode(String.trim(to_string(out))) do
          {:ok, %{"ok" => true} = d} ->
            {:ok,
             %{
               name: name,
               path: d["path"],
               object_key_suffix: d["name"],
               content_type: d["content_type"],
               size: d["size"],
               width: d["width"],
               height: d["height"]
             }}

          _ ->
            if String.contains?(to_string(out), "output_too_large"),
              do: {:skip, "output_too_large"},
              else: {:error, :variant_failed}
        end

      true ->
        if String.contains?(to_string(out), "output_too_large"),
          do: {:skip, "output_too_large"},
          else: {:error, :variant_failed}
    end
  rescue
    _ -> {:error, :variant_failed}
  end

  defp run_variant_port(source, dir, name, max_dim, format, max_output_bytes, timeout_ms) do
    script = variant_runner_path!()
    exe = System.find_executable("elixir") || "elixir"
    code_paths = :code.get_path() |> Enum.map(&:erlang.list_to_binary/1)

    args =
      Enum.flat_map(code_paths, &["-pa", &1]) ++
        [
          "-r",
          script,
          "-e",
          "App.Storage.VariantRunner.main()",
          "--",
          source,
          dir,
          name,
          Integer.to_string(max_dim),
          Atom.to_string(format),
          Integer.to_string(max_output_bytes)
        ]

    env = [
      {~c"VIPS_BLOCK_UNTRUSTED", ~c"1"},
      {~c"VIPS_CONCURRENCY", ~c"1"},
      {~c"VIPS_MAX_CACHE_MEM", ~c"0"},
      {~c"VIPS_MAX_CACHE_SIZE", ~c"0"}
    ]

    supervisor = Path.join(:code.priv_dir(:app), "native_supervisor.py") |> to_string()

    python =
      System.find_executable("python3") || raise "python3 is required for isolated image workers"

    args = [supervisor, Integer.to_string(timeout_ms), exe | args]
    env = [{~c"ELIXIR_ERL_OPTIONS", ~c"+S 2:2 +SDcpu 1 +SDio 1"} | env]

    port =
      Port.open({:spawn_executable, String.to_charlist(python)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, Enum.map(args, &String.to_charlist/1)},
        {:env, env}
      ])

    os_pid =
      case Port.info(port, :os_pid) do
        {_, p} -> p
        _ -> nil
      end

    deadline = System.monotonic_time(:millisecond) + timeout_ms + 2_000
    collect_port(port, os_pid, deadline, [])
  end

  defp collect_port(port, os_pid, deadline, acc) do
    remain = Kernel.max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        if IO.iodata_length(acc) + byte_size(data) <= 65_536 do
          collect_port(port, os_pid, deadline, [acc, data])
        else
          safe_close_port(port)
          {"", 1, false}
        end

      {^port, {:exit_status, status}} ->
        {IO.iodata_to_binary(acc), status, false}
    after
      remain ->
        safe_close_port(port)
        {IO.iodata_to_binary(acc), 137, true}
    end
  end

  defp safe_close_port(port) do
    try do
      Port.close(port)
    rescue
      _ -> :ok
    end
  end

  defp variant_runner_path! do
    path = Path.join(:code.priv_dir(:app), "variant_runner.exs") |> to_string()
    if File.exists?(path), do: path, else: raise("variant runner missing")
  end

  defp persist_and_account_variant(file, conn, variant) do
    key = file.user_id <> "/" <> file.application_id <> "/" <> Ecto.UUID.generate()

    transaction(fn ->
      locked = Repo.get(StoredFile, file.id) |> system_load([:application, :variants])

      cond do
        is_nil(locked) ->
          Repo.rollback(:missing)

        not is_nil(locked.delete_requested_at) ->
          Repo.rollback(:deleting)

        locked.processing_state != "queued" and locked.processing_state != "processing" ->
          Repo.rollback(:stale)

        true ->
          # reserve/account variant bytes and persist variant record+pending key before object put
          case Quota.reserve_in(Repo, locked.user_id, variant.size) do
            :ok -> :ok
            {:error, :quota_exceeded} -> Repo.rollback(:quota_exceeded)
            {:error, reason} -> Repo.rollback(reason)
          end

          pending = Enum.uniq((locked.pending_object_keys || []) ++ [key])

          {:ok, _} =
            locked
            |> Ash.Changeset.for_update(
              :internal_update,
              %{
                pending_object_keys: pending,
                processing_state: "processing",
                reserved_bytes: locked.reserved_bytes + variant.size
              },
              authorize?: false
            )
            |> internal_update()

          attrs = %{
            file_id: locked.id,
            name: variant.name,
            object_key: key,
            content_type: variant.content_type,
            size: variant.size,
            width: variant.width,
            height: variant.height,
            status: "pending"
          }

          case Repo.get_by(StoredFileVariant, file_id: locked.id, name: variant.name) do
            nil ->
              internal_create_variant!(attrs)

            existing ->
              existing
              |> Ash.Changeset.for_update(:update, attrs, authorize?: false)
              |> internal_update!()
          end

          :ok
      end
    end)
    |> case do
      {:ok, _} ->
        case put_object(conn, key, variant.path, variant.size) do
          :ok ->
            mark_variant_ready(file.id, variant.name, key)

          _ ->
            {:error, :variant_store_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_variant_ready(file_id, name, key) do
    transaction(fn ->
      locked = Repo.get(StoredFile, file_id)
      if is_nil(locked), do: Repo.rollback(:missing)
      v = Repo.get_by(StoredFileVariant, file_id: file_id, name: name)
      if is_nil(v), do: Repo.rollback(:missing)
      :ok = Quota.adjust_in(Repo, locked.user_id, v.size, -v.size)

      v
      |> Ash.Changeset.for_update(:update, %{status: "ready"}, authorize?: false)
      |> internal_update!()

      pending = Enum.reject(locked.pending_object_keys || [], &(&1 == key))

      {:ok, _} =
        locked
        |> Ash.Changeset.for_update(
          :internal_update,
          %{pending_object_keys: pending, reserved_bytes: locked.reserved_bytes - v.size},
          authorize?: false
        )
        |> internal_update()

      :ok
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_processed(file, info), do: update_processing(file, "ready", nil, info)

  defp mark_skipped(file, reason, info),
    do: finish_processing_failure(file, "skipped", reason, info)

  defp mark_processing_failed(file, reason),
    do: finish_processing_failure(file, "failed", reason, nil)

  defp finish_processing_failure(file, state, reason, info) do
    with :ok <- rollback_unready_variants(file),
         :ok <- update_processing(file, state, to_string(reason), info) do
      :ok
    end
  end

  defp update_processing(file, state, reason, info) do
    fresh = Repo.get!(StoredFile, file.id)
    attrs = %{processing_state: state, processing_error: reason}

    attrs =
      if info,
        do:
          Map.merge(attrs, %{
            width: info.width,
            height: info.height,
            pixel_count: info.pixels,
            source_format: to_string(info.format)
          }),
        else: attrs

    case fresh |> Ash.Changeset.for_update(:internal_update, attrs) |> internal_update() do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :update_failed}
    end
  end

  defp rollback_unready_variants(file) do
    fresh = Repo.get!(StoredFile, file.id) |> system_load(:variants)
    unready = Enum.filter(fresh.variants, &(&1.status != "ready"))
    conn = load_connection(fresh.connection_id)

    with :ok <- delete_objects(conn, Enum.map(unready, & &1.object_key)) do
      transaction(fn ->
        bytes = Enum.sum(Enum.map(unready, & &1.size))
        :ok = Quota.adjust_in(Repo, fresh.user_id, 0, -bytes)
        destroy_variants_rows!(unready)
        keys = Enum.map(unready, & &1.object_key)

        fresh
        |> Ash.Changeset.for_update(:internal_update, %{
          reserved_bytes: fresh.reserved_bytes - bytes,
          pending_object_keys: fresh.pending_object_keys -- keys
        })
        |> internal_update!()
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp older_than?(dt, seconds) when is_struct(dt, DateTime),
    do: DateTime.diff(DateTime.utc_now(), dt, :second) > seconds

  defp older_than?(_, _), do: false

  # Ash notifications must leave the enclosing SQL transaction before delivery.
  defp transaction(fun) do
    if Process.get({__MODULE__, :notifications}) do
      Repo.transaction(fun)
    else
      Process.put({__MODULE__, :notifications}, [])

      try do
        result = Repo.transaction(fun)

        if match?({:ok, _}, result),
          do: Ash.Notifier.notify(Process.get({__MODULE__, :notifications}) |> Enum.reverse())

        result
      after
        Process.delete({__MODULE__, :notifications})
      end
    end
  end

  defp notifications(notes) do
    case Process.get({__MODULE__, :notifications}) do
      nil -> Ash.Notifier.notify(notes)
      old -> Process.put({__MODULE__, :notifications}, Enum.reverse(notes) ++ old)
    end
  end

  defp internal_update(changeset) do
    case Ash.update(changeset, authorize?: false, return_notifications?: true) do
      {:ok, record, notes} ->
        notifications(notes)
        {:ok, record}

      error ->
        error
    end
  end

  defp internal_update!(changeset) do
    case internal_update(changeset) do
      {:ok, record} -> record
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  defp internal_create(changeset) do
    case Ash.create(changeset, authorize?: false, return_notifications?: true) do
      {:ok, record, notes} ->
        notifications(notes)
        {:ok, record}

      error ->
        error
    end
  end

  defp internal_create_variant!(attrs) do
    changeset = Ash.Changeset.for_create(StoredFileVariant, :create, attrs)

    case internal_create(changeset) do
      {:ok, record} -> record
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  defp internal_destroy(record) do
    case Ash.destroy(record, authorize?: false, return_notifications?: true) do
      {:ok, notes} ->
        notifications(notes)
        :ok

      error ->
        error
    end
  end

  # ---- misc helpers ----
  defp validate_optional_tags(nil), do: :ok

  defp validate_optional_tags(tags) when is_list(tags) do
    case validate_tags(tags) do
      {:ok, _} -> :ok
      {:error, message} -> {:error, {:invalid_tags, message}}
    end
  end

  defp validate_optional_tags(_), do: {:error, {:invalid_tags, "Tags must be a list of strings."}}

  defp validated_tags(nil), do: []
  defp validated_tags(tags), do: elem(validate_tags(tags), 1)
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

  defp dump(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, bin} -> bin
      :error -> nil
    end
  end

  defp dump(id), do: id
end
