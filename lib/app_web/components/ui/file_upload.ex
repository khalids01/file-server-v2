defmodule AppWeb.UI.FileUpload do
  @moduledoc "Shared styled LiveView file picker with progress and validation errors."
  use Phoenix.Component
  import AppWeb.UI.Button
  import AppWeb.UI.Icon
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :max_mb, :integer, required: true

  def file_upload(assigns) do
    ~H"""
    <div class="space-y-4">
      <label
        for={@upload.ref}
        class="block cursor-pointer rounded-lg border border-dashed border-input bg-muted/30 p-8 text-center transition-colors hover:bg-accent focus-within:ring-2 focus-within:ring-ring"
        phx-drop-target={@upload.ref}
      >
        <.icon name="hero-arrow-up-tray" class="mx-auto mb-3 size-7 text-muted-foreground" />
        <span class="block text-sm font-medium">Choose files or drop them here</span>
        <span class="mt-1 block text-xs text-muted-foreground">Up to 5 files at a time · {@max_mb} MB per file · Private by default</span>
        <.live_file_input upload={@upload} class="sr-only" />
      </label>
      <p :for={error <- upload_errors(@upload)} role="alert" class="text-sm text-destructive">
        {error_message(error)}
      </p>
      <div
        :for={entry <- @upload.entries}
        id={"upload-entry-#{entry.ref}"}
        class="rounded-lg border border-border p-3"
      >
        <div class="flex items-center justify-between gap-3">
          <span class="truncate text-sm">{entry.client_name}</span><.button
            type="button"
            variant="ghost"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            aria-label={"Remove " <> entry.client_name}
          ><.icon name="hero-x-mark" /></.button>
        </div>
        <p class="mt-1 text-xs text-muted-foreground" aria-live="polite">
          {entry.progress}% · {if entry.done?, do: "Ready to store", else: "Waiting / transferring"}
        </p>
        <div
          role="progressbar"
          aria-label={entry.client_name}
          aria-valuenow={entry.progress}
          aria-valuemin="0"
          aria-valuemax="100"
          class="mt-2 h-1.5 overflow-hidden rounded-full bg-muted"
        >
          <div class="h-full bg-primary transition-all" style={"width: #{entry.progress}%"} />
        </div>
        <p
          :for={error <- upload_errors(@upload, entry)}
          role="alert"
          class="mt-2 text-sm text-destructive"
        >
          {error_message(error)}
        </p>
      </div>
    </div>
    """
  end

  defp error_message(:too_large), do: "This file exceeds the upload size limit."
  defp error_message(:too_many_files), do: "Choose up to five files at a time."
  defp error_message(_), do: "This file could not be uploaded. Please try again."
end
