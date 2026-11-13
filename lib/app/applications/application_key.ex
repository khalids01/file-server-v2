defmodule App.Applications.ApplicationKey do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Applications,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "application_keys"
    migration_defaults scopes: "nil", expires_at: "nil"
    repo App.Repo
  end

  actions do
    defaults [:read]

    create :issue do
      primary? true
      accept [:name, :application_id, :scopes, :key_hash, :fingerprint]
      change relate_actor(:user)

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          id = Ash.Changeset.get_attribute(changeset, :application_id)

          case Ash.get(App.Applications.Application, id, actor: context.actor) do
            {:ok, %App.Applications.Application{}} ->
              changeset

            _ ->
              Ash.Changeset.add_error(changeset, "Application is unavailable")
          end
        end)
      end
    end

    update :revoke do
      accept []
      change set_attribute(:revoked_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always() do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 2, max_length: 80
    end

    attribute :key_hash, :string, allow_nil?: false, sensitive?: true
    attribute :fingerprint, :string, allow_nil?: false

    attribute :scopes, {:array, :string} do
      allow_nil? false
      default ["files:read"]
      constraints min_length: 1, items: [match: ~r/^files:(read|write|delete)$/]
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
      default fn -> DateTime.add(DateTime.utc_now(), 30, :day) end
    end

    attribute :revoked_at, :utc_datetime_usec
    create_timestamp :created_at
  end

  relationships do
    belongs_to :application, App.Applications.Application, allow_nil?: false
    belongs_to :user, App.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_key, [:key_hash]
  end
end
