# Authentication implementation plan

## Required methods

| Method | Current v2 | Planned behavior |
| --- | --- | --- |
| Magic link | Generated and tested | Retain one-time, interaction-confirmed email sign-in |
| API key | Personal user key only | Add tenant/application/scoped credentials and legacy key compatibility |
| GitHub OAuth | Missing | Sign-in/register, explicit link/unlink, verified-email handling |
| Email/password | Missing | Registration, confirmation, login, change/reset, revocation |
| Emailed OTP code | Missing | Request code, enter code, single-use sign-in/register |

Email OTP means a short code delivered by email. It is not an authenticator-app
TOTP strategy and not a renamed magic link. Keep the existing methods in addition
to the three new requested methods.

## Dependency and implementation decision gate

The installed `ash_authentication` is 4.15.1. Its local tutorials include GitHub
and password, and its `add_strategy` dispatcher supports password, magic_link,
and api_key. It has no built-in email OTP tutorial/strategy. Newer 5.0 release
candidate documentation contains an OTP strategy. Do not assume newer docs apply
to this lockfile, and do not run a fictional `--auth-strategy email_otp` command.

P0 must record currently available stable versions and compatibility with Ash,
Ash Authentication Phoenix, Phoenix, JSON API, and the existing Token/User schema.
Default: retain the working stable stack; implement the missing OTP flow using
reviewed Ash actions/custom authentication integration if no compatible stable
native strategy exists. Prefer a stable native OTP strategy if a tested upgrade
is available. An RC upgrade is a separate explicit technical decision and must
not happen just to make an installer flag work.

Before committing to either path, prove: code request → test email → verify →
normal Ash session token → browser session → logout/revocation. Preserve all
existing auth tests. Native OTP eligibility must include signup behavior, code
format, retry limits, race-safe consumption and available Phoenix UI; it may not
match v1 defaults without customization.

References (version-sensitive):
[GitHub tutorial source](https://github.com/team-alembic/ash_authentication/blob/v4.15.1/documentation/tutorials/github.md),
[Password tutorial source](https://github.com/team-alembic/ash_authentication/blob/v4.15.1/documentation/tutorials/password.md),
[OTP documentation for 5.0.0-rc.11](https://hex.pm/packages/ash_authentication/5.0.0-rc.11/files/documentation/tutorials/otp.md?fallback=default).
The checked-out `deps/ash_authentication/documentation/` is authoritative for the
current installed version. Recheck all referenced versions before implementation.

## Shared identity and registration rules

Use one global User across all methods; track verification provenance and stable
provider subject separately from mutable email. Normalize emails consistently
without provider-specific guessing. Allow nullable password hashes for OAuth/OTP
users. Never synthesize a password for an imported user.

A shared registration guard enforces signupEnabled at credential issuance AND
account creation, including in-flight codes/callbacks issued before signup was
disabled. Existing active users may sign in when new signup is disabled. Decide
and test whether accepted invitations are an explicit exception (planned default:
valid invitations may onboard only their intended verified email). New users get
one personal tenant transactionally and idempotently; failed callbacks/retries
must not create duplicate users/tenants. Restricted imported/invited memberships
must not acquire extra access through this onboarding step.

Block banned/disabled accounts across password, OAuth, codes, magic links, API
keys and browser tokens. Ban/unban is operator-only and audited. Store session
security version/revocation state so password reset, logout-all and bans can
invalidate existing credentials according to their credential class.

## Password flow

- Use Ash Authentication's password strategy on the existing User resource;
  follow the installed task/docs and review generated actions before migration.
  Do not run the full installer again.
- Use the already-supported Bcrypt provider with a calibrated production work
  factor; choose different hashing only after measuring and recording the decision.
  Allow long passphrases/password managers; define minimum length and block common
  compromised passwords without sending raw passwords to external services.
- Unverified password registration cannot access tenant data until email
  confirmation. Setting/changing a password on an existing account requires
  recent authentication and verified ownership, not only knowledge of an email.
- Password reset response must not disclose account existence. Reset tokens are
  short-lived, purpose-bound, single-use; successful reset revokes browser sessions
  and pending reset tokens. Explicitly define application-key revocation separately.
- Rate-limit failures by account and IP with bounded lockout/backoff; never store
  or log password inputs. Ensure filters cover auth params, OAuth secrets and OTPs.
- UI: register, sign-in, confirm email, forgot/reset password, change password,
  session list/logout-all, clear errors and accessible validation.

## GitHub OAuth

- Store provider identity with a unique `(provider, subject)` key. Request minimal
  scopes, validate state and the provider flow's supported protections, use exact
  callback URLs and environment-specific OAuth apps. Fetch a verified primary
  email through the provider when permitted; absent/private/unverified email needs
  an explicit verification/onboarding path.
- Existing-account linking requires an authenticated, recently verified user plus
  fresh provider authorization. Never auto-link an existing email solely because
  a callback supplies a matching email. Unlink requires another usable sign-in
  method and recent authentication; audit both operations.
- Configure `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, and a server-controlled
  redirect URI. Expected callback with current route convention is
  `/auth/user/github/callback`; verify with generated routes before registration.
- Verify callback replay, state failure, denied consent, duplicate subject,
  changed email, missing verified email, disabled signup and banned user cases.
- Do not retain provider access/refresh tokens if only login is needed. If retained,
  encrypt them, exclude from public actions/JSON API and support revocation.

## Emailed OTP design

Preserve v1's initial UX: six digits, ten-minute expiry, at most three incorrect
attempts per challenge. Add a 60-second resend cooldown and configurable rolling
limits per normalized identity and IP (initial target five requests/hour/identity,
with separate IP limits tuned using staging evidence). Limits must hold across
multiple application nodes/restarts; use durable/central enforcement, not only a
per-node ETS counter. Return 429 with a consistent retry policy when limited.

If a custom challenge is required, store a random opaque challenge ID, normalized
identity/purpose, keyed digest, expiry, attempts, consumed/revoked timestamps and
request/rate-limit metadata. Protect low-entropy digits using a separate secret
pepper/HMAC bound to challenge, identity and purpose; store neither plaintext code
nor an unkeyed fast digest vulnerable to offline six-digit enumeration. Send via
a transactional outbox/after-commit job; delivery retries must not create many
independently valid challenges.

Verification must lock/conditionally update the challenge and consume it in the
same transaction as authentication state. Simultaneous correct submissions yield
only one success. New issuance supersedes older challenges for that purpose;
resending and wrong attempts cannot extend expiry or reset the aggregate budget.
Use constant-time comparisons, generic invalid/expired responses and no raw-code
logging. A code is never a long-lived access token.

Successful verification proves email ownership and yields the normal Ash
Authentication session with existing token persistence/revocation rules. If signup
is allowed, registration/onboarding happens atomically; otherwise unknown email
gets the same neutral request response but cannot create an account. Reset-email,
login and email-change codes have distinct purposes and cannot substitute for one
another. Do not introduce email-change OTP without a separate verified flow.

UI: email entry → neutral confirmation → six-digit input → resend timer → success.
Support paste, autofill (`one-time-code`), keyboard entry, accessible errors and
mobile. Switching methods must not bypass signup/ban/rate-limit policy.

## API credentials and sessions

Keep dashboard cookie sessions, personal account credentials, application keys,
and browser tokens as distinct actor types. A key scoped to file read must never
read user email lists, issue a stronger key, administer tenants, or mint an
unrestricted browser token. New application-key expiry can be configurable, but
imported non-expiring v1 keys remain functional until an announced rotation date.
Revocation must preserve sufficient audit history without exposing hash material.

Legacy `sk_live_` keys contain a SHA-256 digest of the entire presented key. The
scaffold's Ash API keys use a different format/hash construction. Import the
legacy digest and verify the old format through a separate versioned path; no
plaintext recovery or hash conversion is possible. Bind the result to the imported
application/tenant, respect `revoked`, and update last-used asynchronously with
bounded write frequency. See the migration plan for rollout and expiry policy.

## Authentication acceptance suite

Test all methods alone and on one linked account; existing-user vs new-user signup
policy; unique email/provider races; reset/confirmation replay; rate limits across
nodes; OTP concurrency/expiry/attempts/resend; expired/invalid state; account-link
collision/unlink last-method prevention; open-redirect prevention; logout-all;
ban propagation; deleted membership; key/browser-token scope/Origin enforcement.
Browser session cookies must use production secure/HttpOnly/SameSite settings,
CSRF protection where applicable, and a safe server-controlled return path.

V1 sessions, reset/verification challenges and OTPs will not be imported. Users
sign in again. Import stable GitHub provider identities only after verifying the
provider mapping and account-link rules; do not trust an arbitrary exported email
as proof that a GitHub account belongs to it.
