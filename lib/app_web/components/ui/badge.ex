defmodule AppWeb.UI.Badge do
  @moduledoc "Shared badge component using semantic theme tokens."
  use Phoenix.Component

  attr :rest, :global
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["ui-badge", @class]} {@rest}>{render_slot(@inner_block)}</span>
    """
  end
end
