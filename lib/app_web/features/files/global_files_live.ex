defmodule AppWeb.GlobalFilesLive do
  @moduledoc "Owner-scoped files across every application, with search, filters and mutations."
  use AppWeb, :live_view
  import AppWeb.FileComponents
  alias App.Applications.Application
  alias App.Storage
  alias App.Storage.StoredFile
  on_mount {AppWeb.LiveUserAuth, :live_user_required}

  def mount(_, _, socket) do
    if connected?(socket), do: App.DashboardNotifier.subscribe(socket.assigns.current_user.id)

    {:ok,
     assign(socket,
       refresh_pending: nil,
       applications: [],
       app_labels: %{},
       files: [],
       file_view: "list",
       file_search: "",
       file_sort: "newest",
       file_page: 1,
       file_tags: [],
       file_app: "",
       file_total: 0,
       file_pages: 1,
       file_prev: nil,
       file_next: nil,
       file_details: nil,
       deleting_file: nil,
       editing_file: nil,
       file_tags_input: ""
     )}
  end

  def handle_params(params, _, socket) do
    # Navigation params always win. Invalidate any debounced refresh token so its
    # scheduled message cannot later clobber the freshly applied navigation state.
    {:noreply,
     socket
     |> assign(
       refresh_pending: nil,
       file_view: if(params["view"] == "grid", do: "grid", else: "list"),
       file_search: file_param(params["search"], 200),
       file_sort: if(params["sort"] in Storage.file_sorts(), do: params["sort"], else: "newest"),
       file_page: page_param(params["page"]),
       file_tags: file_tags_param(params),
       file_app: app_param(params["app"])
     )
     |> load_applications()
     |> load_files()}
  end

  def handle_info(:dashboard_changed, socket) do
    if socket.assigns.refresh_pending do
      {:noreply, socket}
    else
      token = make_ref()
      Process.send_after(self(), {:refresh_files, token}, 25)
      {:noreply, assign(socket, refresh_pending: token)}
    end
  end

  def handle_info({:refresh_files, token}, socket) do
    if socket.assigns.refresh_pending == token do
      socket = assign(socket, refresh_pending: nil)

      case App.Accounts.active_user(socket.assigns.current_user) do
        nil ->
          {:noreply, redirect(socket, to: ~p"/sign-in")}

        user ->
          {:noreply,
           socket
           |> assign(current_user: user)
           |> load_applications()
           |> load_files()
           |> refresh_open_details()}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter_files", params, socket) do
    search = file_param(params["search"], 200)
    sort = if params["sort"] in Storage.file_sorts(), do: params["sort"], else: "newest"

    case parse_tags_input(params["tags"]) do
      {:ok, tags} ->
        {:noreply,
         push_patch(socket,
           to:
             files_path(
               socket.assigns.file_view,
               search,
               sort,
               app_param(params["app"]),
               1,
               tags
             )
         )}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("file_view", %{"view" => view}, socket) when view in ["grid", "list"] do
    a = socket.assigns

    {:noreply,
     push_patch(socket,
       to: files_path(view, a.file_search, a.file_sort, a.file_app, a.file_page, a.file_tags)
     )}
  end

  def handle_event("file_details", %{"id" => id}, socket) do
    case authorized_file(socket.assigns.current_user, id) do
      {:ok, file} -> {:noreply, assign(socket, file_details: file)}
      _ -> {:noreply, put_flash(socket, :error, "File unavailable")}
    end
  end

  def handle_event("delete_file", %{"id" => id}, socket) do
    case authorized_file(socket.assigns.current_user, id) do
      {:ok, file} -> {:noreply, assign(socket, deleting_file: file)}
      _ -> {:noreply, put_flash(socket, :error, "File unavailable")}
    end
  end

  def handle_event("confirm_delete_file", _, %{assigns: %{deleting_file: file}} = socket)
      when not is_nil(file) do
    case Storage.delete(socket.assigns.current_user, file.id) do
      :ok ->
        {:noreply,
         socket
         |> assign(deleting_file: nil)
         |> put_flash(:info, "File deleted")
         |> load_files()}

      _ ->
        {:noreply,
         socket
         |> assign(deleting_file: nil)
         |> put_flash(:error, "Unable to delete file. Check the storage connection.")}
    end
  end

  def handle_event("edit_file_tags", %{"id" => id}, socket) do
    case authorized_file(socket.assigns.current_user, id) do
      {:ok, file} ->
        {:noreply,
         assign(socket,
           editing_file: file,
           file_tags_input: Enum.join(file.tags || [], "\n")
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "File unavailable")}
    end
  end

  def handle_event("save_file_tags", params, %{assigns: %{editing_file: file}} = socket)
      when not is_nil(file) do
    case parse_tags_input(params["tags"]) do
      {:ok, tags} ->
        case Storage.change_tags(
               socket.assigns.current_user,
               file.application_id,
               file.id,
               :replace,
               tags
             ) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> assign(editing_file: nil, file_tags_input: "")
             |> put_flash(:info, "File tags updated")
             |> load_files()}

          {:error, {:invalid_tags, message}} ->
            {:noreply, put_flash(socket, :error, message)}

          _ ->
            {:noreply, put_flash(socket, :error, "Unable to update file tags.")}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("close_dialog", _, socket),
    do:
      {:noreply,
       assign(socket,
         file_details: nil,
         deleting_file: nil,
         editing_file: nil,
         file_tags_input: ""
       )}

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp load_files(socket) do
    actor = socket.assigns.current_user

    opts = [
      search: socket.assigns.file_search,
      sort: socket.assigns.file_sort,
      page: socket.assigns.file_page,
      tags: socket.assigns.file_tags
    ]

    opts =
      if socket.assigns.file_app == "",
        do: opts,
        else: Keyword.put(opts, :application_id, socket.assigns.file_app)

    case Storage.global_files_page(actor, opts) do
      %{files: _} = result ->
        clamped? = result.page != socket.assigns.file_page

        socket =
          socket
          |> assign(
            files: result.files,
            file_total: result.total,
            file_page: result.page,
            file_pages: result.pages,
            file_search: result.search,
            file_sort: result.sort,
            file_tags: result.tags,
            file_prev:
              if(result.page > 1,
                do:
                  files_path(
                    socket.assigns.file_view,
                    result.search,
                    result.sort,
                    socket.assigns.file_app,
                    result.page - 1,
                    result.tags
                  )
              ),
            file_next:
              if(result.page < result.pages,
                do:
                  files_path(
                    socket.assigns.file_view,
                    result.search,
                    result.sort,
                    socket.assigns.file_app,
                    result.page + 1,
                    result.tags
                  )
              )
          )
          |> stream(:files, result.files, reset: true)

        if clamped? and connected?(socket) do
          push_patch(socket,
            to:
              files_path(
                socket.assigns.file_view,
                result.search,
                result.sort,
                socket.assigns.file_app,
                result.page,
                result.tags
              )
          )
        else
          socket
        end

      {:error, _} ->
        socket
        |> assign(file_tags: [], file_search: "", file_sort: "newest", file_page: 1)
        |> put_flash(:error, "Invalid file filters.")
        |> load_files()
    end
  end

  defp refresh_open_details(%{assigns: %{file_details: nil}} = socket), do: socket

  defp refresh_open_details(%{assigns: %{file_details: %{id: id}}} = socket) do
    case authorized_file(socket.assigns.current_user, id) do
      {:ok, file} -> assign(socket, file_details: file)
      _ -> assign(socket, file_details: nil)
    end
  end

  defp load_applications(socket) do
    apps =
      Application
      |> Ash.Query.sort(name: :asc)
      |> Ash.Query.limit(100)
      |> Ash.read!(actor: socket.assigns.current_user)

    assign(socket, applications: apps, app_labels: Map.new(apps, &{&1.id, &1.name}))
  end

  defp authorized_file(actor, id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, %StoredFile{status: "ready"} = file} <-
           Ash.get(StoredFile, uuid, actor: actor, load: [:variants, :application]) do
      {:ok, file}
    else
      _ -> {:error, :not_found}
    end
  end

  defp authorized_file(_, _), do: {:error, :not_found}

  defp format_bytes(size) when size < 1024, do: "#{size} B"
  defp format_bytes(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_bytes(size), do: "#{Float.round(size / (1024 * 1024), 1)} MB"

  defp display_variant(file),
    do: Enum.find(file.variants, &(&1.name == "display_webp" and &1.status == "ready"))

  defp file_param(value, max) when is_binary(value),
    do: String.trim(value) |> String.slice(0, max)

  defp file_param(_, _), do: ""

  defp page_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 -> Kernel.min(n, 100_000)
      _ -> 1
    end
  end

  defp page_param(value) when is_integer(value) and value >= 1, do: Kernel.min(value, 100_000)
  defp page_param(_), do: 1

  defp app_param(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> ""
    end
  end

  defp app_param(_), do: ""

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

    Storage.validate_tags_filter(tags)
  end

  defp parse_tags_input(tags) when is_list(tags), do: Storage.validate_tags_filter(tags)
  defp parse_tags_input(_), do: {:error, "Tags must be one per line."}

  defp files_path(view, search, sort, app, page, tags) do
    params = if view == "grid", do: [{"view", "grid"}], else: []
    params = if sort != "newest", do: params ++ [{"sort", sort}], else: params
    params = if search != "", do: params ++ [{"search", search}], else: params
    params = if app != "", do: params ++ [{"app", app}], else: params
    params = if page != 1, do: params ++ [{"page", to_string(page)}], else: params
    params = params ++ Enum.map(tags, &{"tags[]", &1})

    "/dashboard/files?#{URI.encode_query(params)}"
  end
end
