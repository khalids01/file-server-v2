defmodule App.Storage.StoredFileVariant do
  @moduledoc "A generated private image variant tracked as billable storage."
  use Ash.Resource,
    otp_app: :app,
    domain: App.Storage,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stored_file_variants"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:file_id, :name, :object_key, :content_type, :size, :width, :height, :status]
    end

    update :update do
      primary? true
      accept [:status, :size, :width, :height, :content_type, :object_key]
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(file.user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :object_key, :string, allow_nil?: false, sensitive?: true
    attribute :content_type, :string, allow_nil?: false
    attribute :size, :integer, allow_nil?: false, constraints: [min: 0]
    attribute :width, :integer
    attribute :height, :integer
    attribute :status, :string, allow_nil?: false, default: "ready"

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :file, App.Storage.StoredFile, allow_nil?: false
  end
end
