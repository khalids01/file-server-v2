# Authentication — current requirement, 2026-11-12

This supersedes the earlier five-method design. User sign-in supports **GitHub and
emailed one-time codes only**. Do not reintroduce password registration/login/reset,
magic links, remember-me, confirmation links or personal API-key sign-in.

Application keys remain machine credentials scoped to a tenant/application. They
are separate from user sign-in and cannot open dashboard/operator sessions.

## Implemented boundaries

Global Ash User/Token identities; persisted session tokens; owner-isolated workspaces;
neutral OTP request responses; challenge-bound HMAC; ten-minute TTL; three wrong
attempts; one successful consumption; sixty-second resend cooldown; database-backed
issuance/IP limits and row locks. Failed SMTP delivery revokes the challenge.
Signup closure is rechecked before account creation, including in-flight OTPs.
Bans apply to user sessions, LiveView events and integration-key access.

GitHub's Assent adapter fetches the primary email and verified flag from `/user/emails`
with `read:user,user:email`. Reject missing/unverified emails. A trusted, verified
primary email may link to the same existing OTP account. Stable provider IDs take
precedence and cannot be silently replaced by another provider subject. OAuth
access/refresh tokens are discarded. Do not trust arbitrary browser-supplied
`user_info`; only the server's OAuth callback may supply provider identity data.

SMTP uses Swoosh/`gen_smtp`, configured with EMAIL, EMAIL_PASSWORD, EMAIL_FROM,
SMTP_HOST and SMTP_PORT. EMAIL_FROM is the display name; EMAIL is the login and
default sender. Port 465 uses verified implicit TLS; 587 uses verified STARTTLS.
Development falls back to Local only with both credential fields empty. Tests
always retain Test mail; no external recipient is used by automated checks.
Production requires credentials. See root README for GitHub callback and Gmail
app-password instructions.

## Design

Phoenix-native shadcn-style controls with semantic CSS variables. Shared buttons,
inputs, labels, cards, badges, table/alerts and menus adapt to light/dark/system.
Preferences persist in local storage and a sanitized cookie; server markup and
system CSS avoid forcing light mode before JavaScript. Test blocked storage,
OS changes, cross-tab changes, reloads and LiveView navigation.

## Deferred

Session list/logout-all UI, explicit provider unlinking, durable mail outbox/retries,
provider/network acceptance and rate-counter cleanup/retention. Legacy credential
columns/tables are retained unused to avoid destructive data removal. JSON API
user reads now authenticate with the same browser session, not another login method.
Do not drop legacy fields without a separate migration/data-retention decision.
