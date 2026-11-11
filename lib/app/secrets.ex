defmodule App.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], App.Accounts.User, _opts, _context) do
    Application.fetch_env(:app, :token_signing_secret)
  end

  def secret_for(
        [:authentication, :strategies, :github, :client_id],
        App.Accounts.User,
        _opts,
        _context
      ) do
    App.Accounts.Github.client_id()
  end

  def secret_for(
        [:authentication, :strategies, :github, :client_secret],
        App.Accounts.User,
        _opts,
        _context
      ) do
    App.Accounts.Github.client_secret()
  end

  def secret_for(
        [:authentication, :strategies, :github, :redirect_uri],
        App.Accounts.User,
        _opts,
        _context
      ) do
    App.Accounts.Github.redirect_uri()
  end
end
