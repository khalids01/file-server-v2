# Storage milestone

User request: continue after the application ownership/UI work with local and S3
storage, following v1's settings/browser separation.

Delivered: application-owned immutable S3 connections, AES-GCM encrypted
credentials, operator environment configuration import, local default destination,
async connection checks, five-file LiveView upload batches, enforced size limits,
private attachment downloads, confirmed deletion, real file counts, and preserved
original destinations when changing an app's default.

Routes: `/dashboard/applications/:id` for settings/connections,
`?tab=files` for the file browser, `/files/:id/download` for owner-session downloads.
Run `mix ecto.migrate` to create `storage_connections`, `stored_files` and the
application's nullable default destination reference. Back up the database,
local storage volume and persistent vault key together.

Verification: run `mix precommit`, `mix assets.build`, `mix ash.codegen --check`,
and `node --test test/js/*_test.mjs`. Storage tests exercise actual local filesystem
I/O and the LiveView/browser-session file flow. S3 requests use Req.Test with an
in-memory bucket: SigV4 headers, streamed object data, connection probes, failure
handling and destination retention are verified without accessing real buckets.
Endpoint allowlisting, size limits, symlink/path rejection, bans and ownership
boundaries are tested. A live provider test still requires configured credentials.

Next: paginated/searchable file browser, storage quotas and durable reconciliation
for interrupted writes; then v1-compatible SDK file APIs and imports. No existing
v1 files are migrated automatically. Transforms/previews, multipart resumable
uploads, remote bucket browsing/import, public links, backups/transfers and
credential rotation are not part of this slice. The subsequent file API milestone adds `/api/v2/files`; see [the API guide](../docs/file-api.md). `/api/v2/application` now reports v2 storage readiness and explicitly marks v1 SDK compatibility as false.
