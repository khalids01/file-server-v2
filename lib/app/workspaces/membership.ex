defmodule App.Workspaces.Membership do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Workspaces,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspace_memberships"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:user_id, :role]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {App.Checks.TenantAccess, admin?: true}
    end

    # Membership administration/invitations are deliberately deferred for this MVP.
    policy action_type(:create) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false

    attribute :role, :atom do
      constraints one_of: [:owner, :admin, :member]
      allow_nil? false
    end
  end

  relationships do
    belongs_to :user, App.Accounts.User, allow_nil?: false
    belongs_to :tenant, App.Workspaces.Tenant, define_attribute?: false
  end

  identities do
    identity :unique_member, [:user_id]
  end
end
