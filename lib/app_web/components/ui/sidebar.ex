defmodule AppWeb.UI.Sidebar do
  @moduledoc "Application navigation with desktop icon collapse and a mobile drawer."
  use Phoenix.Component
  import AppWeb.UI.Icon
  import AppWeb.UI.Button

  attr :current_user, :any, default: nil
  attr :section, :string, required: true

  def sidebar(assigns) do
    items = [
      {"Overview", "/dashboard", "hero-squares-2x2"},
      {"Applications", "/dashboard/applications", "hero-command-line"},
      {"Profile", "/dashboard/profile", "hero-user-circle"}
    ]

    items =
      if assigns.current_user && assigns.current_user.operator,
        do: items ++ [{"Operator admin", "/dashboard/admin", "hero-shield-check"}],
        else: items

    assigns = assign(assigns, :items, items)

    ~H"""
    <.button
      variant="ghost"
      type="button"
      data-sidebar-close
      class="sidebar-backdrop"
      aria-label="Close sidebar"
      tabindex="-1"
    ><span class="sr-only">Close sidebar</span></.button>
    <aside id="app-sidebar" class="app-sidebar" aria-label="Application sidebar">
      <p class="sidebar-heading sidebar-label">Dashboard</p>
      <nav class="flex flex-col gap-1" aria-label="Application navigation">
        <.link
          :for={{label, path, icon} <- @items}
          navigate={path}
          title={label}
          aria-label={label}
          aria-current={if @section == label, do: "page"}
          class={["sidebar-link", @section == label && "sidebar-link-active"]}
        >
          <.icon name={icon} class="size-4 shrink-0" />
          <span class="sidebar-label">{label}</span>
        </.link>
      </nav>
      <div class="sidebar-footer sidebar-label">
        <strong class="mb-1 block font-medium text-foreground">Your infrastructure.</strong>
        Your applications, your keys. File storage is coming next.
      </div>
    </aside>
    """
  end

  def sidebar_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="3" width="18" height="18" rx="4" /><path d="M9 3v18" />
    </svg>
    """
  end
end
