defmodule App.Storage.Connection do
  @moduledoc "Immutable, application-owned S3 destination with encrypted credentials."
  use Ash.Resource,
    otp_app: :app,
    domain: App.Storage,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "storage_connections"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :endpoint, :bucket, :region, :credentials, :application_id]
      change relate_actor(:user)
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(user_id == ^actor(:id))
    end

    # Only the storage service can create destinations, after validating the app and endpoint.
    policy action_type(:create) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      constraints: [min_length: 2, max_length: 80, trim?: true]

    attribute :endpoint, :string, allow_nil?: false
    attribute :bucket, :string, allow_nil?: false
    attribute :region, :string, allow_nil?: false
    attribute :credentials, :binary, allow_nil?: false, sensitive?: true
    create_timestamp :created_at
  end

  relationships do
    belongs_to :application, App.Applications.Application, allow_nil?: false
    belongs_to :user, App.Accounts.User, allow_nil?: false
  end
end
