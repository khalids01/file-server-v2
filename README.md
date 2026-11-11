# File Server v2

Phoenix + Ash workspace MVP with **only GitHub and emailed one-time codes for user
sign-in**. Passwords, password reset, magic links, remember-me strategies and personal
API-key sign-in have been removed. Application keys remain server-to-server
integration credentials; they cannot sign a user into the dashboard.

The UI uses Phoenix-native components styled after shadcn/ui: neutral semantic
colors, bordered cards, consistent controls, focus rings and light/dark/system modes.
DaisyUI is removed. The theme menu is in the header; preference persists across
reloads, tabs and LiveView navigation. No React runtime is required.

## Run locally

Use the Elixir/Erlang versions pinned in `.tool-versions`. From `v2`:

```bash
cd /home/khalid/Desktop/projects/saas/file-server/v2
set -a
source .env
set +a
mix setup
mix phx.server
```

`.env` is ignored by Git and is **not loaded automatically**. Source only your own
trusted shell-compatible file. Restart Phoenix after changing credentials.

An exported `DATABASE_URL` overrides development host/port/database/credentials.
For your existing PostgreSQL use a URL such as
`postgresql://USER:PASSWORD@localhost:5432/file_server_v2` (never the v1 database).
Otherwise start the provided fixture database with `docker compose up -d db`;
defaults are localhost:5434, postgres/postgres, `app_dev`. Tests use a separate
`app_test` database on port 5434. No migration is needed specifically for this theme
and authentication change; old credential columns/tables are retained but unused.

## Email through SMTP

Swoosh + `gen_smtp` is the Elixir equivalent of the previous Nodemailer setup.
Use your existing variables:

```dotenv
EMAIL=your-account@gmail.com
EMAIL_PASSWORD=your-gmail-app-password
EMAIL_FROM="File Server"
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
```

`EMAIL_FROM` is the **display name**; the actual sender address defaults to `EMAIL`.
Use `EMAIL_FROM_ADDRESS` only for an authorized alternate sender. Gmail's supported
app-password setup is described in [Google's instructions](https://support.google.com/accounts/answer/185833).
Do not commit credentials or use an ordinary Gmail account password here.

Port 465 uses implicit TLS, authentication and certificate/hostname verification.
Port 587 uses required STARTTLS with the same verification. When EMAIL and
EMAIL_PASSWORD are both blank, development uses `/dev/mailbox`; with credentials
present it sends actual SMTP email, and those messages aren't saved in the local
mailbox. Partial credentials cause a clear startup configuration error. Production
requires configured SMTP. Tests always use isolated test mail, even if your shell
contains real email credentials.

Sign in at `/sign-in`, enter your email and submit the six-digit code. A successful
first sign-in creates the account; the dashboard creates its personal workspace.
Codes expire in ten minutes, allow three wrong attempts, and cannot be replayed.
Resend cooldown is sixty seconds; request limits are five/hour/email and twenty/hour/IP.
A shared sixty/minute/IP limit protects auth POSTs. Challenge-bound HMACs and
PostgreSQL locks protect code storage, rate enforcement and concurrent consumption.
Delivery failures revoke the code and show a generic error without provider secrets.

## GitHub sign-in

Set `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` in `.env`. Register the callback:

```text
http://localhost:4000/auth/user/github/callback
```

For another host/port set the matching `GITHUB_REDIRECT_URI`. Production should use
an HTTPS callback and a separate OAuth application. Sign-in is disabled gracefully
until credentials exist.

The adapter requests `read:user,user:email` and fetches the primary email plus its
verification flag from GitHub's `/user/emails`. A verified primary email is required.
GitHub and email-code sign-in share an account when that verified email matches.
An unverified claim cannot register/link an account, and a different GitHub subject
cannot silently replace an already linked provider identity. Returning GitHub users
resolve by their stable provider ID. Provider access/refresh tokens are discarded.

## Dashboard and operator tools

- `/dashboard`: real workspace/application overview and tenant switching.
- `/dashboard/applications`: create applications; issue scoped, thirty-day keys;
  reveal plaintext once and revoke immediately.
- `/dashboard/settings`: view workspace identity and create another workspace.
- `/dashboard/profile`: edit display name; sign-in is GitHub or email code only.
- `/dashboard/admin`: operator-only user list, ban/unban and signup toggle.

No signup becomes an operator. After verifying your own account, promote it using
the same local database environment:

```bash
mix app.operator you@example.com
```

Refresh/sign in again, then test admin controls with a separate test account.
Bans are rechecked on session loading, dashboard events and key use. Operator
status does not grant access to other tenants. There are no membership-write APIs
outside trusted owner onboarding; invitations and granular app grants remain planned.

For backend application-key testing:

```bash
curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  http://localhost:4000/api/v2/application
```

This returns the authorized tenant/application identity and `storage_ready: false`.
Keys do not authenticate browsers; requests carrying Origin are rejected. The
self-only `/api/json/users` API now uses the existing GitHub/OTP browser session,
not personal bearer credentials. OpenAPI remains at `/api/json/open_api`.
`/admin`, `/dev/dashboard`, `/dev/mailbox` and LiveDebugger are development tools;
the product admin is `/dashboard/admin`.

## Storage environment

Your `S3_*`, `MAX_FILE_SIZE_MB` and legacy `NEXT_PUBLIC_MAX_FILE_SIZE` settings are
reserved for the planned storage implementation. This update does not implement
uploads, S3 connections or enforce upload-size settings for a nonexistent endpoint.
`STORAGE_ENCRYPTION_KEY` is supported as the vault key; a nonempty `CLOAK_KEY` takes
precedence. It must decode from base64 to exactly 32 bytes. Generate with
`openssl rand -base64 32`, retain it securely across deployments and back it up
separately. Neither key is exposed to the browser.

## Verification

```bash
docker compose up -d db
mix precommit
mix assets.build
mix ash.codegen --check
node --test test/js/theme_test.mjs
```

Verified: **46 Elixir tests + 10 JavaScript tests**, warnings-as-errors app
compilation, assets and schema consistency. Coverage includes two-connection OTP
consumption, failed mail revocation, TLS configuration, trusted/untrusted GitHub
email linking, disabled routes, tenant isolation, bans, key revocation and persisted
theme preference. Browser host was unavailable, so screenshot/mobile visual QA is
not claimed. A real Gmail delivery and GitHub OAuth callback require configured
credentials and manual/staging verification; no real mail was sent during tests.

See [the project structure guide](docs/project-structure.md) for feature folders,
shared components, and where to edit each screen.

Relevant files: `lib/app_web/features/`, `lib/app/accounts/`, `lib/app/mailer_config.ex`,
`lib/app_web/components/`, `assets/css/app.css`, `assets/js/theme.mjs`.
The full replacement roadmap is under [agent/](agent/README.md). Current behavior
supersedes the earlier five-method authentication plan. V1 storage/migration,
file manager, transfers, backups and private delivery remain deferred.

Production additionally needs DATABASE_URL, SECRET_KEY_BASE, TOKEN_SIGNING_SECRET,
PHX_HOST, SMTP credentials and a persistent encryption key. Configure HTTPS/proxy
and database TLS for your deployment; do not switch v1 production traffic yet.
Existing Assent Apple-auth and Cloak AES-CTR advisories do not concern enabled
providers/ciphers here; the app uses GitHub and AES-GCM. Recheck compatibility and
advisories before future dependency/provider changes.

Account creation is available at `/register` with name and email verification,
or GitHub OAuth. Sign-in links to registration. The shared `<.user_menu user={@current_user} />`
component lives in `lib/app_web/components/ui/user_menu.ex`; it shows the GitHub
avatar or the first letter of the display name, with profile and sign-out links.
Run `mix ecto.migrate` after pulling to add the optional `users.avatar_url` column.
Existing GitHub users receive their avatar on their next GitHub sign-in.

The workspace sidebar sits against the left edge. Use the header toggle to collapse
it to icons on desktop (saved in local storage) or open the mobile drawer. Escape,
the backdrop, and navigation close the mobile drawer.
