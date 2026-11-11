defmodule App.Checks.VisibleTenants do
  use Ash.Policy.FilterCheck
  def describe(_), do: "workspace membership"
  def filter(actor, _, _), do: [id: [in: App.Workspaces.tenant_ids(actor)]]
end
