defmodule AppWeb.UI.Card do
  @moduledoc "Shared card component using semantic theme tokens."
  use Phoenix.Component

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={["ui-card", @class]} {@rest}>{render_slot(@inner_block)}</section>
    """
  end
end
