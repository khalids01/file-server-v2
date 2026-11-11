defmodule App.Accounts.OtpChallenge do
  @moduledoc """
  Persists emailed one-time-code challenges.

  The low-entropy code is never stored directly: only an HMAC-SHA256 digest
  bound to the challenge purpose and normalized identity is persisted. The
  atomic consume/increment path lives in `App.Accounts.Otp` and uses row locks
  on this table so a correct code can succeed exactly once under concurrency.
  """

  use Ash.Resource,
    otp_app: :app,
    domain: App.Accounts,
    authorizers: [Ash.Policy.Authorizer],
    data_layer: AshPostgres.DataLayer

  postgres do
    table "otp_challenges"
    repo App.Repo
  end

  actions do
    defaults [:read, :destroy]
  end

  policies do
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :purpose, :string do
      allow_nil? false
    end

    attribute :identity, :ci_string do
      allow_nil? false
    end

    attribute :code_digest, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :attempts, :integer do
      allow_nil? false
      default 0
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :consumed_at, :utc_datetime_usec do
      allow_nil? true
    end

    attribute :revoked_at, :utc_datetime_usec do
      allow_nil? true
    end

    attribute :request_ip, :string do
      allow_nil? true
      sensitive? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end
end
