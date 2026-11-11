defmodule App.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :app,
    domain: App.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.UserIdentity]

  user_identity do
    user_resource App.Accounts.User
  end

  postgres do
    table "user_identities"
    repo App.Repo
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
