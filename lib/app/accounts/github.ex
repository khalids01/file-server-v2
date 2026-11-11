defmodule App.Accounts.Github do
  @moduledoc """
  Runtime GitHub OAuth configuration.

  GitHub is enabled only when both client credentials are present. Credentials
  are read from the process environment at request time so that a running
  release can be reconfigured without recompiling.
  """

  @doc """
  Whether GitHub sign-in can be offered. Returns false when operator credentials
  are absent so the UI and callback both degrade to a neutral sign-in error.
  """
  def enabled? do
    {:ok, id} = client_id()
    {:ok, secret} = client_secret()
    is_binary(id) and id != "" and is_binary(secret) and secret != ""
  end

  @doc "The OAuth client ID, or nil when not configured."
  def client_id, do: {:ok, configured(:client_id, "GITHUB_CLIENT_ID")}

  @doc "The OAuth client secret, or nil when not configured."
  def client_secret, do: {:ok, configured(:client_secret, "GITHUB_CLIENT_SECRET")}

  @doc """
  The callback URI base. Ash Authentication appends `user/github/callback`, so
  the default produces `/auth/user/github/callback`.
  """
  def redirect_uri do
    {:ok, env("GITHUB_REDIRECT_URI") || AppWeb.Endpoint.url() <> "/auth"}
  end

  defp configured(key, variable) do
    case Keyword.fetch(Application.get_env(:app, :github, []), key) do
      {:ok, value} -> value
      :error -> env(variable)
    end
  end

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      value -> String.trim(value)
    end
  end
end
