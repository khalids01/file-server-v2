defmodule App.Accounts do
  use Ash.Domain, otp_app: :app, extensions: [AshAdmin.Domain, AshJsonApi.Domain]

  admin do
    show? true
  end

  json_api do
    routes do
      base_route "/users", App.Accounts.User do
        index :read
        get :read
      end
    end
  end

  resources do
    resource App.Accounts.Token
    resource App.Accounts.User
    resource App.Accounts.ApiKey
  end
end
