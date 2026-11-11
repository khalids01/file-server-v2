# App v2 — Phoenix + Ash foundation

One Phoenix 1.8.16 application (`:app`, namespace `App`) lives directly in `v2`.
This is the foundation for replacing v1. It does **not yet implement v1's file uploads,
S3/local storage, image processing, tenants, file manager, or data migration**.
The existing `../v1` application remains independent.

## Run locally

Prerequisites: Elixir 1.20.5 / Erlang OTP 29.1.2 (pinned in `.tool-versions`),
Docker with Compose, and Git. Use a version manager or install these versions.

```bash
cd /home/khalid/Desktop/projects/saas/file-server/v2
docker compose up -d db
mix setup
mix phx.server
# Or: iex -S mix phx.server
```

PostgreSQL 18 listens only on `127.0.0.1:5434`, with development credentials
`postgres` / `postgres`. Databases: `app_dev` and `app_test`. Override host/port
with exported `DB_HOST` / `DB_PORT`. Data persists in a Compose volume.
`docker compose stop` stops the database without removing its data.

Run Mix commands from `v2`, where `.tool-versions` and `mix.exs` live. An exported
`DATABASE_URL` overrides development database defaults (including host, port,
credentials and database name). Tests keep their separate `app_test` database.
For an existing local PostgreSQL instance, put its URL in `.env`, then load it:

```bash
# From v2; only source your own trusted shell-compatible .env file.
set -a
source .env
set +a
mix ecto.setup
mix phx.server
```

Use plain `#` comments in `.env`, without Markdown asterisks. `.env` is not loaded
automatically. When `DATABASE_URL` contains a port, that port overrides `DB_PORT`.


| URL | Purpose |
| --- | --- |
| http://localhost:4000 | Phoenix welcome page |
| http://localhost:4000/sign-in | Request a magic link |
| http://localhost:4000/dev/mailbox | Development email inbox |
| http://localhost:4000/admin | Ash Admin, development only |
| http://localhost:4000/dev/dashboard | LiveDashboard, development only |
| http://localhost:4000/api/json/users | Authenticated user's JSON:API representation |
| http://localhost:4000/api/json/open_api | OpenAPI schema |
| http://localhost:4000/api/json/swaggerui | Swagger UI |
| http://localhost:4007 | LiveDebugger, development only |

## Authentication

**Magic links:** Enter an email at `/sign-in`, open `/dev/mailbox`, follow the
link, and confirm sign-in. New emails register automatically. Tokens are stored,
single-use, and require an interaction so email link scanners cannot silently
consume them. Existing users can sign in again with a fresh link.

Development mail stays local; tests use Swoosh's test adapter. Production is
configured for Mailgun and requires `MAILGUN_API_KEY` / `MAILGUN_DOMAIN`.
Set `MAIL_FROM` to a verified sender before production use.

**API keys:** Keys are separate credentials, not session JWTs. They are sent as
`Authorization: Bearer <key>`. Only their hash is stored. The plaintext is returned
once in resource metadata. Each key has an owner and expiry; owners can read and
revoke only their own keys. Invalid, expired, and deleted keys fail authentication.

To issue a key for an existing user in a trusted local IEx session:

```elixir
# Trusted operator lookup; normal application calls must pass actor: user.
user = Ash.get!(App.Accounts.User, [email: "you@example.com"], authorize?: false)
key = App.Accounts.ApiKey
  |> Ash.Changeset.for_create(:create, %{expires_at: DateTime.add(DateTime.utc_now(), 86_400)}, actor: user)
  |> Ash.create!()
key.__metadata__.plaintext_api_key # copy once; don't log or commit it
# Revoke: Ash.destroy!(key, actor: user)
```

```bash
curl -H "Authorization: Bearer $APP_API_KEY" \
  -H 'Accept: application/vnd.api+json' \
  http://localhost:4000/api/json/users
```

`GET /api/json/users` lists only the actor's record. `GET /api/json/users/:id`
returns only that same record; other users are hidden. Anonymous resource reads
return HTTP 401. Authentication actions, token records, and API key hashes are not
exposed through JSON API. OpenAPI and Swagger are public documentation endpoints.
Ash Admin is a local development tool and has no production route.

## Structure

```text
config/                          environment, database, mail, token and vault settings
lib/app/accounts.ex              Accounts Ash domain + JSON API routes + Admin
lib/app/accounts/user.ex         PostgreSQL user, magic-link and API-key strategies
lib/app/accounts/api_key.ex      hashed keys, expiry, owner policies
lib/app/accounts/token.ex        authentication token persistence
lib/app/accounts/user/senders/   magic-link email sender
lib/app/vault.ex                 AES-256-GCM Cloak vault
lib/app/repo.ex                  AshPostgres repository
lib/app_web/router.ex            browser auth, JSON API, development tools
lib/app_web/ash_json_api_router.ex Accounts JSON API/OpenAPI router
lib/app_web/live_user_auth.ex    hooks for future authenticated LiveViews
priv/repo/migrations/            PostgreSQL extensions and accounts tables
priv/resource_snapshots/         Ash schema snapshots (commit with migrations)
assets/                         Phoenix Tailwind and JavaScript
compose.yaml                    dedicated local PostgreSQL
test/                          authentication, API isolation, vault and Phoenix tests
```

The stack includes Ash, Ash Phoenix, Ash PostgreSQL, Ash Authentication,
Ash Authentication Phoenix, Ash JSON API, Ash Admin, Ash Archival, LiveDebugger,
Cloak and Ash Cloak. Exact resolved versions are recorded in `mix.lock`.

Ash Archival and Ash Cloak are resource extensions with no global installer.
Add `AshArchival.Resource` to future file resources to soft-delete them, then
run `mix ash.codegen <migration_name>`. Authentication tokens and API keys are
intentionally hard-deleted on revocation. For encrypted storage credentials,
add `AshCloak`, configure `cloak do; vault App.Vault; attributes [:secret]; end`,
and generate a migration. No storage credential resource exists yet.

The vault is supervised and uses authenticated AES-GCM. It normalizes Cloak's
authentication-failure return value and raises on tampered ciphertext. Development/test have a
fixed local-only key. Production requires a base64-encoded 32-byte `CLOAK_KEY`;
keep it private and persistent or encrypted records cannot be recovered.

## Verification and schema changes

```bash
mix test
mix precommit
mix ash.codegen --check
mix ecto.migrations
mix assets.build
```

After changing Ash resources, run `mix ash.codegen descriptive_change_name`,
review the migration, then `mix ecto.migrate`. Tests automatically create and
migrate their isolated database. Test coverage includes actual magic-link email
and sign-in, token replay, API key expiry/revocation, cross-user isolation,
JSON API/OpenAPI, and vault encryption/tamper detection.

## Verified locally

- `mix setup` completed against the dedicated PostgreSQL container.
- Both initial development migrations applied; test migrations applied automatically.
- `mix test` and `mix precommit`: 11 tests passed; warnings-as-errors compilation passed.
- `mix assets.build` succeeded.
- `mix ash.codegen --check` found no pending schema changes.
- HTTP checks returned 200 for home, sign-in, Admin, OpenAPI and LiveDebugger.
- Initial dependency compilation emits upstream warnings on Elixir 1.20; the
  application itself compiles without warnings.

## Unified installation record

Phoenix was generated **once** through Igniter New. Its single combined install
phase was equivalent to:

```bash
mix igniter.install ash,ash_phoenix,ash_postgres,ash_authentication,ash_authentication_phoenix,ash_json_api,ash_admin,ash_archival,live_debugger,cloak,ash_cloak \
  --auth-strategy magic_link,api_key --yes
```

The actual generator command, run from the parent directory against a nonexistent
`v2` directory, was:

```bash
mix archive.install hex igniter_new --force
mix archive.install hex phx_new 1.8.16 --force
mix igniter.new v2 --with phx.new \
  --with-args='--app app --module App --no-install' \
  --install ash,ash_phoenix,ash_postgres,ash_authentication,ash_authentication_phoenix,ash_json_api,ash_admin,ash_archival,live_debugger,cloak,ash_cloak \
  --auth-strategy magic_link,api_key --yes
```

Do not rerun the generator or installer on this existing project. Use `mix setup`
for normal setup. The installer completed its package configuration; migration
code generation was rerun separately after correcting runtime configuration.

## Production configuration

Export `DATABASE_URL`, `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET`, `CLOAK_KEY`,
`PHX_HOST`, `MAIL_FROM`, `MAILGUN_API_KEY`, and `MAILGUN_DOMAIN`.
Generate signing secrets with `mix phx.gen.secret`; generate a vault key with
`openssl rand -base64 32`. `.env.example` lists settings; `.env` files are not
automatically loaded. Use your deployment environment's secret management.
Build assets with `MIX_ENV=prod mix assets.deploy`, migrate with
`MIX_ENV=prod mix ecto.migrate`, and start with
`PHX_SERVER=true MIX_ENV=prod mix phx.server` (or build a release).
LiveDebugger is a development-only dependency; Admin/dashboard/mailbox routes
are absent outside development. Configure database TLS for your deployment.

Hex currently flags Assent 0.2.13's Apple callback advisory and Cloak 1.1.4's
AES-CTR advisory. Apple authentication is not enabled, and the vault exclusively
uses AES-GCM. Ash Authentication currently constrains Assent to `< 0.3.0`;
review upstream fixes before enabling Apple auth or changing cipher modes.
See [Assent advisory](https://osv.dev/vulnerability/EEF-CVE-2026-117656) and
[Cloak advisory](https://osv.dev/vulnerability/EEF-CVE-2026-95105).

## V1 replacement roadmap

See [agent/README.md](agent/README.md) for the plan, v1 parity inventory, tenant
architecture, GitHub/password/email OTP authentication design, dashboard/storage
requirements, migration/release strategy, and ordered execution backlog. This is
a planning handoff; those replacement features have not been implemented yet.
