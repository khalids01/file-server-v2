# Storage quotas, recovery and image previews

Run `mix deps.get`, `mix ecto.migrate`, then `mix phx.server` from `v2/` with your trusted environment loaded. The migration adds Oban tables, file lifecycle metadata, generated variants and account-wide quota rows. Existing files stay ready and their sizes are backfilled into used storage. Back up production before applying migrations. Automated verification uses disposable PostgreSQL on port 5434, never the configured real database or bucket.

## Quotas and recovery

`account_storage` stores one quota, used-byte count and reserved-byte count per user, shared by every application. The initial limit is 5 GiB. `STORAGE_QUOTA_GB` changes the default for new quota rows; it does not overwrite existing limits. An operator can update `account_storage.quota_bytes`. Users cannot raise their own limits through an action or API. Accounts already above their limit after migration can download/delete but cannot upload more until space is available.

Uploads atomically reserve capacity, persist pending metadata/object keys and schedule recovery **before** storage I/O. Successful writes atomically move reserved bytes to used bytes, mark ready and enqueue image work. Originals and every generated variant count toward the same quota. Reservation row locks serialize concurrent uploads across applications. Arithmetic rejects underflow instead of clamping corrupted counters.

A dedicated PostgreSQL advisory-lock connection serializes each file's write, optimization and deletion. It holds the lock throughout I/O and finalization, closes on owner death and stops the owner on loss of its database connection. These connections are additional to the Repo pool; allow capacity for active uploads and the two bounded image/cleanup worker queues. All application instances must share the database; local storage additionally requires the same persistent filesystem.

Deletion attempts physical removal immediately. Metadata/counters remain until all tracked originals/variants are confirmed removed. Failed deletes return an error and are retried through Oban. A periodic reconciler runs every five minutes, revisiting pending uploads older than fifteen minutes, failed writes, requested deletions and interrupted queued/processing images. It only deletes tracked objects; it does not sweep arbitrary bucket contents. Older untracked orphans from before this migration require a separate audit/import tool.

## Image pipeline

PNG, JPEG and static WebP uploads are validated using their bytes. The original is preserved. Oban generates three private variants:

| Name | Format | Maximum longest edge |
| --- | --- | --- |
| `thumbnail` | WebP | 320 px |
| `display_webp` | WebP | 1280 px |
| `display_jpeg` | JPEG | 1280 px |

The Image/Vix/libvips worker applies orientation, strips output metadata and never upscales. SVG, GIF, animated PNG/WebP and unsupported formats are skipped. Corrupt inputs fail safely. Valid earlier variants may remain available if a later variant fails; retry reuses ready variants. Original downloads remain available. The Files dashboard shows previews, processing status, retry controls and account storage usage; the file list refreshes every three seconds while that tab is open.

Generated content is private: session route `GET /files/:id/variants/:name`, or server-key route `GET /api/v2/files/:id/variants/:name` requiring `files:read` and the file's application. API metadata includes `processingState`, `processingError` and ready `variants` with dimensions, type, byte size and URL. No arbitrary resize parameters or public transform URLs are accepted. Original content routes remain attachment downloads.

## Native runtime and limits

The host needs **Elixir/Erlang and Python 3** on PATH, including deployments using a release. The worker starts a separate Elixir VM with dependency code paths; Python's standard library supervises its process group, kills/reaps it on deadline or owner EOF, and bounds output to 64 KiB. No Python packages or Sharp/Node service are required. Vix's compatible native libvips artifact is fetched by the dependency; supported platforms may need a platform-specific native build.

Defaults: encoded input cap 50 MiB, 40 million input pixels, 16,384 px maximum dimension, 5 MiB per output, 10 seconds **per variant**, two concurrent image jobs, one libvips thread per child and disabled operation cache. Configurable limits: `IMAGE_MAX_INPUT_PIXELS`, `IMAGE_MAX_OUTPUT_BYTES`, `IMAGE_PROCESSING_TIMEOUT_MS`. Encoded size/pixel preflight happens before native decoding. Output size is checked after encoding. Temp directories are private; cleanup runs on normal completion. An abruptly killed job can leave a `serve-vars-*`/`serve-src-*` temporary path; use an operator-managed temporary-directory retention policy for old abandoned scratch files.

These are application bounds, **not a hard native RSS limit**. Set a deployment/container/systemd memory and disk cap appropriate to image processing; retain persistent original storage across restarts. Test extreme images under those deployment limits before production use. Do not expose original local storage through Phoenix static routes.

## Code map

- `lib/app/storage.ex`: authorized storage service and lifecycle orchestration.
- `lib/app/storage/quota.ex`: account counter row locks and reservations.
- `lib/app/storage/file_lock.ex`: dedicated per-file database lock.
- `lib/app/storage/image_processing.ex`: byte/header and image limits.
- `lib/app/storage/workers/`: image, cleanup and periodic reconciliation jobs.
- `priv/variant_runner.exs`, `priv/native_supervisor.py`: isolated native encoder and process lifetime.
- `lib/app_web/features/files/file_controller.ex`: private session downloads/previews.
- `lib/app_web/api/file_api_controller.ex`: scoped API metadata/previews.
- `lib/app_web/features/dashboard/`: Files UI, previews and usage display.

V1 SDK compatibility is out of scope. Explicit sharing, optional imports, public image delivery/CDN, transfers and backups remain separate milestones.
