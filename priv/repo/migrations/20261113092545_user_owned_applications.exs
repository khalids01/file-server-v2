defmodule App.Repo.Migrations.UserOwnedApplications do
  @moduledoc "Transfers existing applications to workspace owners before removing workspaces."
  use Ecto.Migration

  def up do
    # Preserve application IDs, key hashes, expiry and revocation state. No app or key is deleted.
    execute "ALTER TABLE workspace_applications ADD COLUMN user_id uuid REFERENCES users(id)"

    execute "UPDATE workspace_applications a SET user_id = w.owner_id FROM workspaces w WHERE w.id = a.tenant_id"

    execute "ALTER TABLE workspace_applications ALTER COLUMN user_id SET NOT NULL"

    # Multiple former workspaces may use the same slug. Keep the oldest and suffix
    # duplicates, checking for existing candidates so all applications survive.
    execute """
    DO $$
    DECLARE r record; candidate text; n integer;
    BEGIN
      FOR r IN SELECT id, user_id, slug FROM (
        SELECT id, user_id, slug, row_number() OVER (PARTITION BY user_id, slug ORDER BY created_at, id) AS position
        FROM workspace_applications
      ) duplicates WHERE position > 1 LOOP
        candidate := left(r.slug, 20) || '-' || replace(r.id::text, '-', ''); n := 0;
        WHILE EXISTS (SELECT 1 FROM workspace_applications WHERE user_id = r.user_id AND slug = candidate AND id <> r.id) LOOP
          n := n + 1;
          candidate := left(r.slug, 20) || '-' || replace(r.id::text, '-', '') || '-' || n::text;
        END LOOP;
        UPDATE workspace_applications SET slug = candidate WHERE id = r.id;
      END LOOP;
    END $$;
    """

    execute "UPDATE workspace_api_keys k SET user_id = a.user_id FROM workspace_applications a WHERE k.application_id = a.id"

    execute "DROP INDEX workspace_applications_unique_slug_index"
    execute "ALTER TABLE workspace_api_keys DROP COLUMN tenant_id"
    execute "ALTER TABLE workspace_applications DROP COLUMN tenant_id"
    execute "ALTER TABLE workspace_applications RENAME TO applications"
    execute "ALTER TABLE workspace_api_keys RENAME TO application_keys"

    execute "ALTER TABLE applications RENAME CONSTRAINT workspace_applications_pkey TO applications_pkey"

    execute "ALTER TABLE applications RENAME CONSTRAINT workspace_applications_user_id_fkey TO applications_user_id_fkey"

    execute "ALTER TABLE application_keys RENAME CONSTRAINT workspace_api_keys_pkey TO application_keys_pkey"

    execute "ALTER TABLE application_keys RENAME CONSTRAINT workspace_api_keys_user_id_fkey TO application_keys_user_id_fkey"

    execute "ALTER TABLE application_keys RENAME CONSTRAINT workspace_api_keys_application_id_fkey TO application_keys_application_id_fkey"

    execute "ALTER INDEX workspace_api_keys_unique_key_index RENAME TO application_keys_unique_key_index"

    create unique_index(:applications, [:user_id, :slug], name: :applications_unique_slug_index)
    drop table(:workspace_memberships)
    drop table(:workspaces)
  end

  def down do
    raise Ecto.MigrationError,
          "Workspace removal is irreversible. Restore a database backup to recover former workspace membership data."
  end
end
