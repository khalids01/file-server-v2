#!/usr/bin/env python3
"""Disposable Compose-db rehearsal. Never accepts a production URL or credentials."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ["docker", "compose", "exec", "-T", "db"]
os.chdir(ROOT)
os.umask(0o077)

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def db(*args, **kwargs):
    return run(COMPOSE + list(args), **kwargs)

port = subprocess.check_output(["docker", "compose", "port", "db", "5432"], text=True).strip()
if port != "127.0.0.1:5434":
    raise SystemExit("Rehearsal requires the disposable Compose database on 127.0.0.1:5434.")
suffix = uuid.uuid4().hex[:12]
source_db, restored_db = "ops_source_" + suffix, "ops_restore_" + suffix
try:
    with tempfile.TemporaryDirectory(prefix="serve-backup-rehearsal-") as temp:
        root = Path(temp)
        schema = root / "fixture.dump"
        with schema.open("wb") as output:
            db("pg_dump", "-U", "postgres", "-d", "app_test", "--format=custom", stdout=output)
        db("createdb", "-U", "postgres", source_db)
        with schema.open("rb") as data:
            db("pg_restore", "-U", "postgres", "-d", source_db, "--no-owner", "--no-privileges", stdin=data, stdout=subprocess.DEVNULL)
        owner, app, file_id = [str(uuid.uuid4()) for _ in range(3)]
        key = f"{owner}/{app}/{file_id}"
        payload = b"original bytes survive a database and local storage restore\n"
        storage = root / "storage"
        path = storage / key
        path.parent.mkdir(parents=True)
        path.write_bytes(payload)
        path.chmod(0o600)
        sql = f"""
        INSERT INTO users (id,email,confirmed_at) VALUES ('{owner}','backup-{suffix}@example.test',now());
        INSERT INTO applications (id,name,slug,user_id) VALUES ('{app}','Backup fixture','backup-{suffix}','{owner}');
        INSERT INTO stored_files (id,filename,size,content_type,object_key,application_id,user_id,ready_at)
        VALUES ('{file_id}','fixture.txt',{len(payload)},'text/plain','{key}','{app}','{owner}',now());
        INSERT INTO account_storage (user_id,quota_bytes,used_bytes,reserved_bytes) VALUES ('{owner}',100000,{len(payload)},0);
        """
        db("psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", source_db, input=sql.encode(), stdout=subprocess.DEVNULL)
        backup = root / "backup"
        env = dict(os.environ, BACKUP_TARGET=str(backup), LOCAL_STORAGE_PATH=str(storage), PGDATABASE=source_db,
                   PGUSER="postgres", BACKUP_DOCKER_SERVICE="db", BACKUP_WRITES_PAUSED="yes")
        run(["bash", "scripts/backup.sh"], env=env)
        run(["sha256sum", "-c", "SHA256SUMS"], cwd=backup)
        assert all((backup / name).stat().st_mode & 0o077 == 0 for name in ("database.dump", "local-storage.tar.gz", "SHA256SUMS"))
        # The backup tool must refuse both overwrite and recursive targets.
        for target in (backup, storage / "bad-backup"):
            failed = subprocess.run(["bash", "scripts/backup.sh"], env=dict(env, BACKUP_TARGET=str(target)), capture_output=True)
            assert failed.returncode != 0, "unsafe destination accepted"
        db("createdb", "-U", "postgres", restored_db)
        with (backup / "database.dump").open("rb") as data:
            db("pg_restore", "-U", "postgres", "-d", restored_db, "--no-owner", "--no-privileges", stdin=data, stdout=subprocess.DEVNULL)
        destination = root / "restored-files"
        destination.mkdir()
        with tarfile.open(backup / "local-storage.tar.gz") as archive:
            archive.extractall(destination, filter="data")
        assert hashlib.sha256((destination / key).read_bytes()).digest() == hashlib.sha256(payload).digest()
        verify = f"""DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM stored_files WHERE id='{file_id}' AND object_key='{key}' AND size={len(payload)}) THEN RAISE EXCEPTION 'file metadata mismatch'; END IF;
          IF NOT EXISTS (SELECT 1 FROM account_storage WHERE user_id='{owner}' AND used_bytes={len(payload)} AND reserved_bytes=0) THEN RAISE EXCEPTION 'quota mismatch'; END IF;
        END $$;"""
        db("psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", restored_db, input=verify.encode(), stdout=subprocess.DEVNULL)
        print("PASS: complete schema/data restore, local bytes/checksum, quota counters, private permissions and unsafe-target rejection")
finally:
    for database in (restored_db, source_db):
        subprocess.run(COMPOSE + ["dropdb", "-U", "postgres", "--if-exists", database], stdout=subprocess.DEVNULL, check=False)
