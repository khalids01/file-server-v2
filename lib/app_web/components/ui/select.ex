defmodule AppWeb.UI.Select do
  @moduledoc "Shared custom single-select with keyboard navigation and form serialization."
  use Phoenix.Component
  import AppWeb.UI.Button
  import AppWeb.UI.Icon
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, default: nil
  attr :options, :list, required: true
  attr :value, :any, default: nil
  attr :prompt, :string, default: nil

  def select(assigns) do
    options = Enum.map(assigns.options, fn {label, value} -> {label, to_string(value)} end)

    value =
      if is_nil(assigns.value),
        do:
          if(assigns.prompt,
            do: "",
            else:
              options |> List.first() |> then(fn item -> if item, do: elem(item, 1), else: "" end)
          ),
        else: to_string(assigns.value)

    selected = Enum.find(options, fn {_, v} -> v == value end)

    assigns =
      assign(assigns,
        options: options,
        value: value,
        selected_label:
          if(selected, do: elem(selected, 0), else: assigns.prompt || "Select an option")
      )

    ~H"""
    <div id={@id} phx-hook="Select" class="ui-select grid gap-1.5 mb-2">
      <label :if={@label} for={@id <> "-trigger"} class="ui-label">{@label}</label>
      <input type="hidden" name={@name} value={@value} data-select-value />
      <.button
        id={@id <> "-trigger"}
        type="button"
        variant="outline"
        class="w-full justify-between font-normal"
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded="false"
        aria-controls={@id <> "-options"}
        data-select-trigger
      >
        <span data-select-label>{@selected_label}</span><.icon
          name="hero-chevron-up-down"
          class="size-4 shrink-0 text-muted-foreground"
        />
      </.button>
      <div
        id={@id <> "-options"}
        role="listbox"
        aria-label={@label || "Options"}
        class="ui-select-options"
        hidden
      >
        <.button
          :for={{label, value} <- @options}
          type="button"
          variant="ghost"
          role="option"
          aria-selected={to_string(value == @value)}
          data-select-option={value}
          tabindex="-1"
          class="w-full justify-start rounded-sm px-2 py-2 text-left font-normal"
        >{label}</.button>
      </div>
    </div>
    """
  end
end
