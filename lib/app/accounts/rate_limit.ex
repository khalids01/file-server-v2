defmodule App.Accounts.RateLimit do
  @moduledoc "Atomic shared-database throttling for password attempts."
  def allow_password?(email) do
    identity = email |> to_string() |> String.trim() |> String.downcase()

    digest =
      :crypto.mac(:hmac, :sha256, Application.fetch_env!(:app, :token_signing_secret), identity)
      |> Base.encode16(case: :lower)

    # Reserved settings keys are internal counters; no identity or credential is stored.
    %{rows: [[count]]} =
      App.Repo.query!(
        """
        INSERT INTO platform_settings (key, value, updated_at) VALUES ($1, '1', now())
        ON CONFLICT (key) DO UPDATE SET
          value = CASE WHEN platform_settings.updated_at < now() - interval '1 minute'
            THEN '1' ELSE ((platform_settings.value::integer) + 1)::text END,
          updated_at = CASE WHEN platform_settings.updated_at < now() - interval '1 minute'
            THEN now() ELSE platform_settings.updated_at END
        RETURNING value::integer
        """,
        ["rate:password:" <> digest]
      )

    count <= 10
  end
end
