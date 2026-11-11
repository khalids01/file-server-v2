defmodule App.Workspaces.Application do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Workspaces,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspace_applications"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :slug]
    end

    update :update do
      primary? true
      accept [:name]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {App.Checks.TenantAccess, admin?: true}
    end

    policy action_type([:create, :update]) do
      authorize_if {App.Checks.TenantAccess, admin?: true}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant_id
  end

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :uuid, allow_nil?: false

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 2, max_length: 80, trim?: true
    end

    attribute :slug, :string do
      allow_nil? false
      constraints min_length: 2, max_length: 60, match: ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :tenant, App.Workspaces.Tenant, define_attribute?: false
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
