defmodule App.Storage.AccountStorage do
  @moduledoc "Per-account storage quota and accounting totals."
  use Ash.Resource,
    otp_app: :app,
    domain: App.Storage,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "account_storage"
    repo App.Repo
  end

  actions do
    defaults [:read]
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
    attribute :user_id, :uuid, primary_key?: true, allow_nil?: false
    attribute :quota_bytes, :integer, allow_nil?: false, default: 5_368_709_120
    attribute :used_bytes, :integer, allow_nil?: false, default: 0
    attribute :reserved_bytes, :integer, allow_nil?: false, default: 0
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, App.Accounts.User, define_attribute?: false
  end
end
