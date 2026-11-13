> Current architecture: User → Applications → Files/storage settings/API keys. Workspaces and memberships have been removed; older roadmap references below are historical. Local/S3 application file storage is implemented. See [storage-milestone.md](storage-milestone.md) for scope and remaining work.

# App v2 replacement planning

Prepared 2026-11-11. Status: **owner-workspace MVP implemented; full replacement still in progress**.

See [mvp-delivery.md](mvp-delivery.md) for the current testable slice and limitations.

Current auth/theme requirement (2026-11-12): GitHub + emailed one-time codes only,
SMTP delivery, shadcn-style components and light/dark/system themes. The earlier
password/magic-link/personal-key login plan is superseded. Application keys remain
backend integration credentials. See [authentication](04-authentication.md) and
the root README for current behavior.

Goal: replace the existing Serve v1 with one Phoenix/Ash application and preserve
working storage integrations.

Read in this order:

1. [Replacement plan](01-replacement-plan.md) — scope, phases, and release gates.
2. [V1 parity inventory](02-v1-parity.md) — observed behavior and its source.
3. [Architecture and tenancy](03-architecture-and-tenancy.md) — domains, resources, permissions.
4. [Authentication](04-authentication.md) — five login/credential methods and account lifecycle.
5. [Storage, API and dashboard](05-storage-api-dashboard.md) — customer-facing behavior.
6. [Migration and release](06-migration-and-release.md) — imports, compatibility, cutover, rollback.
7. [Execution backlog](07-execution-backlog.md) — ordered work and acceptance checks.

## Working rules for subsequent implementation

- Start with P0 and record its decisions before building the domain schema.
- Update the backlog with actual evidence when work is completed. Unchecked work
  is planned, not implemented. Do not claim v1 parity from a generated scaffold.
- Extend this existing application. Do not generate another Phoenix project or
  repeat the combined Igniter installation.
- Keep v1 unchanged as the behavioral reference. Use isolated databases, buckets,
  and local test directories; never use production resources for tests.
- Tenant boundaries and SDK contracts are release requirements, not later polish.
- Prefer one completed vertical slice over many UI placeholders.
- Follow `../AGENTS.md`, run its required `mix precommit` check, and verify
  document links and the planning inventory.
- This directory records the roadmap. The later user request authorized the MVP
  implementation, commits and pushes. Do not infer that all remaining phases are complete.

## Current milestone

The original scaffold is commit `cbd5d3f`; the first landing/auth/workspace/admin
MVP is `0b13223`. Follow-up security and verification work is documented in
[mvp-delivery.md](mvp-delivery.md). Current verification: 37 Elixir tests + 4 JavaScript theme tests.
These checks cover the MVP, not v1 storage parity. Full tenant membership/grants,
file storage, jobs, compatibility imports and production cutover remain planned.
