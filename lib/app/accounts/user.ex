defmodule App.Accounts.User do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshJsonApi.Resource]

  json_api do
    type "user"
  end

  authentication do
    tokens do
      enabled? true
      token_resource App.Accounts.Token
      signing_secret App.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      github do
        client_id App.Secrets
        client_secret App.Secrets
        redirect_uri App.Secrets
        identity_resource App.Accounts.UserIdentity
        # Assent fetches GitHub's primary email and verification flag from /user/emails.
        trust_email_verified? true
        on_untrusted_email_match :reject
      end
    end
  end

  postgres do
    table "users"
    repo App.Repo
  end

  actions do
    defaults [:read]

    read :admin_read do
      pagination offset?: true, default_limit: 50, max_page_size: 100
    end

    read :get_by_subject do
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      get_by :email
    end

    create :register_with_github do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:confirmed_at, :avatar_url]

      change fn changeset, _ ->
        info = Ash.Changeset.get_argument(changeset, :user_info)

        if info["email_verified"] == true and is_binary(info["email"]) and
             String.trim(info["email"]) != "" do
          changeset
          |> Ash.Changeset.set_argument(:oauth_tokens, %{})
          |> Ash.Changeset.change_attribute(:email, String.downcase(String.trim(info["email"])))
          |> Ash.Changeset.force_change_attribute(:name, info["name"])
          |> Ash.Changeset.force_change_attribute(:avatar_url, info["picture"])
          |> Ash.Changeset.force_change_attribute(:confirmed_at, DateTime.utc_now())
        else
          Ash.Changeset.add_error(
            changeset,
            "GitHub must supply a verified primary email address"
          )
        end
      end

      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change App.Accounts.Changes.GithubEmailProof
      change AshAuthentication.GenerateTokenChange
    end

    create :register_with_otp do
      accept [:email, :name]
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email, :confirmed_at]
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
    end

    update :update_profile do
      accept [:name]
    end

    update :mark_operator do
      accept []
      change set_attribute(:operator, true)
      change set_attribute(:banned, false)
    end

    update :ban do
      require_atomic? false
      accept []

      change fn changeset, context ->
        if context.actor && changeset.data.id == context.actor.id,
          do: Ash.Changeset.add_error(changeset, "You cannot ban your own operator account"),
          else: changeset
      end

      change set_attribute(:banned, true)
      change set_attribute(:banned_at, &DateTime.utc_now/0)
    end

    update :unban do
      accept []
      change set_attribute(:banned, false)
      change set_attribute(:banned_at, nil)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action([:mark_operator, :ban, :unban, :admin_read]) do
      authorize_if App.Checks.Operator
    end

    policy action([:read, :get_by_subject, :get_by_email, :update_profile]) do
      forbid_unless App.Checks.ActiveActor
      authorize_if expr(id == ^actor(:id))
    end
  end

  preparations do
    prepare App.Accounts.Preparations.RejectBanned
  end

  changes do
    change App.Accounts.Changes.RegistrationGuard, on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :confirmed_at, :utc_datetime_usec

    attribute :name, :string do
      allow_nil? true
      public? true
    end

    attribute :avatar_url, :string do
      allow_nil? true
      public? true
    end

    # Retained only to avoid destructive removal of legacy database data. No password strategy/actions.
    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    attribute :operator, :boolean do
      allow_nil? false
      default false
      public? false
    end

    attribute :banned, :boolean do
      allow_nil? false
      default false
      public? false
    end

    attribute :banned_at, :utc_datetime_usec do
      allow_nil? true
      public? false
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
