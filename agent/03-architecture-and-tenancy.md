> Historical reference — superseded 2026-11-14 by the [active v2 roadmap](01-replacement-plan.md). V1 compatibility and workspace/legacy-auth requirements in this document are not planned work.

# Architecture and tenant model

## Domain boundaries

| Domain | Planned resources / responsibilities |
| --- | --- |
| `App.Accounts` | Global User, authentication Token, OAuthIdentity, password actions, OTP challenge if needed, session/security lifecycle |
| `App.Workspaces` | Tenant, TenantMembership, Invitation, Application, ApplicationMembership, scoped ApplicationApiKey |
| `App.Storage` | StorageConnection, StoragePreference, Blob, BlobVariant, FileEntry, Folder, upload lifecycle and delivery |
| `App.Operations` | Transfer, TransferItem, BackupRun, BackupItem, AuditEvent, usage aggregates; durable worker integration |
| `App.Platform` | Operator-only signup/storage defaults and deployment-level controls |

Domain names are proposed. Use `App.Workspaces.Application` to avoid confusing the
resource with the OTP `App.Application` supervision module. Avoid duplicating
business logic between LiveView, JSON API, and legacy controllers; all invoke
shared authorized Ash actions. Binary uploads and streaming use controllers and
backend modules around those actions, not giant JSON payloads.

## Resource outline

- **User:** UUID, normalized unique email, profile, confirmation state, nullable
  password hash, operator role, ban state. Global identity, not tenant-owned.
- **OAuthIdentity:** user, provider, provider subject, minimal metadata; unique
  provider+subject. Keep OAuth tokens only if an actual feature needs them.
- **Tenant:** UUID, name, slug, lifecycle state. Creator becomes owner in one
  transaction; owner access comes from membership, not a client-supplied owner ID.
- **TenantMembership:** tenant/user, role, status; unique pair; last active owner
  cannot be removed or demoted. Soft-deleted users cannot retain usable access.
- **Application:** tenant, name, slug unique within tenant, default location, status.
- **ApplicationMembership:** tenant, application, user, viewer/editor/manager role.
  Used for limited access; does not implicitly grant all tenant applications.
- **Invitation:** tenant, optional application, role, intended verified email,
  hashed single-use token, expiry, accepted/cancelled timestamps. Acceptance checks
  current inviter authority and cannot escalate the requested grant.
- **ApplicationApiKey:** tenant/application, issuer, name, prefix/fingerprint,
  hash/format version, explicit scopes, expiry/revoked state, last-used timestamp.
  No plaintext reread action. New keys must not be scaffold-wide user credentials.
- **StorageConnection:** tenant, provider, endpoint/bucket/region/addressing,
  delivery mode, encrypted secret, encryption version, enabled state.
- **Blob/BlobVariant:** tenant/location, immutable object key and source-location
  snapshot, digest, size/content type/dimensions, processing state. Dedup uniqueness
  includes tenant + location + digest; use PostgreSQL bigint for byte sizes.
- **FileEntry:** tenant/application, blob, folder, original name, tags, star state,
  logical public ID/legacy alias, timestamps, archived state. A copy creates a new
  entry; a move preserves entry identity. Archived entries still count as references.
- **Folder:** tenant/application, parent, name, archived state. Reject parent cycles,
  cross-application parents, and ambiguous restore/name conflicts.
- **Job/Audit:** tenant/application context where applicable, initiating actor/key,
  operation metadata, state, dedupe/idempotency key, timestamps. Worker system
  tables and platform events are global but never directly customer-readable.

## Tenancy enforcement

Use Ash attribute multitenancy on tenant-owned resources with `tenant_id`,
`global? false`, and no tenant attribute in public `accept`. Global User/Token
resources stay outside tenant scoping. Tenant and membership bootstrap require
explicit policy design so resolving membership does not depend on an untrusted
active-tenant cookie.

For every request/event:

1. Authenticate the user or key using the correct credential class.
2. Resolve the requested tenant from the route or verified key claim/mapping.
3. Load active membership/application grant through a trusted resolver; a route
   slug, header, or session preference is a selector, never authorization.
4. Set both actor and tenant for Ash actions; derive application scope server-side.
5. Reject any record/relationship whose tenant/application differs, with composite
   database constraints where possible. UUID guessing must not reveal existence.

The tenant/app route is explicit, e.g. `/dashboard/t/:tenant_slug/applications/:id`.
Legacy dashboard URLs may redirect to the active personal tenant. Revalidate on
LiveView mount and each sensitive action; clear stale assigns on switch. Use a
membership/access version or invalidation notification so removal does not leave
an already-mounted LiveView authorized. PubSub topics, cache keys, object prefixes,
exports and job payloads include tenant/application identity.

API-key storage requests derive tenant/application from the key. Never trust an
`applicationId` or `tenant_id` supplied by the browser to widen a credential.
New browser tokens include tenant, application, scopes, origins, expiry and ID;
legacy token compatibility resolves the application to its tenant server-side.
Workers recheck current permissions or an explicitly documented service grant;
never replay serialized actor structs or accept arbitrary jobs from customer APIs.

## Access matrix

| Action | Tenant owner/admin | Application manager | Editor | Viewer | Platform operator |
| --- | --- | --- | --- | --- | --- |
| View tenant identity and own membership | Yes | Yes | Yes | Yes | Explicit support access only |
| List all tenant applications | Yes | Assigned apps | Assigned apps | Assigned apps | Explicit audited support access |
| Manage tenant members/settings/connections | Yes, owner-only ownership transfer | No | No | No | Operator defaults only by default |
| Manage an assigned application's settings/keys | Yes | Yes, within allowed scopes | No | No | No implicit content access |
| Browse assigned files | Yes | Yes | Yes | Yes | No implicit content access |
| Upload/rename/move/trash in assigned app | Yes | Yes | Yes | No | No implicit content access |
| Purge files / run tenant transfers | Yes | App-only if explicitly granted | No | No | Emergency audited workflow only |
| Change signup policy / ban users | No | No | No | No | Yes |

Application keys receive only their explicit scopes and application. Issuers cannot
grant beyond their own effective rights; membership removal, tenant suspension,
or a ban must disable effective credentials according to a documented policy.
Invitations do not imply access until accepted by the verified intended user.

## Migrating v1 access without widening it

Create a personal tenant for each owner. Applications and owner storage move to
that tenant. An existing app member receives restricted tenant membership plus
only their explicit application grant. Do not convert every member into a
workspace-wide viewer/admin. If v1 owner fields conflict or an app references
another owner's location/blob, quarantine that import item for resolution.
Never merge tenants on matching display names or slugs.

## Required isolation tests

Two tenants, two apps per tenant, one shared user, a removed user, a banned user,
and keys/tokens of each scope. Exercise read/get/list/aggregate, create/update,
relationship changes, destructive actions, presigned content, import/export,
workers, subscriptions and cache hits. Also test same-tenant users with different
application grants. No-tenant actions must fail on tenant-owned resources.
Tenant filters do not replace action policies; both must be tested.

Reference: [Ash multitenancy](https://hexdocs.pm/ash/multitenancy.html).
