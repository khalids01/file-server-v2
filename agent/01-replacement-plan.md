# V2 product roadmap

Updated 2026-11-14. This is the active plan. V2 should be a better independent product; preserving v1 SDKs, legacy routes, credentials and old public URLs is **not a requirement**. Do not build compatibility adapters. Earlier parity/tenancy plans are historical references, not acceptance criteria.

## Product boundaries

User → Applications → Files, storage settings and scoped server API keys. No workspaces or memberships. Sign-in uses GitHub or emailed one-time codes only. Keep the Phoenix/Ash stack, shared shadcn-style components and dark mode. Extend the existing app; never generate another project or rerun installation.

Already delivered: landing/auth/admin, application dashboard, private local/S3 storage, scoped v2 file API, tags/search/pagination, account quotas, durable jobs/recovery, and isolated image variants. See [status](status.md) and [image/storage guide](../docs/storage-reliability-images.md).

## 1. File management experience — current milestone

- URL-persisted grid/list views with private thumbnails and useful nonimage placeholders.
- File details with preview, dimensions, size/type/date, tags, storage and download.
- Drag/drop upload, per-file progress, cancellation, failure results and honest reselection/retry.
- Select current page, clear selection, confirmed bulk deletion and add/remove/replace tags.
- Maximum 25 unique valid IDs per bulk operation. Reauthorize each actor/application/file; report partial failures and retain failed selection.
- Copy private download URLs with clipboard feedback and a clear sign-in requirement. These are not public share links.
- Preserve filters, pagination, quotas, original storage destinations and private access. Check light/dark responsive behavior where browser tools permit.

Gate: existing tests and new interaction/access-boundary tests pass; no secrets or object keys enter UI responses. Run mix precommit, assets.build, Ash schema checks and JS tests.

## 2. Controlled sharing

Add explicit expiring/revocable share links with narrow file scope, hashed tokens, access limits and clear owner controls. Keep private defaults. Design access rules and tests before exposing public content. Do not turn authenticated download URLs into public links implicitly.

## 3. Application visibility

Application-level file/storage totals, processing and cleanup status, actionable failure messages, and useful usage/activity views. Build real queries and actions rather than placeholder charts.

## 4. Operational reliability

Backup/restore rehearsal, resumable transfers, retention/trash policy, monitoring, deployment memory/disk limits, secret management, HTTPS, real-provider staging checks and documented recovery. Rehearse with disposable fixtures; never test destructively against live data.

## 5. Optional data import

An explicit import tool may later copy chosen existing files/metadata with validation, resumable manifests and counts/checksums. This does not imply v1 API, token, password, route or SDK compatibility. No automatic production cutover.

## Execution rules

Use isolated PostgreSQL on port 5434 and temporary local storage. Never source .env or use actual buckets/production during automated testing. Preserve actor/application authorization for HTTP, LiveView, services and jobs. Keep the user as the only Git author/committer; no AI/coauthor trailers. Commit and push reviewed, passing milestones using the authorization in this conversation.
