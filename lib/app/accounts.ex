defmodule App.Accounts do
  use Ash.Domain, otp_app: :app, extensions: [AshAdmin.Domain, AshJsonApi.Domain]

  def active_user(%App.Accounts.User{id: id}) do
    case Ash.get(App.Accounts.User, id, authorize?: false) do
      {:ok, %{banned: false, confirmed_at: confirmed} = user} when not is_nil(confirmed) -> user
      _ -> nil
    end
  end

  def active_user(_), do: nil

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
    resource App.Accounts.UserIdentity
    resource App.Accounts.OtpChallenge
    resource App.Accounts.ApiKey
  end
end
