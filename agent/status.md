# File browser milestone status

Completed (2026-11-13):

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

Remaining:

- v1 SDK compatibility (current API is v2; `sdk_v1_compatible: false`).
- Image transforms and previews.
- Imports from v1 or remote buckets.
- Durable reconciliation of interrupted writes (orphan objects possible).
- Storage quotas.
- Backups and transfers.
- Production verification (HTTPS, DATABASE_URL, secrets, persistent vault key,
  real SMTP/GitHub credentials, no real buckets in automated tests).

Verification: 91 Elixir tests, 13 JavaScript tests, asset build and Ash schema checks.
Real-bucket and browser visual checks remain unverified.
