defmodule App.Accounts.User do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshJsonApi.Resource]

  require Ash.Resource.Change.Builtins

  json_api do
    type "user"
  end

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end

      confirmation :confirm_new_user do
        monitor_fields [:email]
        confirm_on_create? true
        confirm_on_update? false
        require_interaction? true
        confirmed_at_field :confirmed_at
        auto_confirm_actions [:sign_in_with_magic_link, :register_with_otp]
        sender App.Accounts.User.Senders.SendNewUserConfirmationEmail
      end
    end

    tokens do
      enabled? true
      token_resource App.Accounts.Token
      signing_secret App.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender App.Accounts.User.Senders.SendMagicLinkEmail
      end

      password :password do
        identity_field :email
        hashed_password_field :hashed_password
        hash_provider AshAuthentication.BcryptProvider
        confirmation_required? true
        register_action_accept [:name]
        require_confirmed_with :confirmed_at

        resettable do
          token_lifetime {1, :hours}
          sender App.Accounts.User.Senders.SendPasswordResetEmail
        end
      end

      github do
        client_id App.Secrets
        client_secret App.Secrets
        redirect_uri App.Secrets
        identity_resource App.Accounts.UserIdentity
        trust_email_verified? false
        on_untrusted_email_match :reject
      end

      remember_me :remember_me

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
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
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      change AshAuthentication.Strategy.MagicLink.SignInChange

      change {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
              strategy_name: :remember_me}

      change after_action(fn _changeset, user, _context ->
               if user.banned do
                 {:error, Ash.Error.Forbidden.exception([])}
               else
                 {:ok, user}
               end
             end)

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
      prepare App.Accounts.Preparations.RejectBanned
    end

    create :register_with_github do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true
      upsert? true
      upsert_identity :unique_email

      change fn changeset, _ ->
        Ash.Changeset.set_argument(changeset, :oauth_tokens, %{})
      end

      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        changeset
        |> Ash.Changeset.change_attributes(Map.take(user_info, ["email"]))
        |> Ash.Changeset.force_change_attribute(:name, user_info["name"])
      end

      upsert_fields []

      change after_action(fn _changeset, user, _context ->
               if user.banned do
                 {:error, Ash.Error.Forbidden.exception([])}
               else
                 {:ok, user}
               end
             end)
    end

    create :register_with_otp do
      description "Create or confirm an email-verified user from a one-time code."

      accept [:email]
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

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

    attribute :name, :string do
      allow_nil? true
      public? true
    end

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

  relationships do
    has_many :valid_api_keys, App.Accounts.ApiKey do
      filter expr(valid)
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
