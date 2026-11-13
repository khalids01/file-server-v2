defmodule App.Storage.StoredFile do
  @moduledoc "Private file metadata bound to its original application and storage destination."
  use Ash.Resource,
    otp_app: :app,
    domain: App.Storage,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stored_files"
    repo App.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :filename,
        :size,
        :content_type,
        :object_key,
        :application_id,
        :connection_id,
        :tags
      ]

      change relate_actor(:user)
    end

    update :update_tags do
      accept [:tags]
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :filename, :string, allow_nil?: false, constraints: [max_length: 255]
    attribute :size, :integer, allow_nil?: false, constraints: [min: 0]
    attribute :content_type, :string, allow_nil?: false
    attribute :object_key, :string, allow_nil?: false, sensitive?: true
    attribute :tags, {:array, :string}, allow_nil?: false, default: []
    create_timestamp :created_at
  end

  relationships do
    belongs_to :application, App.Applications.Application, allow_nil?: false
    belongs_to :connection, App.Storage.Connection
    belongs_to :user, App.Accounts.User, allow_nil?: false
  end
end
