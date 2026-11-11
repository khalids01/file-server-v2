defmodule App.Accounts.OtpChallengeRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "otp_challenges" do
    field :purpose, :string
    field :identity, :string
    field :code_digest, :string
    field :attempts, :integer
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :request_ip, :string

    timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    cast(record, attrs, [
      :id,
      :purpose,
      :identity,
      :code_digest,
      :attempts,
      :expires_at,
      :consumed_at,
      :revoked_at,
      :request_ip
    ])
  end
end
