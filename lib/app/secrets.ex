defmodule App.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], App.Accounts.User, _opts, _context) do
    Application.fetch_env(:app, :token_signing_secret)
  end
end
