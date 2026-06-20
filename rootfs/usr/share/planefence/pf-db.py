#!/command/with-contenv python3
"""
SQLite backend helper for Planefence/Plane-Alert record storage.

This utility is intentionally standalone and stdlib-only so it can run in the
existing container image without new dependencies.
"""

from __future__ import annotations

import argparse
import json
import platform
import sqlite3
import sys
import time
import gzip
from pathlib import Path
from typing import Dict


DEFAULT_DB_PATH = "/run/planefence/planefence-records.sqlite"


def _mem_total_mb() -> int:
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    parts = line.split()
                    if len(parts) >= 2:
                        return int(parts[1]) // 1024
    except Exception:
        return 0
    return 0


def select_profile() -> str:
    arch = platform.machine().lower()
    mem_mb = _mem_total_mb()
    if arch in ("armv7l", "armv6l", "aarch64"):
        if mem_mb and mem_mb <= 1300:
            return "pi3"
        return "pi45"
    return "x86"


def profile_settings(profile: str) -> Dict[str, int]:
    table = {
        "pi3": {
            "cache_mb": 8,
            "mmap_mb": 64,
            "wal_autocheckpoint_pages": 512,
            "busy_timeout_ms": 8000,
            "checkpoint_interval_sec": 600,
        },
        "pi45": {
            "cache_mb": 32,
            "mmap_mb": 256,
            "wal_autocheckpoint_pages": 1000,
            "busy_timeout_ms": 8000,
            "checkpoint_interval_sec": 300,
        },
        "x86": {
            "cache_mb": 64,
            "mmap_mb": 512,
            "wal_autocheckpoint_pages": 2000,
            "busy_timeout_ms": 10000,
            "checkpoint_interval_sec": 300,
        },
    }
    if profile not in table:
        raise ValueError(f"Unknown profile: {profile}")
    return table[profile]


def apply_pragmas(conn: sqlite3.Connection, settings: Dict[str, int]) -> None:
    cache_kib = settings["cache_mb"] * 1024
    mmap_bytes = settings["mmap_mb"] * 1024 * 1024

    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA temp_store=MEMORY")
    conn.execute(f"PRAGMA busy_timeout={int(settings['busy_timeout_ms'])}")
    conn.execute(f"PRAGMA cache_size=-{int(cache_kib)}")
    conn.execute(f"PRAGMA mmap_size={int(mmap_bytes)}")
    conn.execute(
        f"PRAGMA wal_autocheckpoint={int(settings['wal_autocheckpoint_pages'])}"
    )


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS db_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS globals_kv (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS pf_records (
          day_key TEXT NOT NULL,
          rec_index INTEGER NOT NULL,
          icao TEXT,
          callsign TEXT,
          time_firstseen INTEGER,
          time_lastseen INTEGER,
          ready_to_notify TEXT,
          complete TEXT,
          version INTEGER NOT NULL DEFAULT 1,
          updated_at INTEGER NOT NULL,
          payload_json TEXT NOT NULL,
          PRIMARY KEY (day_key, rec_index)
        );

        CREATE TABLE IF NOT EXISTS pa_records (
          day_key TEXT NOT NULL,
          rec_index INTEGER NOT NULL,
          icao TEXT,
          callsign TEXT,
          time_firstseen INTEGER,
          time_lastseen INTEGER,
          complete TEXT,
          version INTEGER NOT NULL DEFAULT 1,
          updated_at INTEGER NOT NULL,
          payload_json TEXT NOT NULL,
          PRIMARY KEY (day_key, rec_index)
        );

        CREATE TABLE IF NOT EXISTS heatmap (
          day_key TEXT NOT NULL,
          latlon_key TEXT NOT NULL,
          hit_count INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (day_key, latlon_key)
        );

                CREATE TABLE IF NOT EXISTS day_snapshots (
                    day_key TEXT PRIMARY KEY,
                    payload_text TEXT NOT NULL,
                    payload_format TEXT NOT NULL DEFAULT 'bash_declare_v1',
                    updated_at INTEGER NOT NULL
                );

        CREATE INDEX IF NOT EXISTS idx_pf_icao_day ON pf_records(icao, day_key);
        CREATE INDEX IF NOT EXISTS idx_pf_lastseen ON pf_records(time_lastseen);
        CREATE INDEX IF NOT EXISTS idx_pf_ready ON pf_records(ready_to_notify, complete);

        CREATE INDEX IF NOT EXISTS idx_pa_icao_day ON pa_records(icao, day_key);
        CREATE INDEX IF NOT EXISTS idx_pa_lastseen ON pa_records(time_lastseen);
        """
    )


def open_db(path: str) -> sqlite3.Connection:
    db_path = Path(path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=15, isolation_level=None)
    conn.row_factory = sqlite3.Row
    return conn


def cmd_init(args: argparse.Namespace) -> int:
    profile = args.profile or select_profile()
    settings = profile_settings(profile)

    if args.cache_mb is not None:
        settings["cache_mb"] = int(args.cache_mb)
    if args.mmap_mb is not None:
        settings["mmap_mb"] = int(args.mmap_mb)
    if args.busy_timeout_ms is not None:
        settings["busy_timeout_ms"] = int(args.busy_timeout_ms)
    if args.wal_autocheckpoint_pages is not None:
        settings["wal_autocheckpoint_pages"] = int(args.wal_autocheckpoint_pages)
    if args.checkpoint_interval_sec is not None:
        settings["checkpoint_interval_sec"] = int(args.checkpoint_interval_sec)

    now = int(time.time())
    with open_db(args.db) as conn:
        apply_pragmas(conn, settings)
        create_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            "INSERT OR REPLACE INTO db_meta(key, value) VALUES('schema_version', '1')"
        )
        conn.execute(
            "INSERT OR REPLACE INTO db_meta(key, value) VALUES('profile', ?)",
            (profile,),
        )
        conn.execute(
            "INSERT OR REPLACE INTO db_meta(key, value) VALUES('settings_json', ?)",
            (json.dumps(settings, separators=(",", ":")),),
        )
        conn.execute(
            "INSERT OR REPLACE INTO globals_kv(key, value, updated_at) VALUES('db:last_init', ?, ?)",
            (str(now), now),
        )
        conn.execute("COMMIT")

    print(json.dumps({"ok": True, "db": args.db, "profile": profile, "settings": settings}))
    return 0


def cmd_integrity_check(args: argparse.Namespace) -> int:
    with open_db(args.db) as conn:
        row = conn.execute("PRAGMA integrity_check").fetchone()
        result = "ok" if row else "unknown"
        if row:
            result = str(row[0])
    out = {"db": args.db, "integrity_check": result, "ok": result == "ok"}
    print(json.dumps(out))
    return 0 if out["ok"] else 2


def cmd_show_profile(args: argparse.Namespace) -> int:
    profile = args.profile or select_profile()
    settings = profile_settings(profile)
    print(json.dumps({"profile": profile, "settings": settings}))
    return 0


def cmd_save_day(args: argparse.Namespace) -> int:
    payload = sys.stdin.read()
    day_key = str(args.day).strip()
    if not day_key:
        print(json.dumps({"ok": False, "error": "day is required"}))
        return 2
    now = int(time.time())
    with open_db(args.db) as conn:
        apply_pragmas(
            conn,
            {
                "cache_mb": max(int(args.cache_mb or 8), 1),
                "mmap_mb": max(int(args.mmap_mb or 64), 1),
                "wal_autocheckpoint_pages": max(int(args.wal_autocheckpoint_pages or 512), 1),
                "busy_timeout_ms": max(int(args.busy_timeout_ms or 8000), 1),
                "checkpoint_interval_sec": max(int(args.checkpoint_interval_sec or 300), 1),
            },
        )
        create_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            """
            INSERT INTO day_snapshots(day_key, payload_text, payload_format, updated_at)
            VALUES(?, ?, 'bash_declare_v1', ?)
            ON CONFLICT(day_key) DO UPDATE SET
              payload_text=excluded.payload_text,
              payload_format=excluded.payload_format,
              updated_at=excluded.updated_at
            """,
            (day_key, payload, now),
        )
        conn.execute("COMMIT")
    print(json.dumps({"ok": True, "db": args.db, "day": day_key, "bytes": len(payload)}))
    return 0


def cmd_load_day(args: argparse.Namespace) -> int:
    day_key = str(args.day).strip()
    if not day_key:
        return 2
    with open_db(args.db) as conn:
        row = conn.execute(
            "SELECT payload_text FROM day_snapshots WHERE day_key=?",
            (day_key,),
        ).fetchone()
    if not row:
        return 3
    sys.stdout.write(str(row[0]))
    return 0


def cmd_migrate_legacy_day(args: argparse.Namespace) -> int:
    day_key = str(args.day).strip()
    legacy_gz = Path(args.legacy_gz)
    if not day_key or not legacy_gz.is_file():
        print(json.dumps({"ok": False, "day": day_key, "legacy_gz": str(legacy_gz), "error": "invalid input"}))
        return 2

    with open_db(args.db) as conn:
        create_schema(conn)
        existing = conn.execute(
            "SELECT 1 FROM day_snapshots WHERE day_key=?",
            (day_key,),
        ).fetchone()
        if existing and not args.force:
            print(json.dumps({"ok": True, "skipped": True, "reason": "snapshot_exists", "day": day_key}))
            return 0

    try:
        with gzip.open(legacy_gz, "rt", encoding="utf-8", errors="replace") as f:
            payload = f.read()
    except OSError as exc:
        print(json.dumps({"ok": False, "error": f"gzip_read_failed: {exc}", "legacy_gz": str(legacy_gz)}))
        return 2

    now = int(time.time())
    with open_db(args.db) as conn:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            """
            INSERT INTO day_snapshots(day_key, payload_text, payload_format, updated_at)
            VALUES(?, ?, 'bash_declare_v1', ?)
            ON CONFLICT(day_key) DO UPDATE SET
              payload_text=excluded.payload_text,
              payload_format=excluded.payload_format,
              updated_at=excluded.updated_at
            """,
            (day_key, payload, now),
        )
        conn.execute("COMMIT")

    print(json.dumps({"ok": True, "day": day_key, "legacy_gz": str(legacy_gz), "bytes": len(payload)}))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Planefence SQLite helper")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_init = sub.add_parser("init", help="initialize DB and schema")
    p_init.add_argument("--db", default=DEFAULT_DB_PATH)
    p_init.add_argument("--profile", choices=["pi3", "pi45", "x86"])
    p_init.add_argument("--cache-mb", type=int)
    p_init.add_argument("--mmap-mb", type=int)
    p_init.add_argument("--busy-timeout-ms", type=int)
    p_init.add_argument("--wal-autocheckpoint-pages", type=int)
    p_init.add_argument("--checkpoint-interval-sec", type=int)
    p_init.set_defaults(func=cmd_init)

    p_int = sub.add_parser("integrity-check", help="run PRAGMA integrity_check")
    p_int.add_argument("--db", default=DEFAULT_DB_PATH)
    p_int.set_defaults(func=cmd_integrity_check)

    p_profile = sub.add_parser("show-profile", help="print selected profile settings")
    p_profile.add_argument("--profile", choices=["pi3", "pi45", "x86"])
    p_profile.set_defaults(func=cmd_show_profile)

    p_save = sub.add_parser("save-day", help="store bash snapshot payload for a day")
    p_save.add_argument("--db", default=DEFAULT_DB_PATH)
    p_save.add_argument("--day", required=True)
    p_save.add_argument("--cache-mb", type=int)
    p_save.add_argument("--mmap-mb", type=int)
    p_save.add_argument("--busy-timeout-ms", type=int)
    p_save.add_argument("--wal-autocheckpoint-pages", type=int)
    p_save.add_argument("--checkpoint-interval-sec", type=int)
    p_save.set_defaults(func=cmd_save_day)

    p_load = sub.add_parser("load-day", help="print bash snapshot payload for a day")
    p_load.add_argument("--db", default=DEFAULT_DB_PATH)
    p_load.add_argument("--day", required=True)
    p_load.set_defaults(func=cmd_load_day)

    p_migrate = sub.add_parser("migrate-legacy-day", help="import one legacy gz day file")
    p_migrate.add_argument("--db", default=DEFAULT_DB_PATH)
    p_migrate.add_argument("--day", required=True)
    p_migrate.add_argument("--legacy-gz", required=True)
    p_migrate.add_argument("--force", action="store_true")
    p_migrate.set_defaults(func=cmd_migrate_legacy_day)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
