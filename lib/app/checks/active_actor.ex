defmodule App.Checks.ActiveActor do
  use Ash.Policy.SimpleCheck
  def describe(_), do: "an active account"
  def match?(actor, _, _), do: not is_nil(App.Accounts.active_user(actor))
end
