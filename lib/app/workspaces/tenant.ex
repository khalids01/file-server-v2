defmodule App.Workspaces.Tenant do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Workspaces,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name]
      change relate_actor(:owner)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if App.Checks.ActiveActor
    end

    policy action_type(:read) do
      authorize_if App.Checks.VisibleTenants
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 2, max_length: 80, trim?: true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :owner, App.Accounts.User do
      allow_nil? false
    end
  end
end
