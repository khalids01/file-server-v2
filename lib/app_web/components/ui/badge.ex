defmodule AppWeb.UI.Badge do
  @moduledoc "Shared badge component using semantic theme tokens."
  use Phoenix.Component

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["ui-badge", @class]}>{render_slot(@inner_block)}</span>
    """
  end
end
