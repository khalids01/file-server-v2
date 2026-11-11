defmodule App.Platform.Setting do
  @moduledoc "Operator-controlled platform settings (currently the signup toggle)."

  use Ash.Resource,
    otp_app: :app,
    domain: App.Platform,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "platform_settings"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:key, :value]
      primary? true
    end

    update :update do
      accept [:value]
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if App.Checks.Operator
    end

    policy action_type([:create, :update]) do
      authorize_if App.Checks.Operator
    end
  end

  attributes do
    attribute :key, :string do
      allow_nil? false
      primary_key? true
    end

    attribute :value, :string do
      allow_nil? true
    end

    update_timestamp :updated_at
  end
end
