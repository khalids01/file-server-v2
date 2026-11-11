defmodule App.Workspaces do
  use Ash.Domain, otp_app: :app
  import Ecto.Query
  require Ash.Query
  alias App.Workspaces.{Tenant, Membership, Application, ApplicationKey}

  resources do
    resource Tenant
    resource Membership
    resource Application
    resource ApplicationKey
  end

  def tenant_ids(actor) do
    if App.Accounts.active_user(actor) do
      App.Repo.all(
        from m in "workspace_memberships",
          where: m.user_id == type(^actor.id, Ecto.UUID),
          select: type(m.tenant_id, Ecto.UUID)
      )
    else
      []
    end
  end

  def role(actor, tenant) when is_binary(tenant) do
    if App.Accounts.active_user(actor) && Ecto.UUID.cast(tenant) != :error do
      App.Repo.one(
        from m in "workspace_memberships",
          where:
            m.user_id == type(^actor.id, Ecto.UUID) and m.tenant_id == type(^tenant, Ecto.UUID),
          select: m.role
      )
    end
  end

  def role(_, _), do: nil

  def tenants(actor), do: Tenant |> Ash.Query.sort(created_at: :asc) |> Ash.read!(actor: actor)

  def ensure_personal!(actor) do
    App.Repo.transaction(fn ->
      App.Repo.query!("SELECT pg_advisory_xact_lock($1::bigint)", [
        :erlang.phash2("onboarding:" <> actor.id)
      ])

      case tenants(actor) do
        [] -> create_tenant!(actor, "Personal workspace")
        [tenant | _] -> tenant
      end
    end)
    |> case do
      {:ok, tenant} -> tenant
      {:error, reason} -> raise "Workspace onboarding failed: #{inspect(reason)}"
    end
  end

  def create_tenant!(actor, name) do
    App.Repo.transaction(fn ->
      tenant = Ash.create!(Tenant, %{name: name}, actor: actor)
      # The only bootstrap bypass: the tenant just created by this actor.
      Ash.create!(Membership, %{user_id: actor.id, role: :owner},
        tenant: tenant.id,
        authorize?: false
      )

      tenant
    end)
    |> case do
      {:ok, tenant} -> tenant
      {:error, reason} -> raise "Workspace creation failed: #{inspect(reason)}"
    end
  end

  def applications(actor, tenant),
    do:
      Application |> Ash.Query.sort(created_at: :desc) |> Ash.read!(actor: actor, tenant: tenant)

  def issue_key!(actor, tenant, application_id, name, scopes) do
    # Resolve the application under the same tenant before creating its credential.
    Ash.get!(Application, application_id, actor: actor, tenant: tenant)
    raw = "sv2_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    key =
      ApplicationKey
      |> Ash.Changeset.for_create(
        :issue,
        %{
          name: name,
          application_id: application_id,
          scopes: scopes,
          key_hash: hash(raw),
          fingerprint: String.slice(raw, -6, 6)
        },
        actor: actor,
        tenant: tenant
      )
      |> Ash.create!()

    {key, raw}
  end

  def authenticate_key(raw, required_scope) when is_binary(raw) do
    # Trusted lookup by unguessable credential. All authority is revalidated below.
    key =
      ApplicationKey
      |> Ash.Query.filter(key_hash == ^hash(raw))
      |> Ash.read_one!(authorize?: false, context: %{private: %{all_tenants?: true}})

    with %{revoked_at: nil} = key <- key,
         true <- DateTime.compare(key.expires_at, DateTime.utc_now()) == :gt,
         true <- required_scope in key.scopes,
         user when not is_nil(user) <- Ash.get!(App.Accounts.User, key.user_id, authorize?: false),
         role when role in ["owner", "admin"] <- role(user, key.tenant_id),
         {:ok, application} <-
           Ash.get(Application, key.application_id, actor: user, tenant: key.tenant_id) do
      {:ok, %{user: user, key: key, application: application}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authenticate_key(_, _), do: {:error, :unauthorized}

  defp hash(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
end
