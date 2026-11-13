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
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      id="app-shell"
      phx-hook={@section && "Sidebar"}
      class="min-h-screen bg-background text-foreground"
    >
      <header class="sticky top-0 z-30 flex h-16 items-center justify-between border-b border-border bg-card/95 px-5 backdrop-blur lg:px-8">
        <div class="flex min-w-0 items-center gap-3">
          <.link
            href="/"
            class="flex items-center gap-2.5 text-base font-semibold tracking-tight"
            aria-label="File Server home"
          >
            <span class="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground"><.icon
              name="hero-server-stack-solid"
              class="size-4"
            /></span>
            File Server
          </.link>
          <.button
            :if={@section}
            id="sidebar-toggle"
            type="button"
            variant="ghost"
            class="size-9 p-0"
            data-sidebar-toggle
            aria-controls="app-sidebar"
            aria-expanded="true"
            aria-label="Toggle sidebar"
          >
            <.sidebar_icon />
          </.button>
        </div>
        <nav class="flex items-center gap-2 text-sm font-medium" aria-label="Account navigation">
          <.theme_toggle />
          <%= if @current_user do %>
            <.user_menu user={@current_user} />
          <% else %>
            <.button href="/sign-in" variant="ghost">Sign in</.button>
            <.button href="/register" class="hidden sm:inline-flex">Get started
            <.icon name="hero-arrow-up-right" class="size-3.5" /></.button>
          <% end %>
        </nav>
      </header>
      <div class={[@section && "app-dashboard"]}>
        <.sidebar
          :if={@section}
          current_user={@current_user}
          section={@section}
        />
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
      <div class="mx-auto max-w-md px-5 py-12 sm:py-20">
        <.card class="p-6 sm:p-8">{render_slot(@inner_block)}</.card>
        <p class="mt-6 text-center text-xs text-muted-foreground">Your files. Your rules.</p>
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

  def theme_preference(cookies) do
    value = Map.get(cookies, "file-server-theme")
    if value in ["light", "dark", "system"], do: value, else: "system"
  end

  def theme_toggle(assigns) do
    ~H"""
    <details id="theme-menu" class="theme-menu relative">
      <summary
        class="ui-button ui-button-ghost size-9 !p-0"
        aria-label="Choose color theme"
        title="Choose color theme"
      >
        <.icon name="hero-sun" class="size-4 dark:hidden" /><.icon
          name="hero-moon"
          class="hidden size-4 dark:block"
        />
      </summary>
      <div
        class="ui-card absolute right-0 top-11 z-50 min-w-36 p-1 shadow-md"
        aria-label="Color theme"
      >
        <.button
          :for={
            {mode, title, icon} <- [
              {"light", "Light", "hero-sun"},
              {"dark", "Dark", "hero-moon"},
              {"system", "System", "hero-computer-desktop"}
            ]
          }
          variant="ghost"
          type="button"
          data-theme-choice={mode}
          aria-pressed="false"
          class="theme-option flex w-full items-center gap-2 rounded-sm px-2 py-2 text-left text-sm hover:bg-accent"
        ><.icon name={icon} class="size-4" />{title}</.button>
      </div>
    </details>
    """
  end
end
