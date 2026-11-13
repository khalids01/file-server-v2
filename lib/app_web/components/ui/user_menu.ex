defmodule AppWeb.UI.UserMenu do
  @moduledoc "Reusable account menu with a GitHub avatar or name initial."
  use Phoenix.Component
  import AppWeb.UI.Icon

  attr :user, :any, required: true
  attr :id, :string, default: "user-menu"

  def user_menu(assigns) do
    name = present(assigns.user.name) || to_string(assigns.user.email)

    assigns =
      assigns
      |> assign(:display_name, name)
      |> assign(:initial, name |> String.first() |> String.upcase())
      |> assign(:avatar, avatar_url(Map.get(assigns.user, :avatar_url)))

    ~H"""
    <details id={@id} data-user-menu class="relative">
      <summary
        id={@id <> "-button"}
        class="relative flex size-9 cursor-pointer list-none items-center justify-center overflow-hidden rounded-full border border-border bg-muted text-sm font-medium ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 [&::-webkit-details-marker]:hidden"
        aria-label={"Account menu for " <> @display_name}
      >
        <span aria-hidden="true">{@initial}</span>
        <img
          :if={@avatar}
          src={@avatar}
          alt=""
          class="absolute inset-0 size-full rounded-full object-cover"
          data-user-avatar
          referrerpolicy="no-referrer"
        />
      </summary>
      <div class="absolute right-0 z-50 mt-2 w-64 rounded-lg border border-border bg-card p-1 text-foreground shadow-lg">
        <div class="border-b border-border px-3 py-2">
          <p class="truncate text-sm font-medium">{@display_name}</p>
          <p class="truncate text-xs text-muted-foreground">{@user.email}</p>
        </div>
        <.link
          navigate="/dashboard/profile"
          class="flex items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-accent focus-visible:bg-accent"
        >
          <.icon name="hero-user-circle" />Profile
        </.link>
        <.link
          :if={@user.operator}
          navigate="/dashboard/admin"
          class="flex items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-accent focus-visible:bg-accent"
        >
          <.icon name="hero-shield-check" />Admin
        </.link>
        <.link
          href="/sign-out"
          class="flex items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-accent focus-visible:bg-accent"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" />Sign out
        </.link>
      </div>
    </details>
    """
  end

  defp present(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      name -> name
    end
  end

  defp present(_), do: nil

  # Only load avatar images from GitHub's HTTPS avatar host.
  defp avatar_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "avatars.githubusercontent.com", userinfo: nil} -> url
      _ -> nil
    end
  end

  defp avatar_url(_), do: nil
end
