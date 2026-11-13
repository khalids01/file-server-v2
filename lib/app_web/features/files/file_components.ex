defmodule AppWeb.FileComponents do
  @moduledoc "Reusable private file previews and download-link controls."
  use Phoenix.Component
  import AppWeb.UI.Button
  import AppWeb.UI.Icon

  attr :file, :map, required: true
  attr :view, :string, default: "list"

  def file_media(assigns) do
    assigns =
      assign(
        assigns,
        :thumbnail?,
        Enum.any?(assigns.file.variants, &(&1.name == "thumbnail" and &1.status == "ready"))
      )

    ~H"""
    <img
      :if={@thumbnail?}
      src={"/files/#{@file.id}/variants/thumbnail"}
      alt={@file.filename}
      loading="lazy"
      class={
        if @view == "grid",
          do: "h-40 w-full rounded-lg border border-border bg-muted/20 object-contain",
          else: "h-12 w-12 shrink-0 rounded-md border border-border object-cover"
      }
    />
    <div
      :if={!@thumbnail?}
      class={
        if @view == "grid",
          do: "flex h-40 w-full items-center justify-center rounded-lg bg-muted/50",
          else: "flex size-12 shrink-0 items-center justify-center rounded-md bg-muted"
      }
      aria-hidden="true"
    >
      <.icon
        name={
          if String.starts_with?(@file.content_type, "image/"),
            do: "hero-photo",
            else: "hero-document"
        }
        class="size-8 text-muted-foreground"
      />
    </div>
    """
  end

  attr :file, :map, required: true

  def private_download_link(assigns) do
    ~H"""
    <.button
      id={"copy-download-#{@file.id}"}
      type="button"
      variant="outline"
      phx-hook="Clipboard"
      phx-update="ignore"
      data-download-path={"/files/#{@file.id}/download"}
      title="Private link: recipient must sign in with access to this file"
    >
      <span role="status" aria-live="polite">Copy private link</span>
    </.button>
    """
  end
end
