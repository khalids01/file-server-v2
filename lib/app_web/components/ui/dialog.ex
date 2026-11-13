defmodule AppWeb.UI.Dialog do
  @moduledoc "Shared styled modal with native focus containment and Escape support."
  use Phoenix.Component
  import AppWeb.UI.Button
  import AppWeb.UI.Icon
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  def dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      phx-hook="Dialog"
      aria-labelledby={@id <> "-title"}
      aria-describedby={@description && @id <> "-description"}
      class="ui-dialog"
    >
      <div class="mb-6 flex items-start justify-between gap-4">
        <div>
          <h2 id={@id <> "-title"} class="text-lg font-semibold">{@title}</h2><p
            :if={@description}
            id={@id <> "-description"}
            class="mt-2 text-sm text-muted-foreground"
          >
            {@description}
          </p>
        </div>
        <.button
          type="button"
          variant="ghost"
          phx-click="close_dialog"
          aria-label="Close dialog"
          class="size-8 shrink-0 p-0"
        ><.icon name="hero-x-mark" /></.button>
      </div>
      {render_slot(@inner_block)}
    </dialog>
    """
  end
end
