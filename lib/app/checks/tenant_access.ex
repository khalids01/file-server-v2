defmodule App.Checks.TenantAccess do
  use Ash.Policy.SimpleCheck
  def describe(_), do: "active workspace member with the required role"

  def match?(actor, context, opts) do
    tenant = context.subject.tenant
    role = App.Workspaces.role(actor, tenant)
    if opts[:admin?], do: role in ["owner", "admin"], else: role in ["owner", "admin", "member"]
  end
end
