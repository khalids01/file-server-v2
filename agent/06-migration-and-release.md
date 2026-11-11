# Migration, compatibility, and release runbook design

## Preconditions

Use a separate v2 database and isolated rehearsal bucket/volume. Keep v1 schema,
metadata and source bytes intact. Do not run v2 Ash migrations against the Prisma
database. Capture source revision/schema version and a read-consistent snapshot.
No migration implementation or production operation is authorized by this plan.

The importer must support dry-run, validation-only, deterministic ID maps,
checkpoints/resume, idempotent rerun, per-record errors, reconciliation reports
and a manifest linking source snapshot to target run. Preserve original timestamps
and source IDs in mapping/alias tables; never silently coerce CUIDs into UUIDs.

## Mapping contract

| V1 | V2 mapping / treatment |
| --- | --- |
| User | Global User; source ID alias, email/profile, verified state with provenance; translate operator role and ban fields explicitly |
| Owner IDs | One personal Tenant + owner membership per owner, checkpointed idempotently |
| Application/members | Application under owner tenant; restricted tenant membership + app grants for members |
| Account | OAuthIdentity for verified provider mapping; no blind email linking; inspect any credential hashes before deciding import support |
| Session/verification/token | Do not import browser sessions or pending challenges; require new sign-in |
| ApiKey | Legacy-format verifier with imported SHA-256 digest, app/tenant binding, name, revoked and last-used state; new format issued separately |
| Image | Blob with source location snapshot, digest, dimensions/size/type and original key; preserve public filename aliases |
| ImageVariant | BlobVariant linked to blob, recorded object key, label/dimensions/size |
| ImageApplication | FileEntry with public ID alias, application/folder, name, tags, star, Trash batch/deletedAt and timestamps |
| Folder | Tenant/application tree with source alias and archived/trash data; detect cycles and orphan parents |
| StorageConnection | Tenant connection; decrypt using v1 envelope+binding and old key, then encrypt using v2 context/version |
| StorageSettings/Preference | Translate platform defaults and tenant backup preference; preserve built-in Default/Local meanings |
| StorageJob/StorageJobItem | Retain completed history where useful; drain/pause active jobs before final import; resume only with a tested job-state mapping |
| AuditLog | Read-only historical AuditEvent with legacy actor/app/key IDs mapped or retained as historical references |

V1 password login is disabled, but its Account schema contains a password column.
Inventory actual credential rows. Do not claim hash compatibility from a column
name; default to password setup/reset through verified email instead of forcing
an unsupported hash conversion. GitHub identities preserve provider subject IDs.
Imported users can use email OTP/magic link after mail delivery is verified.

## Import sequence

1. Snapshot schema/data and produce counts, ownership graph, byte manifest and
   source configuration inventory. Check for duplicate normalized emails, invalid
   roles, ownerless rows, cross-owner locations, orphan blobs/entries and tree cycles.
   Quarantine conflicts rather than granting broader access.
2. Create global identities and legacy ID maps; create personal tenants, then
   memberships/application grants. Validate access against v1 fixture expectations.
3. Import applications, destinations/defaults, then folder trees and encrypted
   connection settings using an isolated secrets channel. Never put keys or
   decrypted credentials in migration manifests/logs.
4. Import blobs/variants and entries, preserving logical vs physical identity,
   timestamps, tags/stars/Trash and source-location snapshots.
5. Migrate bytes with checksums. Rehearsal uses copied test bytes; production may
   retain immutable existing object keys with explicit manifests, or copy to new
   prefixes. Choose and rehearse the policy in P0. Local volume mount/path mapping
   is explicit. No migration may delete/rewrite source bytes during rehearsal.
6. Import legacy application keys, preferences, audit/history and safe job history.
   Do not reset revoked flags or manufacture key plaintext. Classify any existing
   scaffold v2 data separately so test/personal keys cannot become production keys.
7. Build URL aliases for entry IDs, legacy blob/filename routes, variants and
   required resize URL forms. Keep public origin/proxy routing compatible. Validate
   returned response URLs, not just database IDs.
8. Reconcile, export a machine-readable report, rerun importer to demonstrate no
   duplicate users/tenants/entries, then run SDK and authorization fixtures.

Legacy public media and private management data have different access semantics.
Content aliases must preserve known public URLs; metadata/listing must still be
application/tenant-authorized. Old URLs with IDs that refer to blobs rather than
entries require an explicit mapping policy based on real handler fixtures.

## Reconciliation evidence

Compare users, apps, effective membership grants, active/revoked keys, locations,
folders, entries incl. Trash, blobs, variants, byte totals, digest coverage, audit
history and timestamps. Logical entry count and unique physical byte total are
separate measures. Require all critical originals to have checksum evidence;
report missing/unreadable bytes and refuse cutover with unresolved discrepancies.
Test representative legacy URLs, variants, Range/HEAD, SDK uploads/deletes,
server keys and browser tokens. V1 browser tokens are short-lived; default to
expiry/draining and reissuance at cutover. If temporary validation is required,
retain strict legacy issuer/audience/origin/scope behavior and resolve the tenant
from the imported application, without reusing session signing secrets.

## Cutover rehearsal and release

1. Deploy v2 to staging with real OAuth app, test mail domain and isolated storage.
   Exercise all login methods and the permission matrix. Verify native image
   processing, backup/restore, migration release task and startup after restart.
2. Record measured upload/stream/transform load, worker memory/concurrency and DB
   limits using representative v1 file sizes. Set a cutover maintenance budget and
   acceptance thresholds from the results; do not invent latency guarantees.
3. Announce reauthentication and any key rotation policy. Prepare read-only/503
   maintenance responses, source backup and explicit owner/on-call responsibility.
4. Pause v1 writes, uploads, cleanup, transforms that write, backup and transfer
   workers. Drain in-flight requests/jobs and capture the final consistent snapshot.
5. Import/sync final metadata and bytes, verify the checkpoint and reconcile again.
   Verify key decryption/rotation and known public URLs before switching traffic.
6. Switch routing, start only v2 writers/workers, then smoke-test login, tenant
   switch, upload, list, content, transform, revoke and jobs using designated data.
7. Monitor delivery/auth failures, storage mismatches, job backlog and tenant access
   errors against agreed thresholds. Keep v1 read-only and preserve backups.

## Rollback rules

Before v2 accepts writes, roll back routing to the unchanged v1 source and workers
if reconciliation or smoke checks fail. Do not run both worker sets concurrently.
After v2 accepts writes, returning to v1 can lose new metadata, credentials and
objects. Choose forward recovery by default; rollback then requires an already
tested reverse-delta/reconciliation procedure covering new IDs, entries, secrets,
keys, memberships and deletes, followed by integrity checks. Record the decision
point and actual rollback scope in the release report. DNS/proxy reversal alone
is not a safe data rollback.

## Deployment handoff

Deliver production Compose/release instructions, migration command, environment
reference, verified mail/OAuth setup, operator bootstrap without automatic admin
signup, TLS/proxy configuration, private-endpoint allowlist, local volume backups,
database backups, secret/key rotation and restoration, restore drills, log/metric
locations, job recovery procedures and retention/decommission checklist. Delay
source deletion until a separately accepted retention period and recovery drill.
