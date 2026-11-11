defmodule AppWeb.UI.Card do
  @moduledoc "Shared card component using semantic theme tokens."
  use Phoenix.Component

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={["ui-card", @class]}>{render_slot(@inner_block)}</section>
    """
  end
end
