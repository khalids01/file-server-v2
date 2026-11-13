defmodule App.Applications.Application do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Applications,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "applications"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :slug]
      change relate_actor(:user)
    end

    update :update do
      primary? true
      accept [:name]
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action_type([:create, :update]) do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

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
    belongs_to :user, App.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_slug, [:user_id, :slug]
  end
end
