defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view
  require Ash.Query
  alias App.Applications
  alias App.Applications.{Application, ApplicationKey}
  on_mount {AppWeb.LiveUserAuth, :live_user_required}

  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_file_processing, 3_000)

    {:ok,
     assign(socket,
       plaintext_key: nil,
       selected_app: nil,
       revoking_key: nil,
       deleting_file: nil,
       editing_file: nil,
       file_tags_input: "",
       files: [],
       storage_usage: nil,
       file_search: "",
       file_sort: "newest",
       file_page: 1,
       file_tags: [],
       file_limit: App.Storage.files_per_page(),
       file_total: 0,
       file_pages: 1,
       file_prev: nil,
       file_next: nil,
       connections: [],
       file_counts: %{},
       show_storage: false,
       storage_error: nil,
       testing_storage: false,
       environment_s3?: App.Storage.environment_available?(),
       keys: [],
       applications: [],
       show_create: false,
       save_error: nil,
       tab: "settings",
       key_counts: %{}
     )
     |> allow_upload(:documents,
       accept: :any,
       max_entries: 5,
       max_file_size: App.Storage.max_file_size()
     )}
  end

  def handle_params(params, _, socket) do
    tab = if params["tab"] in ["settings", "keys", "files"], do: params["tab"], else: "settings"

    socket =
      socket
      |> assign(
        selected_app: nil,
        plaintext_key: nil,
        tab: tab,
        file_search: file_param(params["search"], 200),
        file_sort:
          if(params["sort"] in App.Storage.file_sorts(), do: params["sort"], else: "newest"),
        file_page: page_param(params["page"]),
        file_tags: file_tags_param(params)
      )
      |> load_apps()

    if socket.assigns.live_action == :application do
      case Ash.get(Application, params["id"], actor: socket.assigns.current_user) do
        {:ok, %Application{} = app} ->
          {:noreply,
           socket
           |> assign(selected_app: app, show_storage: false, storage_error: nil)
           |> load_keys()
           |> load_storage(sync_url: true)}

        _ ->
          {:noreply,
           socket
           |> put_flash(:error, "Application not found")
           |> push_navigate(to: ~p"/dashboard/applications")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_file_processing, socket) do
    Process.send_after(self(), :refresh_file_processing, 3_000)

    if socket.assigns.selected_app && socket.assigns.tab == "files" do
      {:noreply, load_storage(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry_image", %{"id" => id}, socket) do
    case App.Storage.retry_processing(socket.assigns.current_user, id) do
      {:ok, _} -> {:noreply, load_storage(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Unable to retry this image.")}
    end
  end

  def handle_event("new_application", _, socket),
    do: {:noreply, assign(socket, show_create: true, save_error: nil)}

  def handle_event("close_dialog", _, socket),
    do:
      {:noreply,
       assign(socket,
         show_create: false,
         revoking_key: nil,
         deleting_file: nil,
         editing_file: nil,
         file_tags_input: "",
         show_storage: false
       )}

  def handle_event("update_application", %{"application" => attrs}, socket) do
    perform(socket, fn ->
      app = socket.assigns.selected_app

      connection_id =
        case attrs["storage_connection_id"] do
          "environment" ->
            case App.Storage.environment_connection(socket.assigns.current_user, app.id) do
              {:ok, connection} -> connection.id
              _ -> raise Ash.Error.Invalid, message: "Environment S3 is not configured"
            end

          "local" ->
            nil

          nil ->
            app.storage_connection_id

          id ->
            id
        end

      app =
        Ash.update!(app, %{name: attrs["name"], storage_connection_id: connection_id},
          actor: socket.assigns.current_user
        )

      socket
      |> assign(selected_app: app)
      |> put_flash(:info, "Application updated")
      |> load_apps()
      |> load_storage()
    end)
  end

  def handle_event("new_storage", _, socket),
    do: {:noreply, assign(socket, show_storage: true, storage_error: nil)}

  def handle_event("create_storage", %{"storage" => attrs}, socket) do
    case App.Storage.create_connection(
           socket.assigns.current_user,
           socket.assigns.selected_app.id,
           attrs
         ) do
      {:ok, connection} ->
        perform(socket, fn ->
          app =
            Ash.update!(socket.assigns.selected_app, %{storage_connection_id: connection.id},
              actor: socket.assigns.current_user
            )

          socket
          |> assign(selected_app: app, show_storage: false)
          |> put_flash(:info, "S3 connection saved. Test the connection before uploading.")
          |> load_storage()
        end)

      {:error, message} ->
        {:noreply,
         assign(
           socket,
           :storage_error,
           if(is_binary(message),
             do: message,
             else: "Unable to save the connection. Check the fields."
           )
         )}
    end
  end

  def handle_event("test_storage", _, socket) do
    actor = socket.assigns.current_user
    app = socket.assigns.selected_app

    {:noreply,
     socket
     |> assign(testing_storage: true)
     |> start_async(:test_storage, fn ->
       App.Storage.test_connection(actor, app.id, app.storage_connection_id)
     end)}
  end

  def handle_event("validate_files", _, socket), do: {:noreply, socket}

  def handle_event("filter_files", params, socket) do
    search = file_param(params["search"], 200)
    sort = if params["sort"] in App.Storage.file_sorts(), do: params["sort"], else: "newest"

    case parse_tags_input(params["tags"]) do
      {:ok, tags} ->
        {:noreply,
         push_patch(
           socket,
           to: files_path(socket.assigns.selected_app.id, search, sort, tags, 1)
         )}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :documents, ref)}

  def handle_event("upload_files", _, socket) do
    results =
      consume_uploaded_entries(socket, :documents, fn %{path: path}, entry ->
        {:ok,
         App.Storage.upload(
           socket.assigns.current_user,
           socket.assigns.selected_app.id,
           path,
           entry.client_name,
           entry.client_type
         )}
      end)

    failed? = Enum.any?(results, fn result -> not match?({:ok, _}, result) end)

    socket =
      cond do
        Enum.any?(results, &(&1 == {:error, :quota_exceeded})) ->
          put_flash(
            socket,
            :error,
            "Account storage quota reached. Delete files or contact the administrator for more space."
          )

        failed? ->
          put_flash(
            socket,
            :error,
            "Some files could not be stored. Check the connection and select those files again."
          )

        true ->
          put_flash(socket, :info, "Files uploaded")
      end

    {:noreply, socket |> load_storage(sync_url: true) |> load_apps()}
  end

  def handle_event("edit_file_tags", %{"id" => id}, socket) do
    case Ash.get(App.Storage.StoredFile, id, actor: socket.assigns.current_user) do
      {:ok, %App.Storage.StoredFile{application_id: app_id} = file}
      when app_id == socket.assigns.selected_app.id ->
        {:noreply,
         assign(socket,
           editing_file: file,
           file_tags_input: Enum.join(file.tags || [], "\n")
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "File unavailable")}
    end
  end

  def handle_event("save_file_tags", params, socket) do
    file = socket.assigns.editing_file

    case parse_tags_input(params["tags"]) do
      {:ok, tags} ->
        case App.Storage.update_tags(
               socket.assigns.current_user,
               socket.assigns.selected_app.id,
               file.id,
               tags
             ) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> assign(editing_file: nil, file_tags_input: "")
             |> put_flash(:info, "File tags updated")
             |> load_storage()}

          {:error, {:invalid_tags, message}} ->
            {:noreply, put_flash(socket, :error, message)}

          _ ->
            {:noreply, put_flash(socket, :error, "Unable to update file tags.")}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("delete_file", %{"id" => id}, socket) do
    case Ash.get(App.Storage.StoredFile, id, actor: socket.assigns.current_user) do
      {:ok, %App.Storage.StoredFile{application_id: app_id} = file}
      when app_id == socket.assigns.selected_app.id ->
        {:noreply, assign(socket, :deleting_file, file)}

      _ ->
        {:noreply, put_flash(socket, :error, "File unavailable")}
    end
  end

  def handle_event("confirm_delete_file", _, socket) do
    case App.Storage.delete(socket.assigns.current_user, socket.assigns.deleting_file.id) do
      :ok ->
        {:noreply,
         socket
         |> assign(deleting_file: nil)
         |> put_flash(:info, "File deleted")
         |> load_storage(sync_url: true)
         |> load_apps()}

      _ ->
        {:noreply,
         socket
         |> assign(deleting_file: nil)
         |> put_flash(:error, "Unable to delete file. Check the storage connection.")}
    end
  end

  def handle_event("create_application", %{"application" => attrs}, socket) do
    perform(socket, fn ->
      Ash.create!(Application, Map.take(attrs, ["name", "slug"]),
        actor: socket.assigns.current_user
      )

      socket
      |> assign(show_create: false)
      |> put_flash(:info, "Application created")
      |> load_apps()
    end)
  end

  def handle_event("issue_key", %{"key" => attrs}, socket) do
    perform(socket, fn ->
      scopes =
        case attrs["access"] do
          "read" -> ["files:read"]
          "write" -> ["files:read", "files:write"]
          "manage" -> ["files:read", "files:write", "files:delete"]
          _ -> ["files:read"]
        end

      {_key, raw} =
        Applications.issue_key!(
          socket.assigns.current_user,
          socket.assigns.selected_app.id,
          attrs["name"],
          scopes
        )

      socket
      |> assign(:plaintext_key, raw)
      |> put_flash(:info, "Key created. Copy it now; it won't be shown again.")
      |> load_keys()
    end)
  end

  def handle_event("revoke_key", %{"id" => id}, socket) do
    perform(socket, fn ->
      key = Ash.get!(ApplicationKey, id, actor: socket.assigns.current_user)
      assign(socket, :revoking_key, key)
    end)
  end

  def handle_event("confirm_revoke_key", _, socket) do
    perform(socket, fn ->
      Ash.update!(socket.assigns.revoking_key, %{},
        action: :revoke,
        actor: socket.assigns.current_user
      )

      socket
      |> assign(plaintext_key: nil, revoking_key: nil)
      |> put_flash(:info, "Key revoked")
      |> load_keys()
    end)
  end

  def handle_event("update_profile", %{"profile" => attrs}, socket) do
    perform(socket, fn ->
      user =
        Ash.update!(socket.assigns.current_user, Map.take(attrs, ["name"]),
          action: :update_profile,
          actor: socket.assigns.current_user
        )

      socket |> assign(:current_user, user) |> put_flash(:info, "Profile updated")
    end)
  end

  def handle_async(:test_storage, {:ok, :ok}, socket),
    do:
      {:noreply,
       socket
       |> assign(testing_storage: false)
       |> put_flash(:info, "Storage connection is working")}

  def handle_async(:test_storage, _, socket),
    do:
      {:noreply,
       socket
       |> assign(testing_storage: false)
       |> put_flash(
         :error,
         "Storage test failed. Check endpoint, credentials, bucket and object permissions."
       )}

  defp load_apps(socket) do
    apps =
      Application
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: socket.assigns.current_user)

    counts =
      App.Applications.ApplicationKey
      |> Ash.read!(actor: socket.assigns.current_user)
      |> Enum.frequencies_by(& &1.application_id)

    socket
    |> assign(
      applications: apps,
      key_counts: counts,
      file_counts: App.Storage.counts(socket.assigns.current_user)
    )
    |> stream(:applications, apps, reset: true)
  end

  defp load_keys(socket) do
    id = socket.assigns.selected_app.id

    keys =
      ApplicationKey
      |> Ash.Query.filter(application_id == ^id)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: socket.assigns.current_user)

    socket |> assign(:keys, keys) |> stream(:keys, keys, reset: true)
  end

  defp load_storage(socket, opts \\ []) do
    actor = socket.assigns.current_user
    app_id = socket.assigns.selected_app.id

    case App.Storage.files_page(actor, app_id,
           search: socket.assigns.file_search,
           sort: socket.assigns.file_sort,
           page: socket.assigns.file_page,
           tags: socket.assigns.file_tags
         ) do
      %{files: _} = result ->
        clamped? = result.page != socket.assigns.file_page

        socket =
          socket
          |> assign(
            files: result.files,
            storage_usage: App.Storage.Quota.status_for_user(actor.id),
            file_total: result.total,
            file_page: result.page,
            file_pages: result.pages,
            file_limit: result.limit,
            file_search: result.search,
            file_sort: result.sort,
            file_tags: result.tags,
            file_prev:
              if(result.page > 1,
                do: files_path(app_id, result.search, result.sort, result.tags, result.page - 1)
              ),
            file_next:
              if(result.page < result.pages,
                do: files_path(app_id, result.search, result.sort, result.tags, result.page + 1)
              ),
            connections: App.Storage.connections(actor, app_id)
          )
          |> stream(:files, result.files, reset: true)

        if clamped? and Keyword.get(opts, :sync_url, false) and connected?(socket) do
          push_patch(socket,
            to: files_path(app_id, result.search, result.sort, result.tags, result.page)
          )
        else
          socket
        end

      {:error, _message} ->
        socket
        |> assign(file_tags: [], file_search: "", file_sort: "newest", file_page: 1)
        |> put_flash(:error, "Invalid file filters.")
        |> load_storage(Keyword.put(opts, :sync_url, true))
    end
  end

  defp perform(socket, fun) do
    {:noreply, fun.()}
  rescue
    _error in [Ash.Error.Invalid, Ash.Error.Forbidden, Ash.Error.Unknown] ->
      {:noreply,
       socket
       |> assign(:save_error, "Unable to save. Check your input and application permissions.")
       |> put_flash(:error, "Unable to save. Check your input and application permissions.")}
  end

  defp storage_options(connections, environment?) do
    [{"Local storage (this server)", "local"}] ++
      Enum.map(connections, &{&1.name, &1.id}) ++
      if(environment?, do: [{"S3 from server environment", "environment"}], else: [])
  end

  defp storage_label(_, nil), do: "Local storage"

  defp storage_label(connections, id) do
    case Enum.find(connections, &(&1.id == id)) do
      nil -> "S3 storage"
      connection -> connection.name
    end
  end

  defp format_bytes(size) when size < 1024, do: "#{size} B"
  defp format_bytes(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_bytes(size), do: "#{Float.round(size / (1024 * 1024), 1)} MB"

  defp file_param(value, max) when is_binary(value) do
    String.trim(value) |> String.slice(0, max)
  end

  defp file_param(_, _), do: ""

  defp page_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 -> Kernel.min(n, 100_000)
      _ -> 1
    end
  end

  defp page_param(value) when is_integer(value) and value >= 1, do: Kernel.min(value, 100_000)
  defp page_param(_), do: 1

  defp file_tags_param(%{"tags[]" => tags}) when is_list(tags),
    do: Enum.filter(tags, &is_binary/1)

  defp file_tags_param(%{"tags[]" => tag}) when is_binary(tag), do: [tag]
  defp file_tags_param(%{"tags" => tags}) when is_list(tags), do: Enum.filter(tags, &is_binary/1)
  defp file_tags_param(%{"tags" => tag}) when is_binary(tag), do: [tag]
  defp file_tags_param(_), do: []

  defp parse_tags_input(nil), do: {:ok, []}
  defp parse_tags_input(""), do: {:ok, []}

  defp parse_tags_input(value) when is_binary(value) do
    tags =
      value
      |> String.split(~r/\r?\n/, trim: false)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    App.Storage.validate_tags_filter(tags)
  end

  defp parse_tags_input(tags) when is_list(tags), do: App.Storage.validate_tags_filter(tags)
  defp parse_tags_input(_), do: {:error, "Tags must be one per line."}

  defp files_path(app_id, search, sort, tags, page) do
    params = []
    params = if sort != "newest", do: params ++ [{"sort", sort}], else: params
    params = if search != "", do: params ++ [{"search", search}], else: params
    params = params ++ [{"tab", "files"}]
    params = if page != 1, do: params ++ [{"page", to_string(page)}], else: params
    params = params ++ Enum.map(tags, &{"tags[]", &1})

    "/dashboard/applications/#{app_id}?#{URI.encode_query(params)}"
  end

  defp section(action),
    do:
      %{
        overview: "Overview",
        applications: "Applications",
        application: "Applications",
        profile: "Profile"
      }[action]
end
