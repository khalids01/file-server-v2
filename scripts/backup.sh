#!/usr/bin/env bash
# Operator-initiated consistent backup. No secrets are read from .env or echoed.
set -euo pipefail
umask 077
: "${BACKUP_TARGET:?Set a NEW backup directory outside local storage}"
: "${LOCAL_STORAGE_PATH:?Set the private local storage root}"
: "${PGDATABASE:?Set the database explicitly}"
: "${PGUSER:?Set the database user explicitly}"
if [[ ${BACKUP_WRITES_PAUSED:-} != yes ]]; then
  echo 'Stop all application instances/workers and set BACKUP_WRITES_PAUSED=yes.' >&2
  exit 2
fi
python3 - "$LOCAL_STORAGE_PATH" "$BACKUP_TARGET" <<'PY'
import pathlib, sys
source, target = map(lambda p: pathlib.Path(p).resolve(), sys.argv[1:])
if not source.is_dir() or target.exists() or target == source or source in target.parents or target in source.parents:
    raise SystemExit('Storage must exist; backup must be a NEW directory outside the storage tree.')
PY
if [[ -z ${BACKUP_DOCKER_SERVICE:-} ]]; then
  : "${PGHOST:?Set the host explicitly}"
  : "${PGPORT:?Set the port explicitly}"
  command -v pg_dump >/dev/null
fi
parent=$(dirname -- "$BACKUP_TARGET")
mkdir -p -- "$parent"
stage=$(mktemp -d "$parent/.file-server-backup.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
if [[ -n ${BACKUP_DOCKER_SERVICE:-} ]]; then
  docker compose exec -T "$BACKUP_DOCKER_SERVICE" pg_dump -U "$PGUSER" -d "$PGDATABASE" --format=custom > "$stage/database.dump"
else
  pg_dump --format=custom > "$stage/database.dump"
fi
tar -C "$LOCAL_STORAGE_PATH" -czf "$stage/local-storage.tar.gz" .
printf 'File Server v2 operator backup\nCreated UTC: %s\nIncludes PostgreSQL and local files; S3 objects and encryption keys require separate backups.\n' "$(date -u +%FT%TZ)" > "$stage/README.txt"
(cd "$stage" && sha256sum database.dump local-storage.tar.gz > SHA256SUMS)
# Refuse overwrite, including if another backup raced us. mv -T prevents nesting.
if [[ -e $BACKUP_TARGET ]]; then echo 'Backup target already exists.' >&2; exit 2; fi
mv -T -n -- "$stage" "$BACKUP_TARGET"
if [[ -d $stage ]]; then echo 'Backup target was created concurrently.' >&2; exit 2; fi
trap - EXIT
printf 'Backup created. Verify SHA256SUMS and rehearse restore in an isolated environment.\n'
