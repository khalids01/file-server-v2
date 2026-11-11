defmodule App.FailingMailAdapter do
  use Swoosh.Adapter

  def deliver(email, _) do
    send(self(), {:attempted_email, email})
    {:error, :smtp_unavailable}
  end
end
