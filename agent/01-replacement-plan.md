# Replacement plan

Auth/theme update, 2026-11-12: only GitHub and email OTP are in scope for user
sign-in. Password, magic-link and personal API-key sign-in requirements below are
superseded by [04-authentication.md](04-authentication.md). Integration keys remain
required. The UI now uses shadcn-style components and light/dark/system themes.

## Outcome and scope

Deliver a self-hostable Phoenix LiveView + Ash replacement for Serve v1 with:

- GitHub OAuth, email/password, emailed OTP, existing magic links, and API keys.
- Real tenant isolation, memberships, roles, application access, and switching.
- A product dashboard covering applications, keys, files, storage, jobs, settings,
  profile, usage, audit events, and operator user management.
- Local and S3-compatible storage, image processing, stable media delivery, file
  management, durable transfers/backups, and recoverable Trash.
- Existing `/api/v1` SDK behavior and required legacy media URLs preserved.
- A rehearsed, resumable migration of existing accounts, metadata, and bytes.

Replacement means behavior and data compatibility, not just visual similarity.
Ash Admin remains an internal development tool; the product dashboard is built
with LiveView, Ash forms/actions, and the project's Tailwind components.

## Decisions proposed for the first implementation

| Topic | Planned default | Reason |
| --- | --- | --- |
| Tenant | A workspace containing applications | Supports both personal use and teams |
| Existing owner | One personal workspace per v1 owner | Preserves the current owner boundary |
| Authentication identity | Global user with multiple tenant memberships | One login can access several workspaces |
| Tenant data | PostgreSQL attribute multitenancy with `tenant_id` | Explicit scoping and one schema to operate |
| Product UI | Phoenix LiveView | Uses the chosen stack without a second frontend app |
| Existing clients | Keep `/api/v1`; add JSON API alongside it | Ash JSON API's envelopes are not the SDK contract |
| File identity | Separate logical FileEntry from stored Blob | Preserves v1 deduplication and application links |
| Jobs | PostgreSQL-backed durable jobs, preferably Oban | Transfers must survive restarts; one durable scheduler |
| Legacy credentials | Separate verifier/import path, then rotate | Existing hashes cannot become Ash-format keys |
| Cutover | Maintenance window, one active writer | Avoids unverified dual-write behavior |
| New additions | Email OTP and passwords are required before release | Explicit user requirement, not optional follow-up |

These are implementation defaults, not assertions that v1 already contains them.
No billing, payment processing, custom-domain tenancy, or tenant database-per-schema
is required for the first replacement. Private sharing, advanced search indexing,
and new video transcoding are outside parity unless separately requested.

## Delivery phases and exit gates

### P0 — Freeze contracts and validate the design

Inventory all API routes and SDK fixtures, v1 access rules, storage semantics,
configuration, and deployment requirements. Confirm authentication dependency
support, password/OTP integration, image library, S3 client, and worker choice
with small isolated experiments. Produce resource diagrams, route contracts,
a version/advisory decision record, and a migration manifest format.

**Gate:** every item in the parity matrix has a task and acceptance check; no
unresolved authentication architecture or tenant ownership ambiguity remains.
No production credentials or deployment are required to complete this design.

### P1 — Tenant boundaries and authorization

Create Tenant, TenantMembership, Application, ApplicationMembership, and policy
helpers. Add trusted tenant resolution to HTTP, LiveView, API keys, jobs, and
PubSub. Add a tenant-aware application-key model; classify the scaffold's existing
personal keys so they cannot become unrestricted storage credentials.

**Gate:** cross-tenant reads, mutations, associations, exports, and subscriptions
fail in tests, including forged tenant IDs and stale memberships. One owner can
create two tenants, switch them, and see separate applications.

### P2 — Complete authentication and account lifecycle

Add password registration/login, confirmation/reset/change, GitHub sign-in and
explicit account linking, and emailed OTP. Retain magic links and test all methods
together. Enforce signup policy, bans, verified-email rules, session revocation,
rate limits, and safe return paths. Build tenant onboarding and invitation acceptance.

**Gate:** all five credential paths work, linking cannot take over accounts,
OTP cannot be replayed or raced, and banned/removed users lose effective access.
OAuth unit/integration tests use a controlled provider; real staging GitHub login
is a later environment acceptance check, not a reason to skip automated coverage.

### P3 — Dashboard shell and application management

Build responsive navigation, tenant/application switchers, application CRUD,
role-based settings, key issuance/rotation/revocation, profile/security settings,
and operator-only user management. Add real overview queries and empty states.

**Gate:** a new user can onboard, create an application, issue a scoped key, manage
access, and use navigation on desktop/mobile. Permission checks exist in actions,
not just hidden navigation. Stats distinguish empty data from failed queries.

### P4 — Storage and the upload/delivery vertical slice

Implement Local/S3 backends, connection management and credential encryption,
streaming uploads, file/blob separation, deduplication, variants, content streaming,
range/conditional requests, default destination selection, and audited deletion.

**Gate:** dashboard + existing server SDK can upload, list, retrieve, and delete
real bytes. Local and S3 parity fixtures pass; simulated failures leave recoverable
state. Cross-tenant blobs, keys, caches, and signed URLs cannot leak.

### P5 — Full file manager and processing

Add folders, breadcrumbs, grid/list, search/sort/pagination, selection, upload
progress/cancel/retry, previews, rename, tags, stars, recent, crop, move/copy,
Trash/restore/permanent deletion, and reference-safe garbage collection.

**Gate:** all source behaviors in the file-manager inventory have UI and action
tests; restart/failure tests cover operations involving both database and storage.

### P6 — Durable jobs, backup/restore, and operations

Implement transfer inventories, verified moves/copies, retries, cancellation,
local-upload backups, metadata exports, restore collision checks, cache controls,
usage, audit browsing, deployment release tasks, health checks, and monitoring.

**Gate:** killed workers resume safely; checksum failures never delete sources;
restore rehearsal verifies database metadata AND bytes. Operators can see and
recover failed jobs. Resource limits are explicit and measured.

### P7 — Compatibility and migration rehearsal

Run the unchanged SDKs and compatibility fixtures against v2. Import an isolated
v1 snapshot with users, memberships, keys, folders, files, variants, connections,
Trash, preferences, and audit history. Preserve public aliases and re-encrypt
credentials. Rehearse final sync, failure rollback, and restart recovery.

**Gate:** all must-have parity rows pass; record counts, permissions, checksums,
URLs, SDK results, credentials, and operational recovery reconcile. No unresolved
critical security issue affects an enabled feature.

### P8 — Release and cutover

Complete staging OAuth/email/S3 checks, freeze v1 writes and workers, run final
verified import, switch traffic, and monitor. Keep v1 data and byte storage
recoverable until the signed-off retention window expires.

**Gate:** named release owner accepts the cutover report. If v2 has accepted new
writes, rollback requires a tested reconciliation path or forward recovery;
switching traffic back blindly is prohibited.

## Dependency order

P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8.
Contract fixtures and import-tool development start in P0/P1 and are exercised
throughout, rather than first appearing at the end. Storage failure tests are
added with each operation. Dates/effort estimates follow P0's evidence; the plan
does not make an unsupported delivery-date promise.

## Definition of replacement complete

All parity rows marked must-have have automated or recorded manual evidence;
all three newly requested login methods work; tenant isolation holds across UI,
HTTP, jobs, and storage; current SDKs work without client rewrites; migrated users
can sign in; existing known URLs still serve matching bytes; backup and rollback
rehearsals pass; deployment and operational runbooks are usable by another person.
