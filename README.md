# Serve v2 — landing, authentication and workspace MVP

One Phoenix 1.8.16 / Ash application, directly in this directory. This release is
ready for local testing of sign-in, owner-isolated workspaces, applications,
access keys and operator administration. It is **not yet a replacement for v1's
file storage**. V1 remains unchanged in `../v1`.

## Start with your existing database

Elixir 1.20.5 / Erlang 29.1.2 are pinned in `.tool-versions`. Run Mix inside `v2`.
Your local `.env` is ignored by Git and is **not loaded automatically**.

```bash
cd /home/khalid/Desktop/projects/saas/file-server/v2
set -a
source .env
set +a
mix setup
mix phx.server
```

Source only your own trusted, shell-compatible file. Comments start with plain
`#`. `DATABASE_URL` overrides development host, port, username, password and database
name, including `DB_PORT`. For your existing instance use a URL shaped like
`postgresql://USER:PASSWORD@localhost:5432/file_server_v2`. `mix setup` creates the
database if permitted, applies additive migrations, and builds assets. It does not
import v1 data. Do not point it at the v1 database.

Alternatively, use the dedicated local PostgreSQL container:

```bash
docker compose up -d db
unset DATABASE_URL
mix setup
mix phx.server
```

Compose binds PostgreSQL 18 to `127.0.0.1:5434`, credentials `postgres/postgres`,
database `app_dev`. Tests use separate `app_test` on this port and ignore the
normal `DATABASE_URL`; `DB_HOST`/`DB_PORT` can select a separate test instance.
Do not run tests against a real application database. `docker compose stop db`
stops the local fixture service without removing its data volume.

## What to test

1. Open [the landing page](http://localhost:4000), then **Get started** or **Sign in**.
2. For the fastest path, choose **Email code**. Open
   [the development mailbox](http://localhost:4000/dev/mailbox), copy the six-digit
   code, and submit it. A personal workspace is created on first dashboard entry.
3. Try password registration. Confirm the emailed link before signing in. Password
   reset also lets an email-code/magic-link account add a password safely.
4. Explore Overview, Applications, Workspace settings and Profile. Create a second
   workspace; switching should show separate application lists.
5. Create an application, open **Manage keys**, and issue a read-only key. Copy it
   immediately; only its fingerprint is shown afterward. New keys expire in 30 days.
6. Test the application identity endpoint, then revoke the key and repeat:

```bash
curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  http://localhost:4000/api/v2/application
```

The response identifies the authorized application and tenant and explicitly
returns `storage_ready: false`. This is a connection check, not a working files API.
Application keys cannot read `/api/json/users` or access another tenant. Requests
with a browser `Origin` header are rejected; keys belong on a backend.

### Operator administration

No signup becomes an operator automatically. After signing in and verifying your
email, run this from a trusted local shell using the same database environment:

```bash
mix app.operator you@example.com
```

Sign in again or refresh the dashboard, then open **Operator admin** at
`/dashboard/admin`. Test signup closure/opening and ban/unban with a separate test
account. Non-operators cannot enter this page, grant themselves operator status,
or change platform settings. An operator cannot ban their own account. Bans are
rechecked for sessions, existing LiveView events and key use. Operator status does
not grant access to other users' workspaces.

### GitHub OAuth

Create an OAuth application in GitHub's developer settings. Configure:

```bash
GITHUB_CLIENT_ID=your-client-id
GITHUB_CLIENT_SECRET=your-client-secret
GITHUB_REDIRECT_URI=http://localhost:4000/auth/user/github/callback
```

Add these to your ignored `.env`, load it and restart Phoenix. Use a distinct
OAuth application and HTTPS callback in production. The redirect defaults to the
configured Phoenix endpoint's `/auth` path, with the callback suffix appended by
Ash. Verify the full callback matches GitHub's configuration.

GitHub is shown as unconfigured until credentials exist. New GitHub accounts must
confirm their email locally; subsequent sign-ins resolve the stored provider
subject. Provider tokens are discarded. An existing account is **not auto-linked
by matching email**. Explicit linking/unlinking is deferred, so an existing
email-code/password account cannot simply acquire GitHub access through an email
match. Automated tests cover identity creation and collision rejection; a real
GitHub network callback still requires operator-provided credentials and testing.

### Auth behavior

- Magic links remain available under **Prefer a magic link?** on Sign in.
- Email codes expire after ten minutes, allow three wrong attempts, are single-use,
  and have a sixty-second resend cooldown. Issuance limits: five/hour/identity and
  twenty/hour/IP. Database locks enforce limits across processes/nodes.
- Password sign-in is limited to ten attempts/minute/identity. All auth POSTs share
  a sixty/minute/IP budget and return 429 when exceeded. Proxy deployments must
  configure trusted remote-IP handling appropriately; arbitrary forwarded headers
  are not trusted by the app.
- Codes use an HMAC bound to challenge/identity/purpose; passwords use Bcrypt;
  application keys are stored only as hashes. Sensitive request fields are filtered.
- Password reset links expire after one hour; reset revokes existing browser
  sessions and the reset link cannot be replayed. Application keys are separately
  managed credentials, not browser sessions.
- Development email uses Swoosh Local. No real email is sent with this adapter.

## Routes and structure

| Route | Purpose |
| --- | --- |
| `/` | Landing |
| `/sign-in`, `/register`, `/forgot-password`, `/sign-in/otp` | Authentication |
| `/dashboard` | Verified-account overview and workspace switch |
| `/dashboard/applications` | Application creation, scoped keys and revocation |
| `/dashboard/settings` | Workspace identity and workspace creation |
| `/dashboard/profile` | Display name and password-reset entry |
| `/dashboard/admin` | Operator-only users and signup policy |
| `/api/v2/application` | New application-key connection check |
| `/api/json/users` | Existing personal-key, self-only JSON API |
| `/api/json/open_api`, `/api/json/swaggerui` | Existing JSON API documentation |
| `/admin` | Development-only Ash Admin; not the product operator UI |
| `/dev/mailbox`, `/dev/dashboard` | Development mailbox and telemetry |

LiveDebugger is dev-only, starting at port 4007 and finding an available next port
if occupied. Check startup output. Auxiliary Mix tasks can coexist with a running
server; don't start two Phoenix servers on the same `PORT`.

- `lib/app/accounts/`: Ash users, identities/tokens, OTP, shared limits and senders.
- `lib/app/workspaces/`: tenants, memberships, applications and application keys.
- `lib/app/platform/`, `lib/app/checks/`: operator controls and authorization.
- `lib/app_web/controllers/`: landing, session/OTP pages, API check, auth callbacks.
- `lib/app_web/live/`: dashboard and operator UI.
- `lib/mix/tasks/app.operator.ex`: explicit local operator bootstrap.
- `priv/repo/migrations/`, `priv/resource_snapshots/`: schema and Ash snapshots.
- `agent/`: full v1 replacement roadmap and [delivery status](agent/mvp-delivery.md).

Users/tokens are global identities. Tenant-owned data uses attribute multitenancy.
The application-key table permits a trusted hash lookup without a tenant so a
presented key can resolve its tenant; normal resource policies still require an
active owner/admin and a matching tenant. Key use revalidates the issuer's access.
Personal scaffold keys remain separate and are not upgraded into application keys.

## Verification

```bash
docker compose up -d db
mix precommit
mix assets.build
mix ash.codegen --check
```

Current verified result: **32 tests passed**, including real OTP concurrency on
two database connections, password confirmation/reset and session invalidation,
GitHub identity collision, tenant mutation isolation, bans and key revocation,
HTTP auth flows and LiveView application/operator forms. Assets and schema checks
pass. Browser screenshot QA was unavailable; visual desktop/mobile review remains
a manual acceptance step. Tests do not prove a real GitHub OAuth callback or
production mail delivery; configure and verify those in staging.

## Remaining scope

No file upload/download backend, S3/local file manager, storage usage stats,
transfers, image processing, backups, browser-token SDK integration or v1 importer
is implemented yet. No memberships can be modified through the MVP: personal
owner workspaces are usable, while invitations, limited application grants and
ownership transfer remain on the plan. Application renaming UI, explicit GitHub
linking/unlinking, session manager/logout-all UI, and audit browsing are deferred.
Do not migrate production traffic from v1 based on this MVP.

The unified original installation includes Phoenix, Ash/Ash Phoenix, Ash
PostgreSQL, Ash Authentication/Phoenix, JSON API, Ash Admin, Ash Archival,
LiveDebugger, Cloak and Ash Cloak. Archival/encrypted-storage resource integration
belongs to the storage phases; the AES-GCM vault is supervised and tested now.
Exact package versions are in `mix.lock`; no second Phoenix app was generated.

## Production settings

See `.env.example`. Production requires `DATABASE_URL`, `SECRET_KEY_BASE`,
`TOKEN_SIGNING_SECRET`, a base64-encoded 32-byte `CLOAK_KEY`, `PHX_HOST`, verified
`MAIL_FROM`, `MAILGUN_API_KEY`, and `MAILGUN_DOMAIN`. Generate signing values with
`mix phx.gen.secret` and the encryption key with `openssl rand -base64 32`. Keep
encryption keys persistent/private and backed up separately. Configure database
TLS and HTTPS/reverse proxy for your deployment. Test real mail/OAuth before use.

Hex reports advisories for Assent 0.2.13's Apple callback and Cloak 1.1.4's AES-CTR
cipher. Apple auth and AES-CTR are not enabled; this app uses GitHub and AES-GCM
and normalizes Cloak's tampered-ciphertext failure result. Ash Authentication pins
Assent below 0.3, so upgrading it requires a compatibility review. See the
[Assent advisory](https://osv.dev/vulnerability/EEF-CVE-2026-117656) and
[Cloak advisory](https://osv.dev/vulnerability/EEF-CVE-2026-95105).
