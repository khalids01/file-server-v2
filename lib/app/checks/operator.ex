defmodule App.Checks.Operator do
  use Ash.Policy.SimpleCheck
  def describe(_), do: "an active platform operator"
  def match?(actor, _, _), do: Kernel.match?(%{operator: true}, App.Accounts.active_user(actor))
end
