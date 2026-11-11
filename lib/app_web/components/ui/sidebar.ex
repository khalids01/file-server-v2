defmodule AppWeb.UI.Sidebar do
  @moduledoc "Workspace navigation with desktop icon collapse and a mobile drawer."
  use Phoenix.Component
  import AppWeb.UI.Icon

  attr :current_user, :any, default: nil
  attr :section, :string, required: true
  attr :tenant_id, :string, default: nil

  def sidebar(assigns) do
    items = [
      {"Overview", "/dashboard", "hero-squares-2x2"},
      {"Applications", "/dashboard/applications", "hero-command-line"},
      {"Workspace settings", "/dashboard/settings", "hero-cog-6-tooth"},
      {"Your profile", "/dashboard/profile", "hero-user-circle"}
    ]

    items =
      if assigns.current_user && assigns.current_user.operator,
        do: items ++ [{"Operator admin", "/dashboard/admin", "hero-shield-check"}],
        else: items

    assigns = assign(assigns, :items, items)

    ~H"""
    <button
      type="button"
      data-sidebar-close
      class="sidebar-backdrop"
      aria-label="Close sidebar"
      tabindex="-1"
    />
    <aside id="workspace-sidebar" class="workspace-sidebar" aria-label="Workspace sidebar">
      <p class="sidebar-heading sidebar-label">Workspace</p>
      <nav class="flex flex-col gap-1" aria-label="Workspace navigation">
        <.link
          :for={{label, path, icon} <- @items}
          navigate={path <> if(@tenant_id, do: "?tenant=" <> @tenant_id, else: "")}
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
        Authentication and workspaces are ready. File storage is coming next.
      </div>
    </aside>
    """
  end
end
