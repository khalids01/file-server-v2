> Historical reference — superseded 2026-11-14 by the [active v2 roadmap](01-replacement-plan.md). V1 compatibility and workspace/legacy-auth requirements in this document are not planned work.

# V1 behavior and parity inventory

Evidence is from the checked-out source, not an audit of deployed production.
Paths below are relative to `../../v1/`. Implementation must inspect each full
handler and its tests before freezing exact behavior and all error/status cases.
Every row is required unless the release decision explicitly records otherwise.

| Area | Observed source behavior | Evidence | V2 target / phase |
| --- | --- | --- | --- |
| Email sign-in | Six-digit email OTP, 600-second expiry, three attempts, hashed storage | `src/lib/auth.ts` | Preserve email code flow, P2 |
| GitHub | Enabled when client ID/secret exist | `src/lib/auth.ts` | GitHub + safe identity linking, P2 |
| Password | Explicitly disabled in current v1 | `src/lib/auth.ts` | New required feature, P2 |
| Signup/admin | Global signup toggle, admin role, bans, expiry | `src/lib/auth-settings.ts`, `prisma/schema/auth.prisma` | Enforce at every registration path; operator controls, P2/P3 |
| Session | Better Auth sessions; 30-day expiry, weekly update age | `src/lib/auth.ts` | Deliberate new session policy, force sign-in on migration, P2/P7 |
| Ownership | Application owner plus members relation; several handlers filter owner | `prisma/schema/application.prisma`, `src/app/api/applications/` | Explicit tenants and role/application grants, P1 |
| Dashboard | Overview, applications/detail/keys, files, storage/detail, upload, cache, jobs, profile, users, settings | `src/app/dashboard/`, `src/features/dashboard/components/dashboard-sidebar.tsx` | Equivalent product navigation and authorized actions, P3–P6 |
| API keys | Application-bound `sk_live_` keys; SHA-256 hash, revoked flag, last-used timestamp; no automatic expiry | `src/lib/api-keys.ts` | Legacy verifier + scoped new keys; preserve old-key behavior during migration window, P1/P7 |
| Browser management | App-bound JWTs, exact allowed origins, scopes, 1–900 second lifetime; API keys rejected with Origin | `src/lib/v1-api.ts`, `src/app/api/v1/browser-tokens/route.ts` | Compatible browser-token boundary and CORS, P4/P7 |
| SDK API | `/api/v1/files`, details/content/crops, storage-locations, capabilities, browser-tokens | `src/app/api/v1/`, `npm_pkg/packages/contracts/src/index.ts` | Existing JSON contracts and opaque IDs, P4/P7 |
| Legacy API | Upload/images/img/name, image delete/crop, app/key APIs, stats, audit, file manager, connections, jobs, cache, manifest | `src/app/api/`, `docs/api.md` | Route-by-route compatibility register in P0; preserve required clients and public URLs |
| Storage selection | Environment Default, persistent Local, saved S3; per-application defaults | `docs/storage-and-file-manager.md`, `src/lib/storage/locations.ts` | Same resolution, retain recorded location for old bytes, P4 |
| Connections | Owner-bound, encrypted credentials, provider probe; restrict edits/removal while referenced | `src/lib/storage/connections.ts`, `src/lib/storage/secrets.ts` | Tenant-bound connections, no browser secret exposure, P4 |
| Endpoint security | Public endpoints by default, exact operator allowlist for private hosts, per-socket DNS checks | `src/lib/storage/endpoint.ts` | Revalidate DNS/socket destinations and redirect rules, P4 |
| Blob/entry split | Image blob + ImageApplication entry; metadata belongs to entry | `prisma/schema/application.prisma`, `docs/api.md` | Blob + FileEntry + variant model, P4 |
| Deduplication | Owner/location-scoped bytes, independent logical entries, shared references | `docs/api.md`, `src/lib/file-storage.ts` | Tenant/location-scoped dedup; never global content lookup, P4 |
| Public content | Stable entry URLs; public by possession; Trash does not revoke URLs | `docs/integration-guide.md`, `docs/storage-and-file-manager.md` | Preserve migrated public semantics; private access is a separate explicit future mode, P4/P7 |
| Media delivery | Proxy default, optional signed S3 redirect; Local streams; GET/HEAD and byte ranges | `src/lib/storage/delivery.ts`, `src/lib/storage/range.ts`, `src/app/api/v1/files/[id]/content/route.ts` | Contract + byte/range/header fixtures, P4 |
| Images | Variants, WebP optimization, on-demand size/quality, crops create new files | `src/lib/storage/image.ts`, `src/app/api/images/[id]/crop/`, `src/app/api/v1/files/[id]/crops/` | Bounded transforms and compatibility fixtures, P4/P5 |
| Manager | Folders, rename, tags, stars, recent, grid/list, search/sort, keyboard/multiselect, drag/drop, progress/cancel/retry | `src/lib/file-manager.ts`, `docs/storage-and-file-manager.md` | LiveView + upload hooks with accessible equivalents, P5 |
| Trash | Restore to prior folder or root; permanent delete only removes last reference | `src/lib/file-deletion.ts`, `docs/storage-and-file-manager.md` | Ash Archival on logical entries/folders + explicit purge workflow, P5 |
| Transfers | Durable job inventory, checksums, retry/progress, preserve move IDs, copy IDs change, no overwrite on conflicts | `src/lib/storage/jobs.ts`, `src/lib/storage/copy-verified.ts`, `prisma/schema/settings.prisma` | Durable jobs + TransferItem, P6 |
| Backup/restore | Metadata JSON/SQL distinction; optional asynchronous upload backups; pending backups block source removal | `docs/storage-and-file-manager.md`, `src/lib/storage/backup-queue.ts`, `src/app/api/file-manifest/` | Metadata and byte recovery treated separately, P6 |
| Operations | Cache management, usage stats, audit logs, production Compose and migration setup | `src/app/api/cache/`, `src/app/api/stats/`, `src/app/api/audit-logs/`, `docker-compose.production.yml` | Tenant/operator controls, release tasks and restore runbooks, P6 |
| Packages | Serve server/client/react integrations and contract tests | `npm_pkg/packages/`, `npm_pkg/README.md`, `docs/integration-guide.md` | Run existing packages unchanged against v2, P7 |

## Important distinctions

- V1 does not define Tenant or TenantMembership tables. Its current access model
  is based on users, owned applications, application members, and owner-scoped
  storage. Membership presence in the schema does not establish uniform member
  access in all routes; P0 tests must distinguish intended access from real behavior.
- `Image` is a legacy name: the contract covers images, video, audio, documents,
  archives, and other files. Do not implement an image-only replacement.
- The newly generated v2 user key is not equivalent to v1's application key.
- JSON API is additional functionality; swapping SDK response shapes for JSON:API
  would break existing clients.
- V1 documentation explicitly targets a fresh installation for its recent storage
  changes. V2 therefore needs its own importer; an existing v1 upgrade path cannot
  be assumed.

## Evidence to collect in P0

Create a fixture manifest with source revision, endpoint, method, auth class,
request example, response schema/status/headers, tenant expectations, reference
file/line, and associated test. Include all paginated/error cases. Run the v1
auth, storage, jobs, deployment and package tests only against explicitly isolated
test resources. Record discrepancies between documentation and executable source
as decisions rather than silently reproducing unsafe behavior.
