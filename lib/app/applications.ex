defmodule App.Applications do
  @moduledoc "User-owned applications and scoped integration credentials."
  use Ash.Domain, otp_app: :app
  require Ash.Query
  alias App.Applications.{Application, ApplicationKey}

  resources do
    resource Application
    resource ApplicationKey
  end

  def applications(actor),
    do: Application |> Ash.Query.sort(created_at: :desc) |> Ash.read!(actor: actor)

  def issue_key!(actor, application_id, name, scopes) do
    Ash.get!(Application, application_id, actor: actor)
    raw = "sv2_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    key =
      Ash.create!(
        ApplicationKey,
        %{
          name: name,
          application_id: application_id,
          scopes: scopes,
          key_hash: hash(raw),
          fingerprint: String.slice(raw, -6, 6)
        },
        action: :issue,
        actor: actor
      )

    {key, raw}
  end

  def authenticate_key(raw, required_scope) when is_binary(raw) do
    key =
      ApplicationKey
      |> Ash.Query.filter(key_hash == ^hash(raw))
      |> Ash.read_one!(authorize?: false)

    with %{revoked_at: nil} = key <- key,
         true <- DateTime.compare(key.expires_at, DateTime.utc_now()) == :gt,
         true <- is_nil(required_scope) or required_scope in key.scopes,
         user when not is_nil(user) <- Ash.get!(App.Accounts.User, key.user_id, authorize?: false),
         true <- not is_nil(App.Accounts.active_user(user)),
         {:ok, %Application{} = application} <-
           Ash.get(Application, key.application_id, actor: user),
         true <- application.user_id == user.id do
      {:ok, %{user: user, key: key, application: application}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authenticate_key(_, _), do: {:error, :unauthorized}
  defp hash(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
end
