# File Server v2

Phoenix + Ash application MVP with **only GitHub and emailed one-time codes for user
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
`app_test` database on port 5434. Run `mix ecto.migrate` after pulling updates.

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
first sign-in creates the account. Applications belong directly to users.
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

- `/dashboard`: application and API-key overview.
- `/dashboard/applications`: v1-style application cards, empty state and creation dialog.
- `/dashboard/applications/:id`: application name/settings; `?tab=keys` manages scoped,
  thirty-day keys; `?tab=files` uploads, lists, downloads and deletes private files.
- `/dashboard/profile`: full-width profile editor; GitHub or email-code sign-in.
- `/dashboard/admin`: operator-only user list, ban/unban and signup toggle.

Applications and keys are owner-isolated. There is no workspace layer or switcher.
The previous `/dashboard/settings` route has been removed.

No signup becomes an operator. After verifying your own account, promote it using
the same local database environment:

```bash
mix app.operator you@example.com
```

Refresh/sign in again, then test admin controls with a separate test account.
Bans are rechecked on session loading, dashboard events and key use. Operator
status does not grant access to other users' applications.

For backend application-key testing:

```bash
curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  http://localhost:4000/api/v2/application
```

This returns the authorized application identity and `storage_ready: true`.
Keys do not authenticate browsers; requests carrying Origin are rejected. The
self-only `/api/json/users` API now uses the existing GitHub/OTP browser session,
not personal bearer credentials. OpenAPI remains at `/api/json/open_api`.
`/admin`, `/dev/dashboard`, `/dev/mailbox` and LiveDebugger are development tools;
the product admin is `/dashboard/admin`.

## Storage environment

Applications default to private **local storage**. In **Manage → Settings**, choose
a destination and save, test it, or connect an S3-compatible bucket. **Files**
supports uploads (five at a time), a private file browser with filename search,
sortable views (newest, oldest, name, size) and paginated results (25 per page),
private downloads and confirmed deletion. Filters and page persist in the
`?tab=files` URL. Cards show actual file counts.

- `LOCAL_STORAGE_PATH`: private upload root, default `storage/` under the project.
  In production use a writable persistent volume outside public/static assets.
- `MAX_FILE_SIZE_MB`: enforced by LiveView and the storage service, default 50.
  Legacy `NEXT_PUBLIC_MAX_FILE_SIZE` is not used by the Elixir app.
- Existing `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET`, `S3_REGION`, and
  `S3_ENDPOINT`: enable **S3 from server environment** in the destination selector.
  Selecting it and saving copies the config into an encrypted destination record.
- Alternatively, **Connect S3 storage** saves credentials entered in the dialog.
  Both paths use path-style S3 requests, SigV4 signing and streamed transfers.
- Provider endpoint suffixes supported by default: `amazonaws.com`, `idrivee2.com`,
  `r2.cloudflarestorage.com`, `digitaloceanspaces.com`, `backblazeb2.com`,
  `wasabisys.com`. Endpoints must be HTTPS and have no path, query or embedded
  credentials. For custom/private MinIO hosts, explicitly set comma-separated
  `S3_ALLOWED_HOSTS` on the server. HTTP is permitted only for those explicit hosts.

Buckets must already exist. Credentials need object Put/Get/Delete permissions.
**Test current storage** writes, checks and deletes a tiny object in the app's
namespace; it does not list or import existing bucket contents. Changing the
default destination affects new uploads only. Existing files retain their
original destination and encrypted credential snapshot. Connection records are
immutable in this milestone; key rotation and destination removal remain future work.

Downloads require the owning user's active session and are attachments, never
public static URLs. S3 downloads stream into a bounded temporary file and are
removed after sending. Local files use generated UUID paths, restrictive file
permissions, and reject symlinks and user-provided paths. Files are private, but
this milestone does not encrypt file contents; the vault encrypts S3 credentials.

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
node --test test/js/*_test.mjs
```

Verified: **121 Elixir tests + 16 JavaScript tests**, warnings-as-errors app
compilation, assets and schema consistency. Coverage includes two-connection OTP
consumption, failed mail revocation, TLS configuration, trusted/untrusted GitHub
email linking, disabled routes, application ownership isolation, bans, key revocation and persisted
theme preference. Storage tests cover local I/O, real LiveView upload/download/delete,
S3 signing/streaming with a simulated bucket, encrypted credentials, failures,
endpoint restrictions, size limits, paginated/searchable browser queries,
malformed-input handling and cross-user/application isolation. Browser tests cover
search/sort filtering, page navigation, empty-search state and ownership redirects.
No real
bucket credentials were used for automated verification. Browser host was unavailable, so screenshot/mobile visual QA is
not claimed. A real Gmail delivery and GitHub OAuth callback require configured
credentials and manual/staging verification; no real mail was sent during tests.

See [the project structure guide](docs/project-structure.md) for feature folders,
shared components, and where to edit each screen.

Relevant files: `lib/app_web/features/`, `lib/app/accounts/`, `lib/app/mailer_config.ex`,
`lib/app_web/components/`, `assets/css/app.css`, `assets/js/theme.mjs`.
The full replacement roadmap is under [agent/](agent/README.md). Current behavior
supersedes the earlier five-method authentication plan. Local/S3 browser storage is
implemented, as are scoped `/api/v2/files` routes. The dashboard file browser supports
filename search, sortable views and 25-per-page pagination persisted in the URL.
V1 compatibility is out of scope. Explicit sharing, analytics, optional imports, transfers and backups are future milestones. `/api/v2/application` reports
`storage_ready: true`, `api_version: "v2"` and `sdk_v1_compatible: false`.
Account-wide quotas, durable recovery and private image variants are implemented. See [storage reliability and images](docs/storage-reliability-images.md) for runtime requirements, limits and migration details.

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

The dashboard sidebar sits against the left edge. Use the header toggle to collapse
it to icons on desktop (saved in local storage) or open the mobile drawer. Escape,
the backdrop, and navigation close the mobile drawer.

## Application ownership migration

`mix ecto.migrate` transfers existing applications to their former workspace owner,
preserves application IDs and API-key credentials, and removes workspace tables.
Duplicate slugs for the same owner receive an ID suffix. Workspace membership
history is removed; this migration cannot be rolled back automatically. Back up
an existing database before applying it. The migration was also checked against
a disposable database containing duplicate slugs and an existing API key.

Custom controls live in `components/ui/`: use `<.button>`, `<.input>`, `<.select>`
and `<.dialog>` rather than adding native interactive controls in page templates.
Select uses a custom keyboard-accessible list and a hidden form value; dialogs
handle focus and Escape. The header places the logo before the sidebar toggle.

See [the v2 file API guide](docs/file-api.md) for curl examples, permissions, limits,
response formats and differences from the v1 SDK. API credentials are checked
before upload parsing; requests are limited to 120/minute/key and 300/minute/IP.

File tags are available in the browser and v2 API: tag badges, a shared edit dialog,
and AND filters preserved in the URL. Matching and deduplication ignore case,
preserving the first spelling for display. See [the API guide](docs/file-api.md).
Run `mix ecto.migrate` after pulling to add empty tags to existing files.

Image previews require Python 3 and Elixir/Erlang on the runtime PATH. After pulling, run `mix deps.get` and `mix ecto.migrate` before starting Phoenix. [Quota and image guide](docs/storage-reliability-images.md).

The Files dashboard now includes grid/list views, file details, current-page selection, bulk delete/tag editing, private-link copying and per-file upload outcomes. See [the file management guide](docs/file-management.md). V2 is developed independently; no v1 SDK compatibility layer is planned.

Applications now include a live **Usage & recovery** tab, with storage totals, processing/cleanup issues and queued recovery actions. Account and application summaries use server records. Operators: [monitoring, backup and restore guide](docs/operations.md). Sharing is deferred; no public links were added.
