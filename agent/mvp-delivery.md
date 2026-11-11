# MVP delivery — 2026-11-11

## Implemented

- Custom Serve landing, sign-in/register/reset request pages and email-code UI.
- Stable Ash Authentication 4.15.1 retained. Password registration/confirmation,
  password login/reset, existing magic links, and persisted GitHub provider identities.
- Custom email-code flow with challenge-bound HMAC, durable issuance/rate limits,
  row-lock consumption, attempt limits, expiry, and normal Ash persisted tokens.
- Atomic database counters for password attempts and auth POST IP budgets.
- Owner-isolated workspaces, idempotent onboarding, switching, application creation,
  explicit key scopes, thirty-day key expiry, one-time reveal and revocation.
- Verified-user dashboard, profile edit, signup toggle, operator-only user list,
  ban/unban and explicit local `mix app.operator EMAIL` bootstrap.
- Fresh account/membership checks, original-record tenant checks on mutations,
  protected operator actions and filtered sensitive request parameters.

The product admin is `/dashboard/admin`; `/admin` remains dev-only Ash Admin.
`/api/v2/application` proves new application key identity/scope, not storage parity.
Global key lookup is a narrow trusted hash lookup; ordinary policies require tenant
context. Existing personal keys retain their separate self-only JSON API behavior.

## Git and implementation ownership

- `855ff11`: baseline scaffold and full replacement plan.
- `7fd0d39`: first working landing/auth/workspace/operator MVP (23 passing tests).
- `91710e1`: tenant mutation scope, IP throttling, auth lifecycle and concurrency verification (32 passing tests).
- Documentation is committed separately after the implementation checks.
- `origin` fetch URL: `https://github.com/khalids01/file-server-v2.git`.
- Push URL uses the user's already configured SSH identity for the same GitHub
  account, because HTTPS had no cached credentials. No force push was used.

Command Code session `serve-v2-landing-auth-admin-mvp`, ID
`c56baacb-416e-43f5-9b43-ae9a3f4721ea`, created the baseline commit/push and partial
password/GitHub/OTP/platform work. It exited with insufficient credits (exit 10).
The user then explicitly authorized Codex to continue. Codex repaired and completed
the scoped MVP, added tests and UI, and performed verification. No claim is made
about measured cost savings. No additional model/account was selected.

## Verification evidence

All checks use the dedicated PostgreSQL fixture at localhost:5434, not the user's
ignored `.env` database at localhost:5432. New additive migrations were exercised
on fixture development/test databases. V1 was not edited or imported.

- `mix precommit`: exit 0, **32 tests passed**, warnings-as-errors compilation passed.
- `mix ash.codegen --check`: exit 0, no pending schema changes.
- `mix assets.build`: exit 0.
- Actual two-connection OTP concurrency test: one success and one failure for one code.
- Password confirmation, reset/replay, old-session rejection, fresh HTTP login,
  GitHub identity creation/email-collision rejection, closed signup, stale-actor
  bans, tenant mutation laundering, credential scope/revocation and LiveView forms.
- HTTP smoke on owned temporary port 4010: landing/sign-in/register/reset-request/OTP/OpenAPI/mailbox/CSS returned 200; anonymous dashboard/operator routes returned 302; missing application credentials returned 401. Temporary server is stopped after checking.
- Browser host unavailable: screenshot/mobile visual QA is not claimed.

Development plaintext test codes are delivered only through Swoosh Local/Test.
No production deployment, real-email send, real GitHub callback, v1 modification,
secret commit, or destructive user-database operation was performed.

## Manual acceptance path

Follow the root README: source your trusted `.env`, `mix setup`, `mix phx.server`.
Request a code, read `/dev/mailbox`, sign in; create/switch workspaces; create an app;
issue/test/revoke a key; register/confirm a password account; reset a password.
Promote an existing verified account locally and test operator signup/ban controls
against a second account. Configure your GitHub OAuth app before real provider QA.

## Deliberately deferred

All P4+ file/storage/transfer/backup/image/SDK-compatibility/import/cutover work.
P1 membership invitation/management, application-specific member grants and ownership
transfer; the MVP admits no membership writes outside trusted owner onboarding.
P2 explicit GitHub account linking/unlinking, session listing/logout-all UI and a
mail outbox/retry lifecycle. P3 application rename settings UI, richer operator
audit browsing and operational dashboards. No fake storage metrics or working
upload buttons are displayed. Existing email accounts cannot auto-link GitHub;
use their current method until explicit linking is implemented.

The reserved rate-counter rows in `platform_settings` need a retention/cleanup
job before large-scale deployment. Proxy IP handling, OAuth credentials, actual
mail delivery and production-load/security acceptance remain operator/staging work.
Full v1 replacement is not complete, and no production cutover is recommended yet.
