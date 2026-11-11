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
    present = fn key ->
      value = System.get_env(key)
      is_binary(value) and String.trim(value) != ""
    end

    present.("GITHUB_CLIENT_ID") and present.("GITHUB_CLIENT_SECRET")
  end

  @doc "The OAuth client ID, or nil when not configured."
  def client_id, do: {:ok, env("GITHUB_CLIENT_ID")}

  @doc "The OAuth client secret, or nil when not configured."
  def client_secret, do: {:ok, env("GITHUB_CLIENT_SECRET")}

  @doc """
  The callback URI base. Ash Authentication appends `user/github/callback`, so
  the default produces `/auth/user/github/callback`.
  """
  def redirect_uri do
    {:ok, env("GITHUB_REDIRECT_URI") || AppWeb.Endpoint.url() <> "/auth"}
  end

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      value -> String.trim(value)
    end
  end
end
