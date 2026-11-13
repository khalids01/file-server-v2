# Finding your way around v2

Most page UI lives in `lib/app_web/features/`. Backend rules and data live in
`lib/app/`. Shared UI lives in `lib/app_web/components/`.

```text
lib/
  app/                          Backend: resources, permissions, business rules
    accounts/                   Users, GitHub identity, email OTP, sessions
    applications/               User-owned applications and integration keys
    storage/                    Connections, private file metadata, local/S3 adapters
    storage.ex                  Authorized upload/download/delete and storage checks
    mailer.ex                   Swoosh mail delivery
    mailer_config.ex            SMTP configuration
  app_web/                      Browser and HTTP layer
    features/
      landing/                  Homepage controller and page_html/home.html.heex
      auth/                     Sign-in, OTP pages, OAuth callbacks, route guards
      dashboard/                Dashboard LiveView and its adjacent HTML template
      admin/                    Operator LiveView and its adjacent HTML template
      files/                    Private download controller
    components/
      ui/                       Button, input, card, badge, table, icon, etc.
      layouts.ex                Shared page shells and theme switcher
      layouts/root.html.heex    Root HTML document
    api/                        JSON API router, scoped file API, credential and upload parsing plugs
    errors/                     HTML and JSON error responses
    router.ex                   URL → controller/LiveView mapping, route protection
    endpoint.ex                 HTTP server, sockets, sessions
  app_web.ex                    Shared imports available to pages and templates
assets/
  css/app.css                   Theme tokens, component styles, Tailwind entry point
  js/theme.mjs                  Light/dark/system preference behavior
  js/app.js                     Browser entry point and LiveView connection
config/                         Build-time and runtime configuration
priv/repo/migrations/           Database migrations
priv/resource_snapshots/        Ash schema snapshots used to generate migrations
test/                           Backend, browser-flow, and JavaScript tests
agent/                          Replacement roadmap and implementation notes
```

## Where to edit

| What you want to change | Start here |
| --- | --- |
| Landing page content | `lib/app_web/features/landing/page_html/home.html.heex` |
| Signup appearance | `lib/app_web/features/auth/session_html/register.html.heex` |
| Account avatar menu | `lib/app_web/components/ui/user_menu.ex` |
| Sign-in appearance | `lib/app_web/features/auth/session_html/new.html.heex` |
| Email code request or verification appearance | `lib/app_web/features/auth/otp_html/` |
| Email code validation or GitHub account linking | `lib/app/accounts/` |
| SMTP connection settings | `lib/app/mailer_config.ex` and `config/runtime.exs` |
| Application settings and keys | `/dashboard/applications/:id`, using the dashboard LiveView |
| Local or S3 file storage | `lib/app/storage/` and `lib/app/storage.ex` |
| Server-side file API | `lib/app_web/api/file_api_controller.ex` and `application_auth.ex` |
| Private downloads | `lib/app_web/features/files/file_controller.ex` |
| Shared selects and dialogs | `lib/app_web/components/ui/select.ex`, `dialog.ex`, and `assets/js/controls.mjs` |
| Dashboard pages and interactions | `lib/app_web/features/dashboard/dashboard_live.ex` and `.html.heex` |
| Admin page and interactions | `lib/app_web/features/admin/operator_live.ex` and `.html.heex` |
| Application ownership and API keys | `lib/app/applications/` |
| Button or input markup | `lib/app_web/components/ui/button.ex` or `input.ex` |
| Colors, spacing, shared component styles | `assets/css/app.css` |
| Collapsible dashboard sidebar | `lib/app_web/components/ui/sidebar.ex` and `assets/js/sidebar.mjs` |
| Shared layout and theme toggle | `lib/app_web/components/layouts.ex` |
| URL or access requirement | `lib/app_web/router.ex` |

## Coming from TypeScript

A `.html.heex` file is a page/component template, similar to JSX. A controller
handles HTTP requests and chooses a template. A LiveView `.ex` file manages page
state and events; its adjacent `.html.heex` renders that state. Shared function
components use HEEx inside `.ex` files and are automatically imported through
`lib/app_web.ex`, so pages can use `<.button>` or `<.input>`.

An Ash resource in `lib/app/` combines schema, actions, validation, and permissions.
Keep those rules there even when their UI belongs to a feature folder.

Folder names organize files; Elixir modules have explicit names. For example,
`features/auth/otp_controller.ex` still declares `AppWeb.OtpController`. Keeping
these names preserves existing routes and configuration. HTML modules keep their
`*_html/` templates beside them, and LiveViews keep their adjacent templates.

## Running and checking

From `v2/`, load your local environment with `set -a; source .env; set +a`, then run
`mix phx.server`. See the root README for database setup and required environment
variables. The `.env` file is not loaded automatically.

Checks: `mix precommit`, `mix assets.build`, `mix ash.codegen --check`, and
`node --test test/js/*_test.mjs`. Use your configured development/test database;
`docker compose up -d db` supplies the repository's local database on port 5434.

Storage quotas and native image workers are described in [storage reliability and images](storage-reliability-images.md), including a code map and deployment requirements.

File-browser components live in `lib/app_web/features/files/file_components.ex`; bounded bulk services live in `lib/app/storage/file_management.ex`, and clipboard behavior lives in `assets/js/clipboard.mjs`. See [file management](file-management.md).
