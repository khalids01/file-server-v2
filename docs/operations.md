# Operations and recovery

This milestone adds live usage/recovery UI, application-scoped usage API, health probes and an operator backup tool. It does **not** deploy the app, contact real buckets/SMTP/GitHub, schedule production backups or assert that production is ready.

## Dashboard and monitoring

Open **Application → Usage & recovery**. Totals come from stored-file and ready-variant records, not placeholder charts. Original bytes and preview bytes are separate; pending variants/uploads remain reserved. Counts include stored files awaiting deletion until cleanup actually succeeds. Pending-upload and recovery counts can overlap when a stale upload needs cleanup.

The issue list shows up to 25 oldest image failures, interrupted uploads and requested deletions/failed-write cleanup. **Retry recovery** queues existing jobs or reuses an already queued job. It does not claim that storage has been repaired. Usage/issues refresh every three seconds as workers finish; originals remain accessible after image failures. Raw storage errors, object keys and credentials are never shown. Account overview and application cards refresh from the same server records. Account quota remains shared across all applications.

`GET /api/v2/application/usage` requires a server key with `files:read`. It returns only that key's application metrics, never account-wide usage or other applications' filenames. It accepts no query parameters.

Monitoring endpoints (generic responses, no database or credential details):

- `GET /health/live`: 200 when the HTTP app responds.
- `GET /health/ready`: 200 when PostgreSQL is reachable, required storage/Oban tables exist and the Oban supervisor is running; 503 otherwise. Database checkout/query timeouts are bounded. This is not an SMTP/GitHub/S3 connectivity check and does not prove all migrations, native encoders or backup jobs are healthy.

Use HTTPS/proxy settings correctly in production. Do not disable TLS or trust arbitrary forwarded headers to make probes pass. Alert on readiness failures, repeated cleanup/image errors, disk exhaustion, database capacity and missing backup verification. Check process logs without exposing credentials. Image execution still requires Python 3, Elixir/Erlang, compatible Vix binaries and deployment memory/disk limits; see [image limits](storage-reliability-images.md).

## Consistent backup

Before backing up, stop **all** app instances and background workers (and any other writers). This keeps the PostgreSQL snapshot and local-file archive consistent. The tool requires `BACKUP_WRITES_PAUSED=yes` as an operator declaration; it cannot verify remote writers have stopped. Keep downtime until the backup has finished. Provider-side S3 backup/versioning is separate and must preserve objects referenced by the database.

The host needs Bash, Python 3, tar, sha256sum and PostgreSQL client tools compatible with the server. Docker mode instead runs pg_dump inside an explicitly selected Compose service.

Set connection values through your operator environment/secret manager (the script never reads `.env`). For host mode, set `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` and authentication through your normal libpq mechanism (for example a protected `.pgpass` or `PGPASSWORD`). Do not put passwords in command arguments or commit them. Then set:

```bash
export LOCAL_STORAGE_PATH=/var/lib/file-server/storage
export BACKUP_TARGET=/var/backups/file-server/backup-2026-11-14
export BACKUP_WRITES_PAUSED=yes
bash scripts/backup.sh
```

Choose a **new** backup target outside the local storage tree. Do not reuse an existing backup name. Optional Docker mode: explicitly set `BACKUP_DOCKER_SERVICE=db` and the appropriate `PGUSER`/`PGDATABASE`; the chosen service must already have local database authentication configured. Treat that as a deliberate choice of backup source.

The bundle contains `database.dump` (custom pg_dump), `local-storage.tar.gz`, `SHA256SUMS` and a scope note. Directories/files are private and the script refuses overwrites/recursive destinations. It does not follow local-file symlinks. Tar errors or changes during archiving fail the backup instead of reporting success. Store bundles on protected, encrypted storage with an off-host copy and a retention policy; private filesystem permissions alone are not encryption. Never serve the backup directory through Phoenix/static hosting. Root `backups/` is Git-ignored.

**Separately protect** the persistent vault key (`CLOAK_KEY` or `STORAGE_ENCRYPTION_KEY`), token/signing secrets and operator configuration. The tool intentionally excludes them. Without the original vault key, restored encrypted S3 connections cannot be decrypted. The database dump itself contains sensitive account/session data and encrypted connection records.

## Restore rehearsal and real restore

Verify `sha256sum -c SHA256SUMS` from the bundle first. Restore only into a fresh database and a fresh private local directory; never run a rehearsed command blindly against the live database. Restore database custom-format content with `pg_restore --no-owner --no-privileges -d NEW_DATABASE database.dump` using an appropriately authorized connection. Extract the local archive only into the fresh directory after inspecting/trusting the archive; restore directory/file permissions (700/600) and ownership for the app user.

Configure that isolated app with the restored database, local root and **matching vault key**; disable external mail/OAuth/bucket writes or use isolated provider credentials. Check migrations, stored file counts, ready-variant bytes, quota counters, originals/preview checksums and authorization. Restored pending jobs can resume when workers start, so review their destinations first. S3 restore requires the provider's matching object backup/version history; this bundle alone is insufficient. Only switch production after the isolated rehearsal and a deliberate cutover/rollback plan. Keep the old deployment/data recoverable.

A safe built-in rehearsal is available for the disposable development fixture only:

```bash
docker compose up -d db
DB_HOST=localhost DB_PORT=5434 mix test
python3 scripts/verify_backup_restore.py
```

The rehearsal insists on the Compose service mapped to `127.0.0.1:5434`, clones `app_test` into random temporary databases, seeds file metadata/accounting and local bytes, runs the actual backup tool, restores to a different temporary database/directory, checks bytes/counters/permissions and unsafe-target rejection, then removes its temporary databases/files. Run it when no tests are concurrently writing `app_test`. It never accepts a production URL or reads `.env`.

Verified in this milestone: real local uploads, isolated native image generation, API access, failed-delete accounting/recovery, usage UI updates, and this real PostgreSQL/local restore rehearsal. S3 signing/streaming/failure paths use isolated Req fixtures; a real provider bucket still needs explicit staging verification. Browser visual QA was unavailable. No production backup freshness is inferred or displayed.
