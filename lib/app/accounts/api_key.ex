defmodule App.Accounts.ApiKey do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "api_keys"
    repo App.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:expires_at]
      change relate_actor(:user)

      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey, prefix: :app, hash: :api_key_hash}
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :destroy]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :api_key_hash, :binary do
      allow_nil? false
      sensitive? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
    end
  end

  relationships do
    belongs_to :user, App.Accounts.User do
      allow_nil? false
    end
  end

  calculations do
    calculate :valid, :boolean, expr(expires_at > now())
  end

  identities do
    identity :unique_api_key, [:api_key_hash]
  end
end
