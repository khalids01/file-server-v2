# Ordered execution backlog

2026-11-12 override: password/magic-link/personal-key user auth tasks are cancelled,
not pending work. User auth is GitHub + email OTP only; SMTP and shadcn-style dark
mode are implemented. See current [authentication](04-authentication.md).

The first MVP is implemented; see [delivery status](mvp-delivery.md). P0 auth
experiments and P1/P2/P3 have partial implementation. No full phase is declared
complete: invitations/grants, linking/session UI and all storage/migration phases
remain outstanding. The table defines the complete replacement, not just the MVP.
These are reviewable units. Keep task IDs stable; attach actual commands/test reports and
source changes when completing a task. An item cannot be closed with placeholder
UI, mocked authorization, or an unexecuted migration.

| ID | Depends on | Deliverable | Completion evidence |
| --- | --- | --- | --- |
| P0-01 | — | Complete route/schema/UI/env/SDK parity register | Every current route classified; fixtures include successful and denied requests |
| P0-02 | P0-01 | Authentication compatibility experiment and dependency ADR | GitHub/password support, native-vs-custom OTP decision, session/revoke proof, advisory disposition |
| P0-03 | P0-01 | Resource graph, roles and legacy ownership mapping ADR | Two-tenant and restricted-app-member examples reviewed; migration conflicts defined |
| P0-04 | P0-01 | Storage/image/job experiment and state-machine ADR | Local + S3 streaming, bounded transform/native release build, crash recovery proof |
| P0-05 | P0-01,03 | Migration manifest/alias/key-format design | Example CUID→UUID maps, legacy key check, public URL fixtures and dry-run report |
| P1-01 | P0-03 | Tenant/membership/invitation/app resources and migrations | Constraints, last-owner protection, membership scope tests |
| P1-02 | P1-01 | Actor/tenant resolver for HTTP/LiveView/Ash | Forged selector, missing tenant, switch, removed-member tests |
| P1-03 | P1-02,P0-05 | App keys, key actor, scopes and legacy verifier | App binding, revocation, expiry, hash compatibility and no widening tests |
| P1-04 | P1-02 | Tenant isolation regression suite | Two tenants, two apps each, restricted member; CRUD/aggregate/relationship denial |
| P2-01 | — | Cancelled: password registration/login/reset is excluded by the current requirement | Old routes return 404; GitHub + OTP only |
| P2-02 | P0-02,P2-01 | GitHub identity + explicit linking/unlinking | Controlled OAuth tests, verified-email/missing-email/state/collision tests |
| P2-03 | P0-02,P1-01 | Email OTP issuance/verification/session integration | Test email, attempts/expiry/resend/rate limits, concurrent single success, signup policy |
| P2-04 | P2-01,02,03 | Unified sign-in/profile/security screens | Browser flow per method, accessible errors, safe redirect, no last-method unlink |
| P2-05 | P2-04 | Ban/signup/session/invitation enforcement | Every method and API actor covered; revoked sessions/memberships fail |
| P3-01 | P1-02,P2-04 | Dashboard shell and tenant onboarding/switch | Desktop/mobile keyboard navigation, no stale tenant data |
| P3-02 | P3-01,P1-03 | Applications/members/keys/settings screens | Create/edit/revoke/defaults with actual actions and permission tests |
| P3-03 | P3-01,P2-05 | Profile/operator user/settings screens | Self vs tenant admin vs platform operator denial cases |
| P4-01 | P0-04,P1-04 | Local/S3 backend and encrypted connections | Isolated provider tests, credential rotation, endpoint/SSRF/probe behavior |
| P4-02 | P4-01 | Blob/entry/variant/upload resources and lifecycle | Upload streaming, tenant dedup, reference constraints, failed-finalization recovery |
| P4-03 | P4-02 | SDK management + content/legacy delivery routes | Contract fixtures, GET/HEAD/Range, proxy/direct, legacy URL tests |
| P4-04 | P4-02,P0-04 | Image variants, transformations and cache | Format/dimension/quality/limits, concurrent cache work and invalid inputs |
| P4-05 | P4-03,P1-03 | Browser-token/CORS integration | Exact origins, lifetime/scopes, API-key Origin rejection, SDK browser tests |
| P5-01 | P4-03,P3-02 | File browser/folders/search/sort/selection | Paginated queries, hierarchy constraints, keyboard and mobile behavior |
| P5-02 | P5-01,P4-02 | Upload queue/previews/crop/rename/tags/stars | Progress/cancel/retry and file-type coverage; crop preserves source |
| P5-03 | P5-01,P4-01 | Move/copy and destination changes | Stable move IDs, new copy IDs, verified bytes, recoverable partial failures |
| P5-04 | P5-01,P5-03 | Trash/restore/purge/GC | Missing parents, duplicate names, shared/archived references, concurrency safety |
| P6-01 | P0-04,P5-03 | Durable transfer/backup inventory + worker queues | Kill/restart, retry, dedupe, checksum conflict, cancellation and leases |
| P6-02 | P6-01,P5-04 | Backup/export/import/restore screens and actions | Separate DB+bytes drill, backup dependency blocks deletion, restore conflicts |
| P6-03 | P4-04,P6-01 | Stats/audit/cache/jobs dashboard | Counts reconcile, tenant policy, progress/error/retry/cancel behavior |
| P6-04 | P6-02 | Production release, health/metrics/secrets runbooks | Container/release start, migration, native images, mail, restore and readiness checks |
| P7-01 | P0-05,P1-01 | Resumable v1 importer (built incrementally) | Dry-run, checkpoint/restart, idempotency, quarantine and report tests |
| P7-02 | P7-01,P6-04 | Full snapshot migration rehearsal | Accounts/access/keys/bytes/aliases/Trash/history reconciliation |
| P7-03 | P4-05,P5-04,P6-03 | End-to-end compatibility/security verification | Unchanged SDKs + legacy route suite; tenant/auth/storage regressions |
| P7-04 | P7-02,03 | Cutover/rollback rehearsal and release checklist | Single-writer freeze, final sync, pre-write rollback, post-write recovery decision |
| P8-01 | P7-04 | Staging environment acceptance | Real GitHub/email/S3 flows, load evidence, verified recovery and release owner |
| P8-02 | P8-01 | Controlled production cutover | Frozen v1, reconciled import, smoke checks, metrics and signed release report |

## Decisions to record during P0 (recommended defaults already in the plan)

- Confirm workspace tenancy, per-owner personal tenant migration and restricted
  imported membership. Any deviations must explain how access is preserved.
- Choose a compatible stable auth version or reviewed custom OTP on the current
  stable stack. No untested RC dependency leap.
- Choose durable scheduler, image backend and S3 client with release/runtime proof.
- Specify new-key expiry defaults and a legacy-key rotation window; do not expire
  all currently valid integration keys silently.
- Specify read-only maintenance duration using rehearsal evidence, source-byte
  retention, and acceptable post-write recovery/rollback strategy.
- Confirm whether every legacy internal dashboard endpoint must remain supported
  after the new dashboard replaces it; public URLs and SDK routes are mandatory.
- Record public-file semantics explicitly; private-by-default would be a separate
  product change requiring migration/compatibility decisions.

## External inputs needed later, not for this planning work

GitHub OAuth app credentials/callback registration, a verified mail sender/provider,
isolated staging S3/local destinations, a sanitized source snapshot, production
origin and deployment topology, and the person responsible for release acceptance.
Implementation can use local fixtures and fake provider endpoints until staging;
never substitute weaker auth or point tests at production because inputs are absent.

## Review checklist per implemented unit

- Resources and migrations reviewed together with snapshots; no accidental drops.
- Policies tested below UI and HTTP layers, including tenant/app relationship checks.
- Errors/retries/concurrent actions tested where they affect data or credentials.
- Relevant fixture/LiveView/storage tests and `mix precommit` pass.
- SDK/package verification runs when compatibility code/packages change.
- Backlog and runbook updated with observed results and remaining limitations.
- Secrets and real user data excluded from test fixtures, logs and documentation.

## Final release report template

Record source/target revisions, dependency versions/advisories, parity status,
auth/tenant isolation evidence, SDK contract results, migration reconciliation,
byte/checksum/URL checks, backup/restore evidence, performance measurements,
known limitations, cutover state, rollback feasibility and release acceptance.
A passing scaffold test suite alone cannot satisfy this report.
