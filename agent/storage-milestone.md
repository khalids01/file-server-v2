> Historical reference — superseded 2026-11-14 by the [active v2 roadmap](01-replacement-plan.md). V1 compatibility and workspace/legacy-auth requirements in this document are not planned work.

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

Browser milestone (2026-11-13): the `?tab=files` view is now a searchable,
sortable, paginated private browser. `App.Storage.files_page/3` validates
page/sort/search, clamps out-of-range pages, filters by filename and performs
ownership-scoped `application_id` filtering with Ash actor authorization; totals
reflect the filter. Files page at 25 per page with stable `created_at/id`,
`filename/id`, `size/id` ordering. Dashboard filters, sort and page persist in
the URL; upload/delete clamp the current page and preserve filters; empty-search
and pagination states are rendered; no native controls or confirmation dialogs
were added. `App.Storage.files/2` remains for existing callers.

Remaining: v1 SDK compatibility, tags/labels, image transforms/previews, imports
from v1/remote buckets, transfers, durable reconciliation of interrupted writes,
storage quotas, backups, production verification.

Next: storage quotas and durable reconciliation for interrupted writes; then
v1-compatible SDK file APIs and imports. No existing
v1 files are migrated automatically. Transforms/previews, multipart resumable
uploads, remote bucket browsing/import, public links, backups/transfers and
credential rotation are not part of this slice. The subsequent file API milestone adds `/api/v2/files`; see [the API guide](../docs/file-api.md). `/api/v2/application` now reports v2 storage readiness and explicitly marks v1 SDK compatibility as false.
