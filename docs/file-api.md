# Application file API (v2)

Use an application key on a trusted server. Application context always comes from
the key. Each request rechecks expiry, revocation, account bans and application
ownership. The key cannot access another application's files, even for the same
owner. Dashboard sessions cannot authenticate these routes.

Send `Authorization: Bearer <key>` or `X-API-Key: <key>`, using one header only.
Never put keys in URLs or frontend JavaScript. Browser Origin/Sec-Fetch-Site
requests are rejected. Responses use `Cache-Control: private, no-store`.

| Method | Route | Scope | Result |
| --- | --- | --- | --- |
| GET | `/api/v2/application` | `files:read` | Application identity and capabilities |
| GET | `/api/v2/files` | `files:read` | Paginated metadata |
| POST | `/api/v2/files` | `files:write` | Store one multipart file (201) |
| GET | `/api/v2/files/:id` | `files:read` | File metadata |
| GET | `/api/v2/files/:id/content` | `files:read` | Private attachment download |
| DELETE | `/api/v2/files/:id` | `files:delete` | Permanent file/object deletion |

## Try it

Create a read/write/delete key in an application's API keys tab. Set
`SERVE_APPLICATION_KEY` in your shell without committing it. With the server
running at localhost:4000:

```bash
curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  -F 'file=@/absolute/path/to/example.txt' \
  http://localhost:4000/api/v2/files

curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  'http://localhost:4000/api/v2/files?page=1&limit=20&search=example'

curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  http://localhost:4000/api/v2/files/FILE_ID

curl -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  --output downloaded.txt \
  http://localhost:4000/api/v2/files/FILE_ID/content

curl -X DELETE -H "Authorization: Bearer $SERVE_APPLICATION_KEY" \
  http://localhost:4000/api/v2/files/FILE_ID
```

Upload uses the application's current default local/S3 destination. Existing files
retain their original location. Send exactly one non-empty multipart `file`
field; duplicate files and extra fields (including application/destination IDs)
are rejected. `MAX_FILE_SIZE_MB` applies. Overall multipart parsing is bounded to
that limit plus 1 MiB of overhead, after credential/scope validation.

List accepts `page` (1–100000), `limit` (1–100, default 20) and optional literal
filename `search` (up to 200 bytes). Results sort newest first with ID as a stable
tiebreaker. It returns `data` plus `pagination` containing `page`, `limit`, `total`,
`pages`, `hasNext`, `hasPrev`. Concurrent writes can change totals between requests.

Upload and metadata responses wrap this object in `data`:

```json
{
  "id": "file-uuid",
  "applicationId": "application-uuid",
  "filename": "example.txt",
  "contentType": "text/plain",
  "sizeBytes": 123,
  "createdAt": "2026-11-13T10:00:00.000000Z",
  "urls": {"content": "/api/v2/files/file-uuid/content"}
}
```

`urls.content` is relative to the API origin and requires the read key. Downloads
are `application/octet-stream` attachments with nosniff and sandbox headers;
S3 content is privately proxied through a bounded temporary file. Content type in
metadata is supplied by the upload client and is not a guarantee of file contents.
Storage keys, credentials and server paths are never included in metadata.

Delete returns `{"data":{"id":"file-uuid","deleted":true}}`. Storage failures
keep metadata available for retry. There is no trash or undo for API deletion.

## Errors and limits

Errors use `{"error":{"code":"CODE","message":"Description"}}`.

- 400: `INVALID_UPLOAD` or `INVALID_QUERY`.
- 401: `INVALID_API_KEY` (missing, malformed, expired, revoked, banned).
- 403: `INSUFFICIENT_SCOPE` or `SERVER_CREDENTIAL_REQUIRED`.
- 404: `FILE_NOT_FOUND`, also used for inaccessible application files.
- 413: `FILE_TOO_LARGE`.
- 415: `INVALID_UPLOAD` for unsupported request content type.
- 429: `RATE_LIMITED`, with `Retry-After: 60`.
- 503: `STORAGE_UNAVAILABLE` when upload/delete cannot reach the destination.

Limits are 120 requests/minute/key and 300 requests/minute/IP. These use shared
PostgreSQL counters, so multiple app nodes enforce the same limit. File writes
still require future quota/reconciliation work documented in the storage milestone.

## Compatibility

This is the v2 private file contract. The existing v1 SDK uses `/api/v1` and also
expects tags, image dimensions/variants, transforms and delivery URL behavior.
Those contracts are not implemented here. No v1 aliases or public file URLs are
introduced. `/api/v2/application` advertises `storage_ready: true`, `api_version:
"v2"`, and `sdk_v1_compatible: false`. V1 SDK conformance and migration remain a
separate milestone; do not point an unchanged v1 SDK at these routes yet.
