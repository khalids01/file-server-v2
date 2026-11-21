defmodule App.DashboardNotifier do
  @moduledoc "Committed owner-scoped dashboard invalidation, without record payloads."
  use Ash.Notifier

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(App.PubSub, topic(user_id))

  @impl true
  def notify(%{data: %{user_id: user_id}}) when is_binary(user_id) do
    Phoenix.PubSub.broadcast(App.PubSub, topic(user_id), :dashboard_changed)
  end

  def notify(_), do: :ok

  defp topic(user_id), do: "dashboard:" <> user_id
end
