# Storage and image milestone status

Completed (2026-11-14):

- Auth: GitHub and email one-time-code sign-in, no passwords, ban rechecks,
  operator admin dashboard.
- Applications: user-owned applications, scoped API keys, application dashboard UI;
  no workspace layer.
- Storage: private local disk and S3-compatible destinations, encrypted S3
  credentials, uploads (max five at a time), private downloads, confirmed deletion,
  destination retention for existing files.
- API: scoped `/api/v2/files` routes and `/api/v2/application` reporting v2
  readiness with `sdk_v1_compatible: false`; keys are server-side only.
- Browser: `?tab=files` is a searchable, sortable, paginated private file browser.
  `App.Storage.files_page/3` applies ownership-scoped filtering (actor + application_id),
  clamps pages and totals reflect the active search. 25 files per page, stable
  created_at/id, filename/id, size/id ordering. Search, sort, page and tag filters
  persist in the URL; upload/delete clamp the current page and keep filters. No native
  selects/dialogs; shared Select and Input components are used. `App.Storage.files/2`
  remains for existing callers.
- Tags: file metadata tags (max 20, trimmed/non-empty, deduplicated, <=64 chars and
  <=256 UTF-8 bytes, no control chars/newlines). v2 upload accepts optional multipart
  `tags` JSON; `PATCH /api/v2/files/:id` requires `files:write`, validates actor +
  application + file scope (including same-owner cross-app denial), authenticates before
  bounded JSON parsing, rejects unknown JSON fields/oversize/malformed tags, and only
  updates metadata. `GET /api/v2/files` supports strict AND `tags[]` filtering and
  includes `tags` in metadata. Tag matching/deduplication ignore case while preserving display spelling. Dashboard file browser shows badges, shared tag edit
  dialog (one-tag-per-line textarea), and tag filtering preserving search/sort/page.
  No v1 SDK compatibility claims.

- Reliability/images: account-wide quota reservations, tracked pending writes and durable Oban cleanup/reconciliation; isolated Image/Vix native previews with orientation, metadata stripping and no upscale; private session and scoped API variants, dashboard previews/status/retry and account usage. See [the guide](../docs/storage-reliability-images.md) for deployment and resource limits.

- File management: URL-persisted grid/list, reusable private previews/placeholders, file details, current-page multi-select, confirmed bulk delete and add/remove/replace tags with partial errors, per-file upload outcomes/reselection, and clipboard feedback. See [the guide](../docs/file-management.md).

- Usage/operations: live application Usage & recovery tab, account/card totals, scoped usage API, queued recovery controls, generic liveness/readiness probes and operator backup tool. PostgreSQL/local backup/restore rehearsal passed. See [operations](../docs/operations.md).

V1 compatibility is explicitly out of scope; the API remains independently versioned v2.

Remaining:

- Real-provider staging and production monitoring/backup scheduling. Sharing is deferred until needed.
- Imports from v1 or remote buckets.
- Backups and transfers.
- Production verification (HTTPS, DATABASE_URL, secrets, persistent vault key,
  real SMTP/GitHub credentials, no real buckets in automated tests).

Verification: 150 Elixir tests, 16 JavaScript tests, asset build and Ash schema checks.
Real-bucket and browser visual checks remain unverified.

## Event-driven refresh and verification — 2026-11-21

Recurring SQL came from DashboardLive polling every three seconds. An initial
30-second idle backoff was superseded by owner-scoped Ash/Phoenix PubSub
invalidations for files, applications, API keys and connections. Storage's
existing post-transaction notification delivery is retained; a 25 ms one-shot
debounce combines bursts. No recurring dashboard polling remains. Backend
changes refresh private file details and usage; reads recheck active ownership.
Multi-node deployments require Phoenix clustering. Direct SQL writes require a
manual reload because they bypass resource notifications.

Verified the image upload → generated preview → authenticated download → tags →
failed delete → cleanup recovery workflow with real local files/native image
processing and LiveView integration tests. Added a Node example client and a
real loopback HTTP test with separate read/write/delete/revoked keys.

Compared v1 S3 connection source without reading credentials or accessing data.
V2 already supports dashboard-created encrypted iDrive e2 connections under
Application → Settings → Connect S3 storage. V1 tests before saving; v2 saves,
selects the destination, then offers Test current storage. Existing simulated
S3 tests verify the dashboard flow and signed I/O. No new compatibility layer
or provider feature was added.

Browser tool returned "browser access host is unavailable"; desktop/mobile
light/dark visual QA remains blocked. Real iDrive e2 testing awaits a dedicated
test application and authorized isolated provider resources; no real bucket
or v1 data was touched.

Command Code DeepSeek V4.1 Flash wrote the example client/API documentation and
ran syntax, missing-key and simulated-response checks. Its initial high-effort
PubSub run produced no edits and was stopped; Codex implemented/reviewed PubSub
and ran the real isolated workflow/API checks. Full verification recorded below.

Final verification: `mix precommit` passed (128 Elixir tests), 16 JavaScript tests
passed, assets built, and `mix ash.codegen --check` passed. Disposable PostgreSQL
was started for these checks and stopped afterward. Existing local config/dev.exs
changes were preserved and excluded from the commit.


## Global Files and Storage navigation — 2026-11-22

Added sidebar Files and Storage routes. Global Files shares the existing scoped
pagination/filtering implementation, adds an application filter and app labels,
and supports private details/downloads, tag editing and confirmed deletion.
PubSub updates reauthorize reads and refresh/close open details; navigation wins
over pending refreshes. Upload/bulk management remains inside each application.

Storage catalogs each owned application's local namespace and existing S3
connections, with read-only physical object/folder browsing and pagination.
Connection creation/testing remains in application settings, linked from cards.
S3 listing is prefix-scoped, signed and bounded; provider XML uses SAX with
DTD/entity rejection. Local paths reject symlinks and traversal. No raw-object
mutations, v1 access or real provider calls were performed.

Roles remain regular user and operator; `/dashboard/admin` and its sidebar link
are operator-only. Operators do not gain cross-user file/storage access.

Command Code DeepSeek V4.1 Flash implemented Global Files and its review fixes
(14 focused tests passed) and drafted S3 listing. The storage run spent excessive
time in discovery and reached its narrowed turn cap; Codex reviewed/corrected
parsing and completed browser integration/security tests. Full checks recorded
below. Browser access host remains unavailable; real iDrive verification pending.

Final checks passed: `mix precommit` (147 Elixir tests), 16 JavaScript tests,
`mix assets.build`, `mix ash.codegen --check`, and `git diff --check`. Tests used
only disposable PostgreSQL on localhost:5434, temporary local files and Req.Test
S3 responses. The disposable DB was stopped afterward; existing config/dev.exs
changes remain local and excluded from the milestone commit.


## Storage connection creation entry point — 2026-11-22

Added a prominent Connect S3 storage button and creation dialog directly to the
Storage page. The form selects an owned application, reuses the existing encrypted
connection service, and immediately shows the saved drive. Public fields survive
validation errors; credentials are not retained in form assigns or rendered back.
An empty account gets an application-creation link. Saving does not contact the
provider or change the default upload destination; application settings still
provide destination selection and connection testing. Added three LiveView tests
for successful encrypted creation, invalid/foreign-app rejection and empty state.

Verified: 150 Elixir tests through `mix precommit`, 16 JavaScript tests, asset
build and Ash codegen check passed. Used only disposable PostgreSQL and fixture
credentials; no provider access. Browser visual verification remains unavailable.
