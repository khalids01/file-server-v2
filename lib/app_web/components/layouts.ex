defmodule AppWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AppWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true
  attr :current_user, :any, default: nil
  attr :current_scope, :any, default: nil
  attr :section, :string, default: nil
  attr :tenant_id, :string, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f7f8fb] text-slate-900 antialiased">
      <header class="sticky top-0 z-30 flex h-18 items-center justify-between border-b border-slate-200/80 bg-white/95 px-5 backdrop-blur lg:px-10">
        <.link
          href="/"
          class="flex items-center gap-2.5 text-xl font-bold tracking-tight"
          aria-label="Serve home"
        >
          <span class="flex size-9 items-center justify-center rounded-xl bg-indigo-600 text-white"><.icon
            name="hero-server-stack-solid"
            class="size-5"
          /></span>
          Serve
          <span class="ml-1 rounded-md bg-indigo-50 px-2 py-0.5 text-[10px] font-bold tracking-widest text-indigo-600">V2</span>
        </.link>
        <nav class="flex items-center gap-4 text-sm font-medium">
          <%= if @current_user do %>
            <span class="hidden text-slate-500 sm:block">{to_string(@current_user.email)}</span>
            <.link href="/sign-out" class="text-slate-600 hover:text-indigo-600">Sign out</.link>
          <% else %>
            <.link href="/sign-in" class="text-slate-600 hover:text-indigo-600">Sign in</.link>
            <.link
              href="/register"
              class="rounded-lg bg-slate-900 px-4 py-2.5 text-white transition hover:bg-indigo-600"
            >Get started <span aria-hidden="true">↗</span></.link>
          <% end %>
        </nav>
      </header>
      <div class={[@section && "mx-auto flex max-w-[1600px] flex-col lg:flex-row"]}>
        <aside
          :if={@section}
          class="flex gap-1 overflow-x-auto border-b border-slate-200 bg-white p-3 lg:min-h-[calc(100vh-4.5rem)] lg:w-60 lg:shrink-0 lg:flex-col lg:border-r lg:border-b-0 lg:p-5"
        >
          <p class="hidden px-3 pb-3 pt-4 text-[10px] font-bold uppercase tracking-[0.2em] text-slate-400 lg:block">
            Workspace
          </p>
          <.link
            :for={
              {label, path, icon} <- [
                {"Overview", "/dashboard", "hero-squares-2x2"},
                {"Applications", "/dashboard/applications", "hero-command-line"},
                {"Workspace settings", "/dashboard/settings", "hero-cog-6-tooth"},
                {"Your profile", "/dashboard/profile", "hero-user-circle"}
              ]
            }
            navigate={path <> if(@tenant_id, do: "?tenant=" <> @tenant_id, else: "")}
            class={[
              "flex shrink-0 items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium transition",
              if(@section == label,
                do: "bg-indigo-50 text-indigo-700",
                else: "text-slate-500 hover:bg-slate-50 hover:text-slate-900"
              )
            ]}
          ><.icon name={icon} class="size-5" />{label}</.link>
          <.link
            :if={@current_user && @current_user.operator}
            navigate="/dashboard/admin"
            class="mt-2 flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium text-slate-500 hover:bg-slate-50"
          ><.icon name="hero-shield-check" class="size-5" />Operator admin</.link>
          <div class="mt-auto hidden rounded-xl border border-slate-200 bg-slate-50 p-4 text-xs leading-5 text-slate-500 lg:block">
            <strong class="block text-slate-700">Foundation release</strong>Authentication and workspaces are ready to explore. File storage is coming next.
          </div>
        </aside>
        <main class={[@section && "min-w-0 flex-1 p-5 sm:p-8 lg:p-10"]}>
          {render_slot(@inner_block)}
        </main>
      </div>
      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <.app flash={@flash}>
      <div class="mx-auto max-w-md px-5 py-14 sm:py-20">
        <div class="rounded-2xl border border-slate-200 bg-white p-7 shadow-sm sm:p-9">
          {render_slot(@inner_block)}
        </div>
        <p class="mt-6 text-center text-xs text-slate-400">Your workspace. Your infrastructure.</p>
      </div>
    </.app>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
