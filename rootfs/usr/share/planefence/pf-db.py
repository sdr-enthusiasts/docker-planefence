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
import shlex
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


def _bash_quote(value: str) -> str:
    return shlex.quote(str(value))


def _emit_bash_assoc(name: str, mapping: Dict[str, str]) -> str:
    items = []
    for k in sorted(mapping.keys()):
        items.append(f"[{_bash_quote(k)}]={_bash_quote(mapping[k])}")
    return f"declare -Ag {name}=({ ' '.join(items) })"


def cmd_load_day_state(args: argparse.Namespace) -> int:
    day_key = str(args.day).strip()
    if not day_key:
        return 2

    records: Dict[str, str] = {}
    pa_records: Dict[str, str] = {}
    heatmap: Dict[str, str] = {}
    last_idx_for_icao: Dict[str, str] = {}
    lastseen_for_icao: Dict[str, str] = {}
    pa_last_idx_for_icao: Dict[str, str] = {}
    last_processed_line = ""

    with open_db(args.db) as conn:
        # PF rows
        pf_rows = conn.execute(
            "SELECT rec_index, payload_json FROM pf_records WHERE day_key=?",
            (day_key,),
        ).fetchall()
        pf_max_idx = -1
        pf_seen: Dict[str, tuple[int, int]] = {}
        for row in pf_rows:
            rec_index = int(row[0])
            pf_max_idx = max(pf_max_idx, rec_index)
            payload = _load_json_payload(row[1])
            for key, value in payload.items():
                records[f"{rec_index}:{key}"] = value
            icao = payload.get("icao", "")
            ts = _to_int(payload.get("time:lastseen", "")) or 0
            if icao:
                prev = pf_seen.get(icao)
                if prev is None or ts >= prev[1]:
                    pf_seen[icao] = (rec_index, ts)

        # PA rows
        pa_rows = conn.execute(
            "SELECT rec_index, payload_json FROM pa_records WHERE day_key=?",
            (day_key,),
        ).fetchall()
        pa_max_idx = -1
        pa_seen: Dict[str, tuple[int, int]] = {}
        for row in pa_rows:
            rec_index = int(row[0])
            pa_max_idx = max(pa_max_idx, rec_index)
            payload = _load_json_payload(row[1])
            for key, value in payload.items():
                pa_records[f"{rec_index}:{key}"] = value
            icao = payload.get("icao", "")
            ts = _to_int(payload.get("time:lastseen", "")) or 0
            if icao:
                prev = pa_seen.get(icao)
                if prev is None or ts >= prev[1]:
                    pa_seen[icao] = (rec_index, ts)

        # Heatmap rows
        hm_rows = conn.execute(
            "SELECT latlon_key, hit_count FROM heatmap WHERE day_key=?",
            (day_key,),
        ).fetchall()
        for row in hm_rows:
            heatmap[str(row[0])] = str(int(row[1]))

        # Globals used by existing shell paths
        g_rows = conn.execute(
            "SELECT key, value FROM globals_kv WHERE key IN (?, ?, ?, ?, ?)",
            (
                "LASTPROCESSEDLINE",
                "records:maxindex",
                "pa_records:maxindex",
                "records:LASTUPDATE",
                "pa_records:LASTUPDATE",
            ),
        ).fetchall()
        g = {str(r[0]): str(r[1]) for r in g_rows}

        records["maxindex"] = g.get("records:maxindex", str(pf_max_idx))
        pa_records["maxindex"] = g.get("pa_records:maxindex", str(pa_max_idx))
        if "records:LASTUPDATE" in g:
            records["LASTUPDATE"] = g["records:LASTUPDATE"]
        if "pa_records:LASTUPDATE" in g:
            pa_records["LASTUPDATE"] = g["pa_records:LASTUPDATE"]
        last_processed_line = g.get("LASTPROCESSEDLINE", "")

        for icao, (idx, ts) in pf_seen.items():
            last_idx_for_icao[icao] = str(idx)
            lastseen_for_icao[icao] = str(ts)
        for icao, (idx, _ts) in pa_seen.items():
            pa_last_idx_for_icao[icao] = str(idx)

    # No row-table state found for the day
    if len(pf_rows) == 0 and len(pa_rows) == 0 and len(hm_rows) == 0:
        return 3

    output = [
        _emit_bash_assoc("records", records),
        _emit_bash_assoc("heatmap", heatmap),
        _emit_bash_assoc("last_idx_for_icao", last_idx_for_icao),
        _emit_bash_assoc("lastseen_for_icao", lastseen_for_icao),
        _emit_bash_assoc("pa_records", pa_records),
        _emit_bash_assoc("pa_last_idx_for_icao", pa_last_idx_for_icao),
        f"LASTPROCESSEDLINE={_bash_quote(last_processed_line)}",
    ]
    sys.stdout.write("\n".join(output) + "\n")
    return 0


def cmd_delete_old_snapshots(args: argparse.Namespace) -> int:
    before_day = str(args.before_day).strip()
    if not before_day or not before_day.isdigit() or len(before_day) != 6:
        print(json.dumps({"ok": False, "error": "before_day must be 6 digits (YYMMDD)"}))
        return 2
    with open_db(args.db) as conn:
        cur = conn.execute(
            "DELETE FROM day_snapshots WHERE day_key < ?",
            (before_day,),
        )
        deleted = cur.rowcount
    print(json.dumps({"ok": True, "db": args.db, "before_day": before_day, "deleted": deleted}))
    return 0


def cmd_restore_or_init(args: argparse.Namespace) -> int:
    """
    Integrity-gated startup restore for the sqlite backend.

    Resolution order:
      1. If runtime DB exists and passes integrity_check → keep it in place, done.
      2. Else if a persist DB exists and passes integrity_check → copy it to runtime path.
      3. Else scan legacy gz day files and import any that exist (best-effort recovery).
      4. Always run init to ensure schema/pragmas are current.
      5. Return 0 on success (including a clean-init fallback), non-zero only on hard failure.
    """
    runtime_db = Path(args.db)
    persist_db = Path(args.persist_db)
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

    def db_ok(path: Path) -> bool:
        if not path.is_file() or path.stat().st_size == 0:
            return False
        try:
            with open_db(str(path)) as c:
                row = c.execute("PRAGMA integrity_check").fetchone()
                return bool(row and str(row[0]).lower() == "ok")
        except Exception:
            return False

    source = "none"
    if db_ok(runtime_db):
        source = "runtime_ok"
    elif db_ok(persist_db):
        runtime_db.parent.mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(str(persist_db), str(runtime_db))
        source = "persist_restored"
    else:
        # Remove any corrupt file so init starts clean
        runtime_db.unlink(missing_ok=True)
        source = "clean_init"

    # Always ensure schema + pragmas are up to date
    now = int(time.time())
    with open_db(str(runtime_db)) as conn:
        apply_pragmas(conn, settings)
        create_schema(conn)
        conn.execute("BEGIN IMMEDIATE")
        conn.execute("INSERT OR REPLACE INTO db_meta(key,value) VALUES('schema_version','1')")
        conn.execute("INSERT OR REPLACE INTO db_meta(key,value) VALUES('profile',?)", (profile,))
        conn.execute(
            "INSERT OR REPLACE INTO globals_kv(key,value,updated_at) VALUES('db:last_restore_or_init',?,?)",
            (str(now), now),
        )
        conn.execute("COMMIT")

    # If we got here via clean_init, opportunistically import legacy day files
    if source == "clean_init" and args.legacy_records_dir:
        import glob as glob_mod
        pattern = str(Path(args.legacy_records_dir) / "planefence-records-*.gz")
        for legacy_gz in sorted(glob_mod.glob(pattern)):
            p = Path(legacy_gz)
            day_key = p.stem.replace("planefence-records-", "")
            if not day_key.isdigit() or len(day_key) != 6:
                continue
            try:
                with gzip.open(legacy_gz, "rt", encoding="utf-8", errors="replace") as f:
                    payload = f.read()
                with open_db(str(runtime_db)) as conn:
                    conn.execute("BEGIN IMMEDIATE")
                    conn.execute(
                        """INSERT OR IGNORE INTO day_snapshots(day_key,payload_text,payload_format,updated_at)
                           VALUES(?,?,'bash_declare_v1',?)""",
                        (day_key, payload, now),
                    )
                    conn.execute("COMMIT")
            except Exception:
                pass

    print(json.dumps({"ok": True, "db": str(runtime_db), "source": source, "profile": profile}))
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


def _to_int(value: str) -> int | None:
    try:
        return int(str(value))
    except Exception:
        return None


def _load_json_payload(raw: str | None) -> Dict[str, str]:
    if not raw:
        return {}
    try:
        decoded = json.loads(raw)
        if isinstance(decoded, dict):
            return {str(k): str(v) for k, v in decoded.items()}
    except Exception:
        return {}
    return {}


def cmd_sync_hot_data(args: argparse.Namespace) -> int:
    day_key = str(args.day).strip()
    if not day_key:
        print(json.dumps({"ok": False, "error": "day is required"}))
        return 2

    pf_updates: Dict[int, Dict[str, str]] = {}
    pa_updates: Dict[int, Dict[str, str]] = {}
    heatmap_updates: Dict[str, int] = {}
    global_updates: Dict[str, str] = {}

    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if not parts:
            continue
        tag = parts[0]

        if tag in ("PF", "PA"):
            if len(parts) < 4:
                continue
            idx = _to_int(parts[1])
            if idx is None or idx < 0:
                continue
            field = parts[2]
            value = "\t".join(parts[3:])
            target = pf_updates if tag == "PF" else pa_updates
            rec = target.setdefault(idx, {})
            rec[field] = value
        elif tag == "HM":
            if len(parts) < 3:
                continue
            latlon_key = parts[1]
            hit_count = _to_int(parts[2])
            if not latlon_key or hit_count is None:
                continue
            heatmap_updates[latlon_key] = hit_count
        elif tag == "G":
            if len(parts) < 3:
                continue
            key = parts[1]
            value = "\t".join(parts[2:])
            if key:
                global_updates[key] = value

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

        for rec_index, delta in pf_updates.items():
            existing = conn.execute(
                "SELECT payload_json FROM pf_records WHERE day_key=? AND rec_index=?",
                (day_key, rec_index),
            ).fetchone()
            merged = _load_json_payload(existing[0] if existing else None)
            merged.update(delta)

            conn.execute(
                """
                INSERT INTO pf_records(
                  day_key, rec_index, icao, callsign, time_firstseen, time_lastseen,
                  ready_to_notify, complete, updated_at, payload_json
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(day_key, rec_index) DO UPDATE SET
                  icao=excluded.icao,
                  callsign=excluded.callsign,
                  time_firstseen=excluded.time_firstseen,
                  time_lastseen=excluded.time_lastseen,
                  ready_to_notify=excluded.ready_to_notify,
                  complete=excluded.complete,
                  updated_at=excluded.updated_at,
                  payload_json=excluded.payload_json,
                  version=pf_records.version + 1
                """,
                (
                    day_key,
                    rec_index,
                    merged.get("icao"),
                    merged.get("callsign"),
                    _to_int(merged.get("time:firstseen", "")),
                    _to_int(merged.get("time:lastseen", "")),
                    merged.get("ready_to_notify"),
                    merged.get("complete"),
                    now,
                    json.dumps(merged, separators=(",", ":"), ensure_ascii=False),
                ),
            )

        for rec_index, delta in pa_updates.items():
            existing = conn.execute(
                "SELECT payload_json FROM pa_records WHERE day_key=? AND rec_index=?",
                (day_key, rec_index),
            ).fetchone()
            merged = _load_json_payload(existing[0] if existing else None)
            merged.update(delta)

            conn.execute(
                """
                INSERT INTO pa_records(
                  day_key, rec_index, icao, callsign, time_firstseen, time_lastseen,
                  complete, updated_at, payload_json
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(day_key, rec_index) DO UPDATE SET
                  icao=excluded.icao,
                  callsign=excluded.callsign,
                  time_firstseen=excluded.time_firstseen,
                  time_lastseen=excluded.time_lastseen,
                  complete=excluded.complete,
                  updated_at=excluded.updated_at,
                  payload_json=excluded.payload_json,
                  version=pa_records.version + 1
                """,
                (
                    day_key,
                    rec_index,
                    merged.get("icao"),
                    merged.get("callsign"),
                    _to_int(merged.get("time:firstseen", "")),
                    _to_int(merged.get("time:lastseen", "")),
                    merged.get("complete"),
                    now,
                    json.dumps(merged, separators=(",", ":"), ensure_ascii=False),
                ),
            )

        for latlon_key, hit_count in heatmap_updates.items():
            conn.execute(
                """
                INSERT INTO heatmap(day_key, latlon_key, hit_count, updated_at)
                VALUES(?, ?, ?, ?)
                ON CONFLICT(day_key, latlon_key) DO UPDATE SET
                  hit_count=excluded.hit_count,
                  updated_at=excluded.updated_at
                """,
                (day_key, latlon_key, hit_count, now),
            )

        for key, value in global_updates.items():
            conn.execute(
                """
                INSERT INTO globals_kv(key, value, updated_at)
                VALUES(?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                  value=excluded.value,
                  updated_at=excluded.updated_at
                """,
                (key, value, now),
            )

        conn.execute("COMMIT")

    print(
        json.dumps(
            {
                "ok": True,
                "db": args.db,
                "day": day_key,
                "pf_rows": len(pf_updates),
                "pa_rows": len(pa_updates),
                "heatmap_rows": len(heatmap_updates),
                "globals": len(global_updates),
            }
        )
    )
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

    p_del = sub.add_parser("delete-old-snapshots", help="purge day snapshots older than a day key")
    p_del.add_argument("--db", default=DEFAULT_DB_PATH)
    p_del.add_argument("--before-day", required=True)
    p_del.set_defaults(func=cmd_delete_old_snapshots)

    p_restore = sub.add_parser("restore-or-init", help="integrity-gated startup restore/init")
    p_restore.add_argument("--db", default=DEFAULT_DB_PATH)
    p_restore.add_argument("--persist-db", default="/usr/share/planefence/persist/records/planefence-records.sqlite")
    p_restore.add_argument("--legacy-records-dir", default="")
    p_restore.add_argument("--profile", choices=["pi3", "pi45", "x86"])
    p_restore.add_argument("--cache-mb", type=int)
    p_restore.add_argument("--mmap-mb", type=int)
    p_restore.add_argument("--busy-timeout-ms", type=int)
    p_restore.add_argument("--wal-autocheckpoint-pages", type=int)
    p_restore.add_argument("--checkpoint-interval-sec", type=int)
    p_restore.set_defaults(func=cmd_restore_or_init)

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

    p_state = sub.add_parser("load-day-state", help="materialize bash state from sqlite row tables")
    p_state.add_argument("--db", default=DEFAULT_DB_PATH)
    p_state.add_argument("--day", required=True)
    p_state.set_defaults(func=cmd_load_day_state)

    p_migrate = sub.add_parser("migrate-legacy-day", help="import one legacy gz day file")
    p_migrate.add_argument("--db", default=DEFAULT_DB_PATH)
    p_migrate.add_argument("--day", required=True)
    p_migrate.add_argument("--legacy-gz", required=True)
    p_migrate.add_argument("--force", action="store_true")
    p_migrate.set_defaults(func=cmd_migrate_legacy_day)

    p_hot = sub.add_parser("sync-hot-data", help="upsert touched PF/PA/heatmap rows from stdin")
    p_hot.add_argument("--db", default=DEFAULT_DB_PATH)
    p_hot.add_argument("--day", required=True)
    p_hot.add_argument("--cache-mb", type=int)
    p_hot.add_argument("--mmap-mb", type=int)
    p_hot.add_argument("--busy-timeout-ms", type=int)
    p_hot.add_argument("--wal-autocheckpoint-pages", type=int)
    p_hot.add_argument("--checkpoint-interval-sec", type=int)
    p_hot.set_defaults(func=cmd_sync_hot_data)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
