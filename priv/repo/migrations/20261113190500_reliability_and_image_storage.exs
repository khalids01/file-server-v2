defmodule App.Repo.Migrations.ReliabilityAndImageStorage do
  use Ecto.Migration

  def up do
    create table(:account_storage, primary_key: false) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :quota_bytes, :bigint, null: false, default: 5_368_709_120
      add :used_bytes, :bigint, null: false, default: 0
      add :reserved_bytes, :bigint, null: false, default: 0

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create constraint(:account_storage, :account_storage_used_nonnegative,
             check: "used_bytes >= 0"
           )

    create constraint(:account_storage, :account_storage_reserved_nonnegative,
             check: "reserved_bytes >= 0"
           )

    create constraint(:account_storage, :account_storage_quota_nonnegative,
             check: "quota_bytes >= 0"
           )

    alter table(:stored_files) do
      add :status, :text, null: false, default: "ready"
      add :processing_state, :text, null: false, default: "not_applicable"
      add :processing_error, :text
      add :reserved_bytes, :bigint, null: false, default: 0
      add :upload_operation_id, :text
      add :pending_object_keys, {:array, :text}, null: false, default: []
      add :delete_requested_at, :utc_datetime_usec
      add :delete_attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :width, :integer
      add :height, :integer
      add :pixel_count, :bigint
      add :source_format, :text
      add :ready_at, :utc_datetime_usec
      add :processing_generation, :integer, null: false, default: 0
    end

    create table(:stored_file_variants, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :file_id, references(:stored_files, type: :uuid, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :object_key, :text, null: false
      add :content_type, :text, null: false
      add :size, :bigint, null: false
      add :width, :integer
      add :height, :integer
      add :status, :text, null: false, default: "ready"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:stored_file_variants, [:file_id, :name])
    create index(:stored_files, [:status])
    create index(:stored_files, [:application_id, :status])
    create index(:stored_files, [:processing_state])
    create index(:stored_files, [:user_id, :status])

    execute("""
    INSERT INTO account_storage (user_id, quota_bytes, used_bytes, reserved_bytes)
    SELECT u.id, 5368709120,
           COALESCE(f.file_bytes, 0) + COALESCE(v.variant_bytes, 0),
           0
    FROM users u
    LEFT JOIN (
      SELECT user_id, COALESCE(SUM(size), 0) AS file_bytes
      FROM stored_files
      WHERE status = 'ready'
      GROUP BY user_id
    ) f ON f.user_id = u.id
    LEFT JOIN (
      SELECT sf.user_id, COALESCE(SUM(sfv.size), 0) AS variant_bytes
      FROM stored_file_variants sfv
      JOIN stored_files sf ON sf.id = sfv.file_id
      WHERE sf.status = 'ready' AND sfv.status = 'ready'
      GROUP BY sf.user_id
    ) v ON v.user_id = u.id
    ON CONFLICT (user_id) DO NOTHING
    """)

    execute("""
    UPDATE stored_files
    SET ready_at = created_at
    WHERE status = 'ready' AND ready_at IS NULL
    """)
  end

  def down do
    drop_if_exists index(:stored_files, [:user_id, :status])
    drop_if_exists index(:stored_files, [:processing_state])
    drop_if_exists index(:stored_files, [:application_id, :status])
    drop_if_exists index(:stored_files, [:status])
    drop_if_exists unique_index(:stored_file_variants, [:file_id, :name])
    drop table(:stored_file_variants)

    alter table(:stored_files) do
      remove :processing_generation
      remove :ready_at
      remove :source_format
      remove :pixel_count
      remove :height
      remove :width
      remove :last_error
      remove :delete_attempts
      remove :delete_requested_at
      remove :pending_object_keys
      remove :upload_operation_id
      remove :reserved_bytes
      remove :processing_error
      remove :processing_state
      remove :status
    end

    drop table(:account_storage)
  end
end
