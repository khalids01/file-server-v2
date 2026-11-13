> Historical reference — superseded 2026-11-14 by the [active v2 roadmap](01-replacement-plan.md). V1 compatibility and workspace/legacy-auth requirements in this document are not planned work.

# Storage, API, and dashboard plan

## Storage implementation boundaries

Define one StorageBackend behavior for bounded streaming put/get/head/delete/list,
copy where supported, and signed delivery. Local and S3 implement identical
failure/result semantics. Validate capabilities rather than pretending every
S3-compatible provider behaves identically. Start with Local plus an isolated
MinIO/S3 fixture; verify configured production providers during staging.

Uploads follow a state machine: authorize and resolve destination → allocate
pending upload → stream to temporary key while hashing/validating → finalize
object → commit Blob/FileEntry references → enqueue processing/backup → publish
completion. Database and object storage do not share a transaction. Use idempotent
steps, persisted state and a compensating cleanup/reconciliation job. Do not report
success before durable metadata references valid bytes. Limit upload size, count,
image pixel count, transform dimensions, concurrent work, request duration and
worker memory; never load arbitrary media fully into a LiveView process.

The file boundary includes documents/audio/video/archives, not just images.
Persist the exact location snapshot for each blob. Changing defaults affects
future uploads and never silently remaps existing bytes. Disabling a destination
blocks new writes, not historical reads. Refuse deleting/editing location identity
while referenced by live files, Trash, jobs or backups.

Encrypted connection secrets use the supervised vault with tagged key versions,
rotation, previous-key support and tamper-rejection tests. V1 uses connection/owner
binding in its encryption envelope; preserve equivalent binding through an
explicit envelope/context check, not just a swap to generic AshCloak encryption.
Never serialize plaintext or ciphertext envelopes to customers. Restrict saved
endpoints against SSRF, validate DNS on connection, enforce exact private-host
allowlists and redirect rules, and perform bounded probe cleanup.

For move/copy: persist an inventory, copy and checksum verify, commit new location
references, then remove eligible old objects. Retry each step safely. Copies get
new entry IDs. Moves retain entry ID and URLs. Refcount/dedup checks include
archived entries and outstanding backup dependencies. Use lock/transaction rules
and a pending-deletion grace period to prevent concurrent upload/purge races.

Use Ash Archival for logical FileEntry/Folder Trash with trash batch/restore
metadata; implement permanent purge explicitly. Never treat archiving the blob
itself as a complete deletion strategy. Authentication credentials retain their
own revocation semantics. Preserve v1's public-by-URL content behavior, including
Trash, until a separate private-delivery feature is designed and communicated.

## Content and image processing

- Preserve stable file entry IDs/legacy aliases and original/variant URL forms.
- Stream GET/HEAD, byte ranges and conditional requests; verify 200/206/304/416,
  Content-Type/Length/Range, validators and disposition against fixtures.
- Proxy private bucket reads by default; optional direct mode signs short-lived
  S3 URLs. Keep returned signed URLs out of persistent metadata and credentials
  out of redirects. Local delivery uses Serve.
- Choose the Elixir/libvips image integration through a measured P0 experiment.
  Include native build/release support, orientation, animation, supported formats,
  crop behavior, max dimensions and decompression limits. No unbounded arbitrary
  user-defined transform recipes.
- Normalize transformation inputs and include tenant, blob version, dimensions,
  quality and format in cache identity. Reject invalid inputs before work; rate
  limit cold transforms and cap variant count/cache bytes. Audit cache clearing.
- Keep checksums of source and transfer outputs; validate crop/variant correctness
  with dimensions, output decoding and representative visual fixtures.

## API compatibility

Expose Ash JSON API under `/api/json` for explicitly allowed resources/actions.
Use Phoenix compatibility controllers under `/api/v1` and required legacy paths,
calling the same Ash actions. Keep file bytes outside generic JSON:API serialization.
Do not expose User, Token, OAuthIdentity, secrets or worker tables broadly.

P0 creates a golden fixture corpus from `v1/npm_pkg/packages/contracts/src/index.ts`
and existing clients: capability discovery, storage locations, multipart upload,
list/get, content URLs, crops, deletion, browser-token minting and errors. Preserve
`{data, pagination}`, FileAsset fields, opaque strings, URL behavior, documented
error codes/statuses and request IDs. Capture request-ID behavior from the actual
handlers; do not assume every documented header currently exists.

Retain `Authorization` and `x-api-key` compatibility where v1 accepts them. API keys
are backend-only on the SDK surface; reject them with a browser Origin. Browser
tokens are short-lived and exact-origin/application/scope bound. CORS preflight
must not grant actual management authority. Scope checks are performed for each
action. Keep browser JWT signing secrets separate from session and vault secrets.

Existing non-expiring legacy keys and old file URLs get explicit compatibility
coverage. Tests must run the current server/client/react packages against v2 with
no fixture-only authentication bypass. If packages require a compatibility change,
version/publish them together per v1's package instructions and test upgrade paths;
never silently require all consumers to migrate at cutover.

## Product dashboard

Build one responsive sidebar/header layout with tenant switcher, application
context, user menu, breadcrumbs, loading/error states and accessible dialogs.
Use `Layouts.app`, shared input/icon components, Ash forms, LiveView streams for
lists and small JS hooks for upload progress/drag/drop/keyboard interactions.
Keep domain operations in actions and authorization server-side.

| Surface | Required behavior | Acceptance evidence |
| --- | --- | --- |
| Overview | Files, unique physical bytes incl. variants/Trash, applications, keys, job health, recent events | Stats reconcile with tenant records and dedup fixture; pagination/bounds |
| Applications | Create/edit/archive, tenant-scoped slug, default location, app members, keys and settings | Owner/manager permissions, cross-app denial, one-time key reveal |
| Files | Folder tree, breadcrumbs, back/forward, grid/list, query/search/sort, paginated selection | No unbounded loads; accessible keyboard/multiselect; persisted URL filters |
| Upload | Drop/picker, bounded queue (v1 defaults to three), progress, cancel/retry, destination/folder | Size/type errors; disconnect/retry; truthful cancellation semantics |
| Preview | Image/video/audio, crop as new file, download other types, copy stable URL | Range playback; safe content handling; original unchanged after crop |
| Organize | Rename/tags/star/recent, move/copy dialog and drag/drop, cross-location selection | Actions validate destination grant and parent; checksum-safe operations |
| Trash | Browse/restore/purge/empty with confirmation and job progress | Missing-parent restore to root; no bytes lost while another reference exists |
| Storage | Browse owned managed objects, destinations and delivery info | No arbitrary host filesystem/bucket traversal; no secrets displayed |
| Settings | Tenant members/invites, connections/backups, defaults and delivery; operator section separated | Credentials write-only; owner/admin controls; endpoint probes |
| Storage jobs | Paginated progress/items, retries/cancel, errors, export associations | Survives refresh/restart; clear partial-success/cancellation reporting |
| Cache | Scope/usage and clear controls | Only authorized tenant cache affected, events audited |
| Audit | Filtered actor/action/app/date records, paginated export | No credential/code leakage; retention configurable |
| Profile/security | Profile, password/reset, GitHub link/unlink, active sessions/logout-all | Recent-auth checks, cannot remove last sign-in method |
| Users/operator | Signup toggle, ban/unban, role controls, operational status | Platform role checked in actions; no automatic access to tenant files |

Tenant routes are explicit. Preserve familiar `/dashboard` entry points through
safe redirects. Keep connection/global storage configuration in Settings; Storage
is for browsing drives/files, matching v1's established navigation distinction.
Define human-readable empty states, form errors, toast behavior, focus restoration,
mobile navigation and destructive confirmation flows before calling a page done.

## Durable work and operations

Prefer Oban backed by the same PostgreSQL service, with bounded queues for uploads,
variants, transfer, backup, mail and cleanup. Confirm versions/licensing and add it
once during implementation. Persist domain TransferItem/BackupItem state rather
than assuming a scheduler job record is a recoverable inventory. Alternative
leased workers require equivalent proof and a recorded decision; do not operate
two competing schedulers for the same job.

Jobs need idempotency, retry/backoff, cancellation checkpoints, stale-lease
recovery, concurrency bounds, sanitized errors and tenant context. Backup status
must block source deletion where v1 does. JSON/SQL metadata exports do not include
uploaded bytes; UI and runbooks must say exactly what each backup protects.

Deploy a release with explicit migration task, readiness/liveness checks, database
connection limits, local persistent volume, worker configuration, reverse-proxy
upload/timeouts, mail delivery settings and native image dependencies. Record
metrics for auth failures/rate limits, upload throughput/error rates, storage
latency, memory, job lag/failures and delivery errors. Logs carry request/job/tenant
IDs without raw credentials, OTPs, OAuth secrets or signed URLs.
