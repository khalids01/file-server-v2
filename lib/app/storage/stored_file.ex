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
    defaults [:read]

    create :create do
      primary? true

      accept [
        :filename,
        :size,
        :content_type,
        :object_key,
        :application_id,
        :connection_id,
        :tags,
        :status,
        :processing_state,
        :processing_error,
        :reserved_bytes,
        :upload_operation_id,
        :pending_object_keys,
        :delete_requested_at,
        :delete_attempts,
        :last_error,
        :width,
        :height,
        :pixel_count,
        :source_format,
        :ready_at,
        :processing_generation
      ]

      change relate_actor(:user)
    end

    update :update_tags do
      accept [:tags]
    end

    update :internal_update do
      accept [
        :status,
        :processing_state,
        :processing_error,
        :reserved_bytes,
        :pending_object_keys,
        :delete_requested_at,
        :delete_attempts,
        :last_error,
        :width,
        :height,
        :pixel_count,
        :source_format,
        :ready_at,
        :processing_generation,
        :size,
        :content_type
      ]
    end

    destroy :destroy do
      primary? true
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
    attribute :status, :string, allow_nil?: false, default: "ready"
    attribute :processing_state, :string, allow_nil?: false, default: "not_applicable"
    attribute :processing_error, :string
    attribute :reserved_bytes, :integer, allow_nil?: false, default: 0, constraints: [min: 0]
    attribute :upload_operation_id, :string
    attribute :pending_object_keys, {:array, :string}, allow_nil?: false, default: []
    attribute :delete_requested_at, :utc_datetime_usec
    attribute :delete_attempts, :integer, allow_nil?: false, default: 0
    attribute :last_error, :string
    attribute :width, :integer
    attribute :height, :integer
    attribute :pixel_count, :integer
    attribute :source_format, :string
    attribute :ready_at, :utc_datetime_usec
    attribute :processing_generation, :integer, allow_nil?: false, default: 0

    create_timestamp :created_at
  end

  relationships do
    belongs_to :application, App.Applications.Application, allow_nil?: false
    belongs_to :connection, App.Storage.Connection
    belongs_to :user, App.Accounts.User, allow_nil?: false
    has_many :variants, App.Storage.StoredFileVariant, destination_attribute: :file_id
  end
end
