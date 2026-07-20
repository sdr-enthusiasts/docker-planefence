#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# PF-PROCESS_SBS (SQLite-backed, zero-dependency rewrite)
# Uses urllib instead of requests. No pip install needed.
# Fixes: incremental processing, memory growth, re-enrichment, state fragility.
# Copyright 2020-2026 Ramon F. Kolb (kx1t) - licensed GPLv3.
# ---------------------------------------------------------------------------

import os
import sys
import glob
import time
import fcntl
import json
import csv
import gzip
import re
import shutil
import tempfile
import subprocess
import sqlite3
import urllib.request
import urllib.error
from datetime import datetime, timedelta
from collections import defaultdict
from contextlib import contextmanager

DEBUG = os.environ.get("DEBUG", "false").lower() in ("true", "on", "1", "yes")

OUTFILEDIR = os.environ.get("OUTFILEDIR", "/usr/share/planefence/html")
HTMLDIR = OUTFILEDIR
RUN_PF_DIR = "/run/planefence"
NOISEDIR = os.path.join(OUTFILEDIR, "noise")
JS_DIR = os.path.join(OUTFILEDIR, "js")
PERSIST_DIR = "/usr/share/planefence/persist"
CACHE_DIR = os.path.join(PERSIST_DIR, ".internal")
PLANEPIX_CACHE = os.path.join(PERSIST_DIR, "planepix", "cache")
RECORDS_DIR = os.path.join(PERSIST_DIR, "records")
CONFIG_FILE = "/usr/share/planefence/planefence.conf"
PA_CONFIG_FILE = "/usr/share/planefence/plane-alert.conf"
SOCKET_DIR = "/run/socket30003"
DB_PATH = os.path.join(PERSIST_DIR, "planefence.db")

for d in [HTMLDIR, RUN_PF_DIR, NOISEDIR, JS_DIR, CACHE_DIR, PLANEPIX_CACHE, RECORDS_DIR]:
    os.makedirs(d, exist_ok=True)

TODAY = datetime.now()
YESTERDAY = TODAY - timedelta(days=1)
NOWTIME = int(time.time())
MIDNIGHT_EPOCH = int(datetime(TODAY.year, TODAY.month, TODAY.day).timestamp())
TODAY_STR = TODAY.strftime("%y%m%d")
YESTERDAY_STR = YESTERDAY.strftime("%y%m%d")
TODAY_YMD = TODAY.strftime("%Y/%m/%d")
TRACEDATE = TODAY.strftime("%Y-%m-%d")
TODAY_ISO = TODAY.strftime("%Y-%m-%d")

VERSION = os.environ.get("VERSION", "")
VERSION += "-" if VERSION else ""
if os.path.exists("/.VERSION"):
    with open("/.VERSION") as f:
        VERSION += f.read().strip()
else:
    VERSION += "build_unknown"

def load_config():
    config = {}
    for fname, prefix in [(CONFIG_FILE, ""), (PA_CONFIG_FILE, "pa_")]:
        if os.path.exists(fname):
            with open(fname, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        val = v.split("#")[0].strip()
                        config[prefix + k.strip()] = val.strip(' \t\n\r"\'')
    for k, v in os.environ.items():
        config[k] = v
    return config

CONFIG = load_config()
def get_env(key, default=None):
    return CONFIG.get(key, default)

def is_true(val):
    return str(val).lower() in ("true", "on", "1", "yes", "enabled")

COLLAPSEWITHIN = int(get_env("COLLAPSEWITHIN", "600"))
DIST = float(get_env("DIST", "999999"))
MAXALT = float(get_env("MAXALT", "999999"))
DISTUNIT = get_env("DISTUNIT", "nm")
ALTUNIT = get_env("ALTUNIT", "ft")
ALTREF = get_env("ALTREF", "MSL")
SPEEDUNIT = get_env("SPEEDUNIT", "kts")
PLANEFENCE = is_true(get_env("PLANEFENCE", "true"))
PLANEALERT = is_true(get_env("PLANEALERT", "true"))
SHOWIMAGES = is_true(get_env("SHOWIMAGES", "true"))
REMOTENOISE = get_env("REMOTENOISE", "")
TWEET_MINTIME = int(get_env("TWEET_MINTIME", "0")) if get_env("TWEET_MINTIME") else 0
TWEET_BEHAVIOR = get_env("TWEET_BEHAVIOR", "").lower()
YELLOWLIMIT = int(get_env("YELLOWLIMIT", "10"))
GREENLIMIT = int(get_env("GREENLIMIT", "5"))
IGNOREDUPES = is_true(get_env("IGNOREDUPES", "false"))
CHECKROUTE = is_true(get_env("CHECKROUTE", "true"))
GENERATE_CSV = is_true(get_env("GENERATE_CSV", "false"))
FUDGELOC = int(get_env("FUDGELOC", "3"))
HEATMAPZOOM = get_env("HEATMAPZOOM", "10")
MY = get_env("MY", "")
MYURL = get_env("MYURL", "")
HISTTIME = get_env("HISTTIME", "24")
PF_MOTD = get_env("PF_MOTD", "")
PA_MOTD = get_env("PA_MOTD", "")
LAT = float(get_env("LAT", "0.0"))
LON = float(get_env("LON", "0.0"))
PA_FILE = get_env("PA_FILE", "/usr/share/planefence/persist/.internal/plane-alert-db.txt")
PA_RANGE = float(get_env("pa_RANGE", "999999"))
SQUAWKTIME = int(get_env("pa_SQUAWKTIME", "10"))
MAXSPREAD = int(get_env("MAXSPREAD", "15"))
SQUAWKS_STR = get_env("pa_SQUAWKS", "")
PA_ALERTHEADER = get_env("pa_ALERTHEADER", "")

SQUAWKS_REGEX = None
if SQUAWKS_STR:
    parts = [p.strip() for p in SQUAWKS_STR.split(",") if p.strip()]
    if parts:
        SQUAWKS_REGEX = re.compile("|".join(parts))

TRACKSERVICE = get_env("TRACKSERVICE", "adsbexchange").lower()
if TRACKSERVICE == "adsbexchange":
    TRACKURL = "https://globe.adsbexchange.com"
elif TRACKSERVICE == "adsb.lol":
    TRACKURL = "https://adsb.lol"
elif TRACKSERVICE == "airplanes.live":
    TRACKURL = "https://globe.airplanes.live"
elif TRACKSERVICE == "flightaware":
    TRACKURL = "https://flightaware.com/live/flight"
else:
    TRACKURL = TRACKSERVICE if TRACKSERVICE.startswith("http") else f"http://{TRACKSERVICE}"

IGNORELIST = get_env("IGNORELIST", "")
ignore_set = set()
if IGNORELIST and os.path.exists(IGNORELIST):
    with open(IGNORELIST, "r") as f:
        for line in f:
            icao = line.strip().upper()
            if icao:
                ignore_set.add(icao)

OPENSKY_COLS = {"icao24": -1, "typecode": -1}

UI_KEY_MAP = {
    "icao": "icao", "callsign": "callsign", "tail": "tail", "type": "type",
    "owner": "owner", "lat": "lat", "lon": "lon",
    "time:firstseen": "firstseen", "time:lastseen": "lastseen",
    "distance:value": "dist", "distance:unit": "dist_unit",
    "altitude:value": "alt", "altitude:unit": "alt_unit",
    "squawk:value": "squawk", "squawk:description": "squawk_desc",
    "track": "heading", "angle": "direction", "speed": "speed",
    "nominatim": "location", "route": "route",
    "ready_to_notify": "ready_to_notify", "notified": "notified",
    "image:thumblink": "image", "image:link": "imagelink",
    "sound:peak": "noise_peak", "sound:1hour": "noise_1h",
    "sound:loudness": "noise_loudness", "sound:color": "noise_color",
}

def log_print(level, msg):
    if level == "DEBUG" and not DEBUG:
        return
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [{level}] {msg}", flush=True)

# ---------------------------------------------------------------------------
# urllib helpers (replaces requests)
# ---------------------------------------------------------------------------
def http_get(url, timeout=10, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return 0, b""

def http_post_json(url, data, timeout=10):
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/json",
        "Accept": "application/json"
    }, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return 0, b""

# ---------------------------------------------------------------------------
# SQLite Database Layer
# ---------------------------------------------------------------------------
SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS planefence (
    id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, icao TEXT NOT NULL,
    callsign TEXT, tail TEXT, type TEXT, owner TEXT, lat REAL, lon REAL,
    lat_min REAL, lon_min REAL, dist REAL, dist_unit TEXT DEFAULT 'nm',
    alt REAL, alt_unit TEXT DEFAULT 'ft', alt_ref TEXT DEFAULT 'MSL',
    firstseen INTEGER, lastseen INTEGER, time_at_min_dist INTEGER,
    squawk TEXT, squawk_desc TEXT, heading REAL, direction TEXT,
    speed REAL, speed_unit TEXT DEFAULT 'kts',
    enriched_tail INTEGER DEFAULT 0, enriched_type INTEGER DEFAULT 0,
    enriched_callsign INTEGER DEFAULT 0, enriched_owner INTEGER DEFAULT 0,
    enriched_image INTEGER DEFAULT 0, enriched_noise INTEGER DEFAULT 0,
    enriched_route INTEGER DEFAULT 0, enriched_nominatim INTEGER DEFAULT 0,
    enriched_at INTEGER, location TEXT, route TEXT,
    image_thumb TEXT, image_link TEXT, image_file TEXT,
    noise_peak REAL, noise_1h REAL, noise_loudness REAL, noise_color TEXT,
    noisegraph_file TEXT, spectro_file TEXT, mp3_file TEXT,
    complete INTEGER DEFAULT 0, ready_to_notify INTEGER DEFAULT 0, notified INTEGER DEFAULT 0,
    link_map TEXT, link_faa TEXT, link_fa TEXT,
    created_at INTEGER DEFAULT (strftime('%s','now')),
    updated_at INTEGER DEFAULT (strftime('%s','now')),
    UNIQUE(date, icao, firstseen)
);
CREATE INDEX IF NOT EXISTS idx_pf_active ON planefence(date, icao, complete, lastseen);
CREATE INDEX IF NOT EXISTS idx_pf_time ON planefence(date, firstseen, lastseen);
CREATE INDEX IF NOT EXISTS idx_pf_enrich ON planefence(date, complete, enriched_at);

CREATE TABLE IF NOT EXISTS plane_alert (
    id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, icao TEXT NOT NULL,
    callsign TEXT, tail TEXT, type TEXT, owner TEXT, lat REAL, lon REAL,
    lat_first REAL, lon_first REAL, lat_min REAL, lon_min REAL,
    dist REAL, dist_unit TEXT DEFAULT 'nm', alt REAL, alt_unit TEXT DEFAULT 'ft',
    firstseen INTEGER, lastseen INTEGER, time_at_min_dist INTEGER,
    squawk TEXT, squawk_desc TEXT, heading REAL, direction TEXT, speed REAL,
    enriched_tail INTEGER DEFAULT 0, enriched_type INTEGER DEFAULT 0,
    enriched_callsign INTEGER DEFAULT 0, enriched_owner INTEGER DEFAULT 0,
    enriched_image INTEGER DEFAULT 0, enriched_noise INTEGER DEFAULT 0,
    enriched_route INTEGER DEFAULT 0, enriched_nominatim INTEGER DEFAULT 0,
    enriched_at INTEGER, location TEXT, route TEXT,
    image_thumb TEXT, image_link TEXT, image_file TEXT,
    noise_peak REAL, noise_1h REAL, noise_loudness REAL, noise_color TEXT,
    complete INTEGER DEFAULT 1, ready_to_notify INTEGER DEFAULT 1, notified INTEGER DEFAULT 0,
    pa_registration TEXT, pa_operator TEXT, pa_type_desc TEXT, pa_icao_type TEXT,
    pa_cmpg TEXT, pa_tag1 TEXT, pa_tag2 TEXT, pa_tag3 TEXT, pa_category TEXT,
    pa_link TEXT, pa_image1 TEXT, pa_image2 TEXT, pa_image3 TEXT, pa_image4 TEXT,
    link_map TEXT, link_faa TEXT, link_fa TEXT,
    created_at INTEGER DEFAULT (strftime('%s','now')),
    updated_at INTEGER DEFAULT (strftime('%s','now')),
    UNIQUE(date, icao, firstseen)
);
CREATE INDEX IF NOT EXISTS idx_pa_active ON plane_alert(date, icao, lastseen);

CREATE TABLE IF NOT EXISTS heatmap (
    date TEXT NOT NULL, lat_rounded REAL, lon_rounded REAL, count INTEGER DEFAULT 1,
    PRIMARY KEY (date, lat_rounded, lon_rounded)
);

CREATE TABLE IF NOT EXISTS state (
    key TEXT PRIMARY KEY, value TEXT, updated_at INTEGER DEFAULT (strftime('%s','now'))
);

CREATE TABLE IF NOT EXISTS daily_stats (
    date TEXT PRIMARY KEY, pf_maxindex INTEGER DEFAULT 0, pa_maxindex INTEGER DEFAULT 0,
    total_lines INTEGER DEFAULT 0, has_route INTEGER DEFAULT 0,
    has_images INTEGER DEFAULT 0, has_noise INTEGER DEFAULT 0, lastupdate INTEGER
);
"""

@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except:
        conn.rollback()
        raise
    finally:
        conn.close()

def init_db():
    with get_db() as conn:
        conn.executescript(SCHEMA_SQL)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA temp_store=MEMORY")
        conn.execute("PRAGMA cache_size=-64000")

def get_state(key, default=None):
    with get_db() as conn:
        row = conn.execute("SELECT value FROM state WHERE key=?", (key,)).fetchone()
        return row["value"] if row else default

def set_state(key, value):
    with get_db() as conn:
        conn.execute("""
            INSERT INTO state(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=strftime('%s','now')
        """, (key, str(value)))

def load_active_planes(date):
    with get_db() as conn:
        rows = conn.execute("SELECT * FROM planefence WHERE date = ? AND complete = 0", (date,)).fetchall()
    return {row["icao"]: dict(row) for row in rows}

def load_active_pa(date):
    with get_db() as conn:
        rows = conn.execute("SELECT * FROM plane_alert WHERE date = ? AND lastseen >= ?", (date, MIDNIGHT_EPOCH)).fetchall()
    return {row["icao"]: dict(row) for row in rows}

def upsert_pf_plane(date, icao, data, is_new=False):
    with get_db() as conn:
        if is_new:
            cur = conn.execute("""
                INSERT INTO planefence(date, icao, firstseen, lastseen, dist, lat, lon,
                    lat_min, lon_min, alt, heading, speed, direction,
                    squawk, squawk_desc, callsign, dist_unit, alt_unit, complete, ready_to_notify)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
            """, (
                date, icao, data["seen_time"], data["seen_time"],
                data["dist"], data.get("lat"), data.get("lon"),
                data.get("lat"), data.get("lon"), data.get("alt"),
                data.get("track"), data.get("gs"), data.get("angle"),
                data.get("squawk"), data.get("squawk_desc"), data.get("callsign"),
                DISTUNIT, ALTUNIT
            ))
            return cur.lastrowid
        else:
            conn.execute("""
                UPDATE planefence SET lastseen = ?,
                    dist = CASE WHEN ? < dist THEN ? ELSE dist END,
                    lat_min = CASE WHEN ? < dist THEN ? ELSE lat_min END,
                    lon_min = CASE WHEN ? < dist THEN ? ELSE lon_min END,
                    time_at_min_dist = CASE WHEN ? < dist THEN ? ELSE time_at_min_dist END,
                    lat = COALESCE(?, lat), lon = COALESCE(?, lon),
                    alt = COALESCE(?, alt), heading = COALESCE(?, heading),
                    speed = COALESCE(?, speed), direction = COALESCE(?, direction),
                    squawk = COALESCE(?, squawk), squawk_desc = COALESCE(?, squawk_desc),
                    callsign = COALESCE(?, callsign), updated_at = strftime('%s','now')
                WHERE date = ? AND icao = ? AND complete = 0
            """, (
                data["seen_time"], data["dist"], data["dist"],
                data["dist"], data.get("lat"), data["dist"], data.get("lon"),
                data["dist"], data["seen_time"],
                data.get("lat"), data.get("lon"), data.get("alt"),
                data.get("track"), data.get("gs"), data.get("angle"),
                data.get("squawk"), data.get("squawk_desc"), data.get("callsign"),
                date, icao
            ))
            return None

def upsert_pa_plane(date, icao, data, is_new=False, pa_row=None, pa_col_map=None):
    with get_db() as conn:
        if is_new:
            cur = conn.execute("""
                INSERT INTO plane_alert(date, icao, firstseen, lastseen, dist, lat, lon,
                    lat_first, lon_first, lat_min, lon_min, alt, heading, speed, direction,
                    squawk, squawk_desc, callsign, dist_unit, alt_unit, complete, ready_to_notify)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)
            """, (
                date, icao, data["seen_time"], data["seen_time"],
                data["dist"], data.get("lat"), data.get("lon"),
                data.get("lat"), data.get("lon"), data.get("lat"), data.get("lon"),
                data.get("alt"), data.get("track"), data.get("gs"), data.get("angle"),
                data.get("squawk"), data.get("squawk_desc"), data.get("callsign"),
                DISTUNIT, ALTUNIT
            ))
            rowid = cur.lastrowid
        else:
            conn.execute("""
                UPDATE plane_alert SET lastseen = ?,
                    dist = CASE WHEN ? < dist THEN ? ELSE dist END,
                    lat_min = CASE WHEN ? < dist THEN ? ELSE lat_min END,
                    lon_min = CASE WHEN ? < dist THEN ? ELSE lon_min END,
                    time_at_min_dist = CASE WHEN ? < dist THEN ? ELSE time_at_min_dist END,
                    lat = COALESCE(?, lat), lon = COALESCE(?, lon),
                    alt = COALESCE(?, alt), heading = COALESCE(?, heading),
                    speed = COALESCE(?, speed), direction = COALESCE(?, direction),
                    squawk = COALESCE(?, squawk), squawk_desc = COALESCE(?, squawk_desc),
                    callsign = COALESCE(?, callsign), updated_at = strftime('%s','now')
                WHERE date = ? AND icao = ?
            """, (
                data["seen_time"], data["dist"], data["dist"],
                data["dist"], data.get("lat"), data["dist"], data.get("lon"),
                data["dist"], data["seen_time"],
                data.get("lat"), data.get("lon"), data.get("alt"),
                data.get("track"), data.get("gs"), data.get("angle"),
                data.get("squawk"), data.get("squawk_desc"), data.get("callsign"),
                date, icao
            ))
            rowid = None

        if pa_row and pa_col_map:
            tag_mapping = {
                "$ICAO": None, "$Registration": "pa_registration",
                "$Operator": "pa_operator", "$Type": "pa_type_desc",
                "$ICAO Type": "pa_icao_type", "#CMPG": "pa_cmpg",
                "$Tag 1": "pa_tag1", "$#Tag 2": "pa_tag2",
                "$#Tag 3": "pa_tag3", "Category": "pa_category",
                "$#Link": "pa_link", "#ImageLink": "pa_image1",
                "#ImageLink2": "pa_image2", "#ImageLink3": "pa_image3",
                "#ImageLink4": "pa_image4",
            }
            updates = {}
            for col, idx in pa_col_map.items():
                if idx < len(pa_row) and pa_row[idx].strip():
                    val = pa_row[idx].strip().strip('"')
                    db_col = tag_mapping.get(col)
                    if db_col:
                        updates[db_col] = val
            if updates:
                where_id = rowid if rowid else conn.execute(
                    "SELECT id FROM plane_alert WHERE date=? AND icao=? ORDER BY firstseen DESC LIMIT 1",
                    (date, icao)
                ).fetchone()["id"]
                set_clause = ", ".join(f"{k}=?" for k in updates.keys())
                conn.execute(f"UPDATE plane_alert SET {set_clause} WHERE id=?", list(updates.values()) + [where_id])
        return rowid

def mark_pf_timeouts(date, now, collapse_within):
    with get_db() as conn:
        rows = conn.execute("""
            SELECT id, firstseen FROM planefence WHERE date = ? AND complete = 0 AND (? - lastseen) > ?
        """, (date, now, collapse_within)).fetchall()
        for row in rows:
            anchor = row["firstseen"] if TWEET_BEHAVIOR == "post" else row["firstseen"]
            ready = 0 if (TWEET_MINTIME and now < anchor + TWEET_MINTIME) else 1
            conn.execute("UPDATE planefence SET complete = 1, ready_to_notify = ? WHERE id = ?", (ready, row["id"]))

def update_heatmap(date, lat, lon):
    if lat is None or lon is None:
        return
    lat_r, lon_r = round(lat, 3), round(lon, 3)
    with get_db() as conn:
        conn.execute("""
            INSERT INTO heatmap(date, lat_rounded, lon_rounded, count) VALUES(?, ?, ?, 1)
            ON CONFLICT(date, lat_rounded, lon_rounded) DO UPDATE SET count = count + 1
        """, (date, lat_r, lon_r))

def update_stats(date, total_lines=None, lastupdate=None):
    with get_db() as conn:
        conn.execute("""
            INSERT INTO daily_stats(date, total_lines, lastupdate) VALUES(?, COALESCE(?, 0), ?)
            ON CONFLICT(date) DO UPDATE SET
                total_lines = daily_stats.total_lines + COALESCE(?, 0),
                lastupdate = COALESCE(?, daily_stats.lastupdate)
        """, (date, total_lines or 0, lastupdate, total_lines or 0, lastupdate))

def get_planes_needing_enrichment(date, now, table="planefence"):
    with get_db() as conn:
        if table == "planefence":
            return conn.execute("""
                SELECT * FROM planefence WHERE date = ? AND (
                    (complete = 1 AND (enriched_route = 0 OR enriched_noise = 0 OR enriched_nominatim = 0))
                    OR (complete = 0 AND (enriched_at IS NULL OR enriched_at < ?))
                ) ORDER BY complete DESC, enriched_at ASC
            """, (date, now - 300)).fetchall()
        else:
            return conn.execute("""
                SELECT * FROM plane_alert WHERE date = ? AND (
                    enriched_route = 0 OR enriched_noise = 0 OR enriched_nominatim = 0
                    OR (enriched_at IS NULL OR enriched_at < ?)
                ) ORDER BY enriched_at ASC
            """, (date, now - 300)).fetchall()

def update_enrichment_flags(table, row_id, flags):
    cols = ", ".join(f"{k}=?" for k in flags.keys())
    vals = list(flags.values()) + [row_id]
    with get_db() as conn:
        conn.execute(f"UPDATE {table} SET {cols}, enriched_at=strftime('%s','now') WHERE id=?", vals)

def update_plane_field(table, row_id, field, value):
    with get_db() as conn:
        conn.execute(f"UPDATE {table} SET {field}=?, updated_at=strftime('%s','now') WHERE id=?", (value, row_id))

def get_daily_planes(date, table="planefence"):
    with get_db() as conn:
        return conn.execute(f"SELECT * FROM {table} WHERE date = ? ORDER BY firstseen DESC", (date,)).fetchall()

def get_heatmap_data(date):
    with get_db() as conn:
        return conn.execute("SELECT lat_rounded, lon_rounded, count FROM heatmap WHERE date = ?", (date,)).fetchall()

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------
def deg_to_compass(deg):
    dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    return dirs[int((float(deg) + 11.25) / 22.5) % 16]

def get_squawk_description(squawk):
    try:
        res = subprocess.run(["/usr/share/planefence/get_squawk_description.sh", squawk],
                             capture_output=True, text=True, timeout=5)
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except:
        pass
    return ""

def get_tail(icao):
    icao = icao.upper()
    cache_file = os.path.join(CACHE_DIR, "icao2tail.cache")
    if os.path.exists(cache_file):
        with open(cache_file) as f:
            for line in f:
                if line.startswith(icao + ","):
                    return line.strip().split(",", 1)[1].strip()
    mictronics = "/run/planefence/icao2plane.txt"
    if os.path.exists(mictronics):
        try:
            res = subprocess.run(["grep", "-m1", "-i", "-F", icao, mictronics],
                                 capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                parts = res.stdout.strip().split(",")
                if len(parts) >= 2 and parts[1].strip():
                    tail = parts[1].strip()
                    with open(cache_file, "a") as f: f.write(f"{icao},{tail}\n")
                    return tail
        except: pass
    opensky = "/run/OpenSkyDB.csv"
    if os.path.exists(opensky):
        try:
            res = subprocess.run(["grep", "-m1", "-i", "-F", icao, opensky],
                                 capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                parts = res.stdout.strip().split(",")
                if len(parts) >= 27:
                    tail = parts[26].strip().strip('"\' ')
                    if tail:
                        with open(cache_file, "a") as f: f.write(f"{icao},{tail}\n")
                        return tail
        except: pass
    if icao.startswith("A") and not icao.startswith(("AE", "ADE", "ADF")):
        try:
            res = subprocess.run(["/usr/share/planefence/icao2tail.py", icao],
                                 capture_output=True, text=True, timeout=5)
            if res.returncode == 0 and res.stdout.strip():
                tail = res.stdout.strip()
                with open(cache_file, "a") as f: f.write(f"{icao},{tail}\n")
                return tail
        except: pass
    return ""

def get_callsign(icao, todayfile):
    icao = icao.upper()
    if todayfile and os.path.exists(todayfile):
        try:
            cmd = f"tac {todayfile} | awk -F ',' -v icao='{icao}' '($1 == icao && $12 != \"\") {{print $12;exit;}}'"
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except: pass
    return get_tail(icao)

def get_type(icao):
    icao = icao.upper()
    mictronics = "/run/planefence/icao2plane.txt"
    if os.path.exists(mictronics):
        try:
            res = subprocess.run(["grep", "-m1", "-i", "-F", icao, mictronics],
                                 capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                parts = res.stdout.strip().split(",")
                if len(parts) >= 3 and parts[2].strip():
                    return parts[2].strip()
        except: pass
    opensky = "/run/OpenSkyDB.csv"
    if os.path.exists(opensky):
        try:
            if OPENSKY_COLS["icao24"] == -1:
                with open(opensky) as f:
                    reader = csv.reader(f)
                    header = next(reader)
                    try: OPENSKY_COLS["icao24"] = header.index("icao24")
                    except ValueError: OPENSKY_COLS["icao24"] = 0
                    try: OPENSKY_COLS["typecode"] = header.index("typecode")
                    except ValueError: OPENSKY_COLS["typecode"] = 0
            if OPENSKY_COLS["icao24"] != -1 and OPENSKY_COLS["typecode"] != -1:
                res = subprocess.run(["grep", "-m1", "-i", "-F", icao, opensky],
                                     capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    row = next(csv.reader([res.stdout.strip()]))
                    if row[OPENSKY_COLS["icao24"]].strip().upper() == icao:
                        return row[OPENSKY_COLS["typecode"]].strip()
        except: pass
    try:
        status, body = http_get(f"https://api.adsb.lol/v2/hex/{icao}", timeout=10)
        if status == 200:
            data = json.loads(body.decode("utf-8"))
            ac = data.get("ac", [])
            if ac and ac[0].get("t"):
                return ac[0]["t"]
    except: pass
    return ""

def get_ps_photo(icao, returntype="link"):
    if not SHOWIMAGES: return ""
    icao = icao.upper()
    os.makedirs(PLANEPIX_CACHE, exist_ok=True)
    jpg = os.path.join(PLANEPIX_CACHE, f"{icao}.jpg")
    lnk = os.path.join(PLANEPIX_CACHE, f"{icao}.link")
    tlnk = os.path.join(PLANEPIX_CACHE, f"{icao}.thumb.link")
    na = os.path.join(PLANEPIX_CACHE, f"{icao}.notavailable")
    if os.path.exists(na): return ""
    CACHETIME = 3 * 24 * 3600
    now = time.time()
    if returntype == "image" and os.path.exists(jpg) and (now - os.path.getmtime(jpg)) < CACHETIME:
        return jpg
    elif returntype == "link" and os.path.exists(lnk) and (now - os.path.getmtime(lnk)) < CACHETIME:
        with open(lnk) as f: return f.read().strip()
    elif returntype == "thumblink" and os.path.exists(tlnk) and (now - os.path.getmtime(tlnk)) < CACHETIME:
        with open(tlnk) as f: return f.read().strip()
    try:
        status, body = http_get(
            f"https://api.planespotters.net/pub/photos/hex/{icao}",
            timeout=10, headers={"User-Agent": f"Planefence/{VERSION}"}
        )
        if status == 200:
            data = json.loads(body.decode("utf-8"))
            photo = data.get("photos", [{}])[0]
            link = photo.get("link")
            thumb = photo.get("thumbnail_large", {}).get("src")
            if link and thumb:
                status2, body2 = http_get(thumb, timeout=10)
                if status2 == 200:
                    with open(jpg, "wb") as f: f.write(body2)
                with open(lnk, "w") as f: f.write(link)
                with open(tlnk, "w") as f: f.write(thumb)
                if returntype == "image": return jpg
                elif returntype == "link": return link
                else: return thumb
    except: pass
    open(na, "w").close()
    return ""

def get_noisedata(firstseen, lastseen, noise_cache):
    if not REMOTENOISE or not firstseen or not lastseen: return None
    firstseen = int(firstseen)
    lastseen = max(firstseen + 15, int(lastseen))
    dates = {datetime.fromtimestamp(ts).strftime("%y%m%d") for ts in [firstseen, lastseen]}
    samples = sum_lvl = sum_1m = sum_5m = sum_10m = sum_1h = 0
    for d in dates:
        if d not in noise_cache:
            try:
                status, body = http_get(f"{REMOTENOISE}/noisecapt-{d}.log", timeout=5)
                noise_cache[d] = body.decode("utf-8", errors="ignore").splitlines() if status == 200 else []
            except:
                noise_cache[d] = []
        for line in noise_cache[d]:
            parts = line.split(",")
            if len(parts) >= 6 and firstseen <= float(parts[0]) <= lastseen:
                samples += 1
                sum_lvl += float(parts[1])
                sum_1m += float(parts[2])
                sum_5m += float(parts[3])
                sum_10m += float(parts[4])
                sum_1h += float(parts[5])
    if samples == 0: return None
    avg_1h = sum_1h / samples
    loudness = (sum_lvl / samples) - avg_1h
    color = "red" if loudness > YELLOWLIMIT else ("yellow" if loudness > GREENLIMIT else "green")
    return {
        "noise_peak": str(sum_lvl / samples), "noise_1min": str(sum_1m / samples),
        "noise_5min": str(sum_5m / samples), "noise_10min": str(sum_10m / samples),
        "noise_1h": str(avg_1h), "noise_loudness": str(loudness), "noise_color": color
    }

def create_noiseplot(callsign, starttime, endtime, icao, noise_cache):
    if not REMOTENOISE: return ""
    starttime = int(starttime) - 15
    endtime = max(starttime + 15, int(endtime))
    day = datetime.fromtimestamp(starttime).strftime("%y%m%d")
    if day not in noise_cache:
        try:
            status, body = http_get(f"{REMOTENOISE}/noisecapt-{day}.log", timeout=5)
            noise_cache[day] = body.decode("utf-8", errors="ignore").splitlines() if status == 200 else []
        except:
            noise_cache[day] = []
    tmp_log = f"/tmp/noisecapt-{day}.log"
    with open(tmp_log, "w") as f:
        f.write("\n".join(noise_cache[day]))
    if not any(starttime <= float(p.split(",")[0]) <= endtime for p in noise_cache[day] if p): return ""
    graph_file = os.path.join(NOISEDIR, f"noisegraph-{starttime}-{icao}.png")
    offset = int(datetime.now().astimezone().utcoffset().total_seconds() / 3600 * 36)
    try:
        subprocess.run(["gnuplot", "-e",
                        f"offset={offset}; start={starttime}; end={endtime}; "
                        f"infile='{tmp_log}'; outfile='{graph_file}'; "
                        f"plottitle='Noise plot for {callsign} at {datetime.fromtimestamp(starttime)}'; margin=60",
                        "/usr/share/planefence/noiseplot.gnuplot"],
                       check=True, timeout=30)
        return graph_file if os.path.exists(graph_file) else ""
    except: return ""

def create_spectrogram(firstseen, lastseen, time_at_mindist, noise_cache):
    if not REMOTENOISE: return ""
    target = time_at_mindist if time_at_mindist else (int(firstseen) + int(lastseen)) // 2
    if not hasattr(create_spectrogram, "noiselist"):
        try:
            status, body = http_get(f"{REMOTENOISE}/noisecapt-dir.gz", timeout=10)
            if status == 200:
                content = gzip.decompress(body).decode(errors="ignore")
                create_spectrogram.noiselist = content.splitlines()
            else:
                create_spectrogram.noiselist = []
        except:
            create_spectrogram.noiselist = []
    best_before = best_after = None
    best_before_dt = best_after_dt = float("inf")
    for fname in create_spectrogram.noiselist:
        if fname.startswith("noisecapt-spectro-") and fname.endswith(".png"):
            try:
                ts = int(fname.split("-")[2].split(".")[0])
                dt = abs(target - ts)
                if ts <= target:
                    if dt < best_before_dt:
                        best_before_dt = dt
                        best_before = fname
                else:
                    if dt < best_after_dt:
                        best_after_dt = dt
                        best_after = fname
            except: pass
    chosen = None
    if best_before and best_before_dt <= MAXSPREAD: chosen = best_before
    elif best_after and best_after_dt <= MAXSPREAD: chosen = best_after
    if chosen:
        local_path = os.path.join(NOISEDIR, chosen)
        if not os.path.exists(local_path):
            try:
                status, body = http_get(f"{REMOTENOISE}/{chosen}", timeout=10)
                if status == 200:
                    with open(local_path, "wb") as f: f.write(body)
                else:
                    return ""
            except: return ""
        return local_path
    return ""

def create_mp3(firstseen, lastseen, noise_cache):
    if not REMOTENOISE: return ""
    firstseen = int(firstseen)
    lastseen = max(firstseen + 30, int(lastseen))
    peak_time = peak_lvl = 0
    for lines in noise_cache.values():
        for line in lines:
            parts = line.split(",")
            if len(parts) >= 6 and firstseen <= float(parts[0]) <= lastseen:
                if float(parts[1]) > peak_lvl:
                    peak_lvl = float(parts[1])
                    peak_time = float(parts[0])
    if peak_time == 0: return ""
    mp3_file = f"noisecapt-recording-{int(peak_time)}.mp3"
    local_path = os.path.join(NOISEDIR, mp3_file)
    if not os.path.exists(local_path):
        try:
            status, body = http_get(f"{REMOTENOISE}/{mp3_file}", timeout=10)
            if status == 200:
                with open(local_path, "wb") as f: f.write(body)
            else:
                return ""
        except: return ""
    return local_path

def link_latest_spectrofile():
    files = glob.glob(os.path.join(NOISEDIR, "noisecapt-spectro-*.png"))
    if files:
        link = os.path.join(OUTFILEDIR, "noisecapt-spectro-latest.png")
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink(max(files, key=os.path.getmtime), link)

# ---------------------------------------------------------------------------
# Legacy file output
# ---------------------------------------------------------------------------
def shell_quote_value(value):
    if any(c in value for c in '() $&;<>|`'):
        return "'" + value.replace("'", "'\\''") + "'"
    return value

def write_records_file(filepath, stats):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".tmp") as tmpf:
        def w(k, v):
            quoted = shell_quote_value(str(v))
            tmpf.write(f"{k}={quoted}\n".encode())
        w("LASTUPDATE", str(NOWTIME))
        w("lastprocessedline", stats.get("lastprocessedline", ""))
        w("totallines", str(stats.get("total_lines", 0)))
        w("maxindex", str(stats.get("pf_maxindex", 0)))
        w("pa_maxindex", str(stats.get("pa_maxindex", 0)))
        w("HASROUTE", stats.get("has_route", "false"))
        w("HASIMAGES", stats.get("has_images", "false"))
        w("HASNOISE", stats.get("has_noise", "false"))
        tmpf.flush()
        with gzip.open(filepath, "wb") as gz:
            gz.write(open(tmpf.name, "rb").read())
        os.unlink(tmpf.name)

# ---------------------------------------------------------------------------
# JSON/CSV generation
# ---------------------------------------------------------------------------
def row_to_dict(row):
    d = dict(row)
    result = {}
    for k, v in d.items():
        if v is None:
            continue
        ui_key = None
        if k in UI_KEY_MAP:
            ui_key = UI_KEY_MAP[k]
        elif k.startswith("pa_"):
            continue
        else:
            ui_key = k
        if ui_key:
            result[ui_key] = str(v) if not isinstance(v, str) else v
    if "notified" not in result:
        result["notified"] = "false"
    return result

def generate_json(rows, prefix, globals_dict, lastupdate_key):
    records_list = []
    for row in rows:
        rec = row_to_dict(row)
        rec["index"] = row["id"]
        records_list.append(rec)
    records_list.sort(key=lambda x: x["index"], reverse=True)
    first_dict = dict(globals_dict)
    first_dict[lastupdate_key] = str(NOWTIME)
    records_list.insert(0, first_dict)
    out_file = os.path.join(RUN_PF_DIR, f"{prefix}-{TODAY_STR}.json")
    with open(out_file, "w") as f:
        json.dump(records_list, f, separators=(',', ':'))
    link = os.path.join(OUTFILEDIR, f"{prefix}.json")
    if os.path.lexists(link): os.unlink(link)
    os.symlink(out_file, link)

def generate_csv(rows, prefix):
    if not rows:
        return
    records_list = [dict(row) for row in rows]
    all_keys = set()
    for rec in records_list:
        all_keys.update(rec.keys())
    out_file = os.path.join(RUN_PF_DIR, f"{prefix}-{TODAY_STR}.csv")
    with open(out_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=sorted(all_keys))
        writer.writeheader()
        writer.writerows(records_list)

def generate_heatmap_js(date):
    rows = get_heatmap_data(date)
    with open(os.path.join(JS_DIR, "planeheatdata.js"), "w") as f:
        f.write("var addressPoints = [\n")
        for row in rows:
            f.write(f"[ {row['lat_rounded']}, {row['lon_rounded']}, {row['count']} ],\n")
        f.write("];\n")

# ---------------------------------------------------------------------------
# Input parsing
# ---------------------------------------------------------------------------
def safe_float(val, default=None):
    if val is None:
        return default
    val = str(val).strip().lower()
    if not val or val == "ground":
        return 0.0
    try:
        return float(val)
    except ValueError:
        return default

def parse_sbs_line(line):
    parts = line.strip().split(",")
    if not parts or "hex_ident" in line or len(parts) < 12:
        return None
    try:
        date_str = parts[4].strip().replace("-", "/")
        time_str = parts[5].strip().split(".")[0]
        return {
            "icao": parts[0].strip().upper(),
            "alt": safe_float(parts[1], 0.0),
            "lat": safe_float(parts[2], None),
            "lon": safe_float(parts[3], None),
            "angle": safe_float(parts[6], None),
            "dist": safe_float(parts[7], 0.0),
            "squawk": parts[8].strip() if parts[8].strip() else None,
            "gs": safe_float(parts[9], None),
            "track": safe_float(parts[10], None),
            "callsign": parts[11].strip() if parts[11].strip() else None,
            "seen_time": int(datetime.strptime(f"{date_str} {time_str}", "%Y/%m/%d %H:%M:%S").timestamp())
        }
    except Exception as e:
        return None

# ---------------------------------------------------------------------------
# FIXED: Timestamp-based incremental line collection
# ---------------------------------------------------------------------------
def collect_new_lines():
    """Fetch only lines newer than last processed timestamp."""
    last_ts_str = get_state("last_processed_timestamp", "0")
    last_ts = int(last_ts_str) if last_ts_str else 0

    today_files = sorted(glob.glob(f"{SOCKET_DIR}/dump1090-*-{TODAY_STR}.txt"))
    yesterday_files = sorted(glob.glob(f"{SOCKET_DIR}/dump1090-*-{YESTERDAY_STR}.txt"))
    todayfile = today_files[-1] if today_files else None
    yesterdayfile = yesterday_files[-1] if yesterday_files else None

    new_lines = []
    max_ts = last_ts

    if yesterdayfile and os.path.exists(yesterdayfile):
        with open(yesterdayfile) as f:
            for line in f:
                data = parse_sbs_line(line)
                if data and data["seen_time"] > last_ts:
                    new_lines.append(data)
                    if data["seen_time"] > max_ts:
                        max_ts = data["seen_time"]

    if todayfile and os.path.exists(todayfile):
        with open(todayfile) as f:
            for line in f:
                data = parse_sbs_line(line)
                if data and data["seen_time"] > last_ts:
                    new_lines.append(data)
                    if data["seen_time"] > max_ts:
                        max_ts = data["seen_time"]

    new_lines.sort(key=lambda x: x["seen_time"])
    return new_lines, max_ts, todayfile

# ---------------------------------------------------------------------------
# Enrichment
# ---------------------------------------------------------------------------
def process_basic_enrichment(row, table, todayfile):
    row = dict(row)  # Convert sqlite3.Row to dict
    icao = row["icao"]
    flags = {}
    updates = {}

    if not row.get("enriched_tail"):
        tail = get_tail(icao)
        if tail:
            updates["tail"] = tail
            if icao[0] == 'A':
                updates["link_faa"] = f"https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt={tail}"
            elif icao[0] == 'C':
                updates["link_faa"] = f"https://wwwapps.tc.gc.ca/saf-sec-sur/2/ccarcs-riacc/RchSimpRes.aspx?m=%7c{tail[1:].replace('-', '')}%7c"
            if not updates.get("link_map"):
                updates["link_map"] = f"{TRACKURL}/{tail}" if TRACKSERVICE == "flightaware" else f"{TRACKURL}/?icao={icao}&lat={row.get('lat', '')}&lon={row.get('lon', '')}&showTrace={TRACEDATE}"
        flags["enriched_tail"] = 1

    if not row.get("enriched_type"):
        typ = get_type(icao)
        if typ:
            updates["type"] = typ
        flags["enriched_type"] = 1

    if not row.get("enriched_callsign"):
        cs = get_callsign(icao, todayfile)
        if cs:
            updates["callsign"] = cs
            updates["link_fa"] = f"https://flightaware.com/live/modes/{icao}/ident/{cs}/redirect"
        flags["enriched_callsign"] = 1

    if not row.get("enriched_owner") and (updates.get("callsign") or row.get("callsign")):
        cs = updates.get("callsign") or row.get("callsign")
        try:
            res = subprocess.run(["/usr/share/planefence/airlinename.sh", cs, icao],
                                 capture_output=True, text=True, timeout=5)
            if res.returncode == 0 and res.stdout.strip():
                updates["owner"] = res.stdout.strip()
        except: pass
        flags["enriched_owner"] = 1

    if SHOWIMAGES and not row.get("enriched_image"):
        thumb = get_ps_photo(icao, "thumblink")
        link = get_ps_photo(icao, "link")
        imgfile = get_ps_photo(icao, "image")
        if thumb: updates["image_thumb"] = thumb
        if link: updates["image_link"] = link
        if imgfile: updates["image_file"] = imgfile
        flags["enriched_image"] = 1

    if updates:
        set_clause = ", ".join(f"{k}=?" for k in updates.keys())
        vals = list(updates.values()) + [row["id"]]
        with get_db() as conn:
            conn.execute(f"UPDATE {table} SET {set_clause}, updated_at=strftime('%s','now') WHERE id=?", vals)

    if flags:
        update_enrichment_flags(table, row["id"], flags)

def process_deep_enrichment(row, table, noise_cache, bulk_routes):
    row = dict(row)  # Convert sqlite3.Row to dict
    icao = row["icao"]
    flags = {}
    updates = {}

    if REMOTENOISE and not row.get("enriched_noise") and row.get("firstseen") and row.get("lastseen"):
        nd = get_noisedata(row["firstseen"], row["lastseen"], noise_cache)
        if nd:
            updates.update(nd)
        if row.get("noise_peak") or (nd and nd.get("noise_peak")):
            if not row.get("noisegraph_file"):
                graph = create_noiseplot(row.get("callsign", icao), row["firstseen"], row["lastseen"], icao, noise_cache)
                if graph:
                    updates["noisegraph_file"] = graph
            if not row.get("spectro_file"):
                spec = create_spectrogram(row["firstseen"], row["lastseen"], row.get("time_at_min_dist"), noise_cache)
                if spec:
                    updates["spectro_file"] = spec
            if not row.get("mp3_file"):
                mp3 = create_mp3(row["firstseen"], row["lastseen"], noise_cache)
                if mp3:
                    updates["mp3_file"] = mp3
        flags["enriched_noise"] = 1

    if not row.get("enriched_nominatim") and row.get("lat") and row.get("lon"):
        try:
            res = subprocess.run(["/usr/share/planefence/nominatim.sh", f"--lat={row['lat']}", f"--lon={row['lon']}"],
                                 capture_output=True, text=True, timeout=5)
            if res.returncode == 0 and res.stdout.strip():
                updates["location"] = res.stdout.strip()
        except: pass
        flags["enriched_nominatim"] = 1

    if CHECKROUTE and row.get("callsign") and not row.get("enriched_route"):
        bulk_routes.append({
            "callsign": row["callsign"],
            "lat": float(row.get("lat") or 0),
            "lng": float(row.get("lon") or 0),
            "table": table,
            "row_id": row["id"]
        })

    if updates:
        set_clause = ", ".join(f"{k}=?" for k in updates.keys())
        vals = list(updates.values()) + [row["id"]]
        with get_db() as conn:
            conn.execute(f"UPDATE {table} SET {set_clause}, updated_at=strftime('%s','now') WHERE id=?", vals)

    if flags:
        update_enrichment_flags(table, row["id"], flags)

def process_bulk_routes(bulk_routes):
    if not bulk_routes:
        return
    payload = {"planes": [{"callsign": e["callsign"], "lat": e["lat"], "lng": e["lng"]} for e in bulk_routes]}
    try:
        status, body = http_post_json("https://adsb.im/api/0/routeset", payload, timeout=10)
        if status == 200:
            results = json.loads(body.decode("utf-8"))
            route_map = {}
            for item in results:
                if isinstance(item, dict):
                    route_map[item.get("callsign", "")] = {
                        "route": item.get("_airport_codes_iata", "n/a"),
                        "plausible": item.get("plausible", True)
                    }
                elif isinstance(item, list) and len(item) >= 3:
                    route_map[item[0]] = {"route": item[1], "plausible": item[2]}
            for entry in bulk_routes:
                cs = entry["callsign"]
                if cs in route_map:
                    info = route_map[cs]
                    r_str = str(info["route"])
                    if r_str.lower() in ("unknown", "null", ""): r_str = "n/a"
                    elif not info["plausible"]: r_str += " (?)"
                    update_plane_field(entry["table"], entry["row_id"], "route", r_str)
                    update_enrichment_flags(entry["table"], entry["row_id"], {"enriched_route": 1})
    except Exception as e:
        log_print("ERROR", f"Bulk Route processing failed: {e}")

# ---------------------------------------------------------------------------
# Main processing
# ---------------------------------------------------------------------------
def process_data():
    with open("/run/planefence.pid", "w") as f:
        f.write(str(os.getpid()))

    init_db()

    records_file = os.path.join(RECORDS_DIR, f"planefence-records-{TODAY_STR}.gz")

    pa_db = {}
    pa_col_map = {}
    if PLANEALERT and os.path.exists(PA_FILE):
        try:
            with open(PA_FILE, "r", encoding="utf-8", errors="ignore") as f:
                reader = csv.reader(f)
                headers = next(reader)
                pa_col_map = {h.strip().strip('"').strip(): i for i, h in enumerate(headers)}
                for row in reader:
                    if row: pa_db[row[0].strip().strip('"').upper()] = row
        except Exception as e:
            log_print("ERROR", f"Failed to load PA_FILE: {e}")

    # FIXED: Timestamp-based incremental line reading
    new_lines, max_ts, todayfile = collect_new_lines()

    if not new_lines:
        log_print("INFO", "No new lines to process.")
    else:
        log_print("INFO", f"Processing {len(new_lines)} new lines.")

        active_pf = load_active_planes(TODAY_ISO)
        active_pa = load_active_pa(TODAY_ISO)

        squawk_tracker = defaultdict(dict)
        for data in new_lines:
            if data["squawk"]:
                sq, ts = data["squawk"], data["seen_time"]
                tracker = squawk_tracker[data["icao"]]
                if sq not in tracker:
                    tracker[sq] = [ts, ts]
                else:
                    tracker[sq][0] = min(ts, tracker[sq][0])
                    tracker[sq][1] = max(ts, tracker[sq][1])

        pa_squawkmatch = {}
        for icao, sq_dict in squawk_tracker.items():
            for sq, (start, end) in sq_dict.items():
                if SQUAWKS_REGEX and SQUAWKS_REGEX.search(sq) and (end - start) >= SQUAWKTIME:
                    pa_squawkmatch[icao] = True
                    break

        touched_pf = set()
        touched_pa = set()

        for data in new_lines:
            icao, ts = data["icao"], data["seen_time"]

            if PLANEFENCE and icao not in ignore_set and data["dist"] <= DIST and data["alt"] <= MAXALT:
                if icao in active_pf and (ts - active_pf[icao]["lastseen"] <= COLLAPSEWITHIN):
                    if IGNOREDUPES:
                        continue
                    row_id = active_pf[icao]["id"]
                    upsert_pf_plane(TODAY_ISO, icao, data, is_new=False)
                    touched_pf.add(row_id)
                    active_pf[icao]["lastseen"] = ts
                    active_pf[icao]["dist"] = min(active_pf[icao]["dist"], data["dist"])
                else:
                    row_id = upsert_pf_plane(TODAY_ISO, icao, data, is_new=True)
                    active_pf[icao] = {"id": row_id, "icao": icao, "lastseen": ts,
                                       "firstseen": ts, "dist": data["dist"]}
                    touched_pf.add(row_id)

                if data["lat"] is not None and data["lon"] is not None:
                    update_heatmap(TODAY_ISO, data["lat"], data["lon"])

            if PLANEALERT:
                in_pa = icao in pa_db
                squawk_match = pa_squawkmatch.get(icao, False)
                if (in_pa or squawk_match) and data["dist"] <= PA_RANGE:
                    if icao in active_pa:
                        upsert_pa_plane(TODAY_ISO, icao, data, is_new=False,
                                       pa_row=pa_db.get(icao), pa_col_map=pa_col_map)
                        touched_pa.add(active_pa[icao]["id"])
                        active_pa[icao]["lastseen"] = ts
                    else:
                        row_id = upsert_pa_plane(TODAY_ISO, icao, data, is_new=True,
                                                pa_row=pa_db.get(icao), pa_col_map=pa_col_map)
                        active_pa[icao] = {"id": row_id, "icao": icao, "lastseen": ts,
                                           "firstseen": ts, "dist": data["dist"]}
                        touched_pa.add(row_id)

        for row_id in touched_pf:
            with get_db() as conn:
                row = conn.execute("SELECT * FROM planefence WHERE id=?", (row_id,)).fetchone()
            if row:
                process_basic_enrichment(row, "planefence", todayfile)
        for row_id in touched_pa:
            with get_db() as conn:
                row = conn.execute("SELECT * FROM plane_alert WHERE id=?", (row_id,)).fetchone()
            if row:
                process_basic_enrichment(row, "plane_alert", todayfile)

        mark_pf_timeouts(TODAY_ISO, NOWTIME, COLLAPSEWITHIN)
        update_stats(TODAY_ISO, total_lines=len(new_lines))

        noise_cache = {}
        bulk_routes = []

        pf_enrich = get_planes_needing_enrichment(TODAY_ISO, NOWTIME, "planefence")
        for row in pf_enrich:
            process_deep_enrichment(row, "planefence", noise_cache, bulk_routes)

        pa_enrich = get_planes_needing_enrichment(TODAY_ISO, NOWTIME, "plane_alert")
        for row in pa_enrich:
            process_deep_enrichment(row, "plane_alert", noise_cache, bulk_routes)

        process_bulk_routes(bulk_routes)

        with get_db() as conn:
            has_route = conn.execute("""
                SELECT 1 FROM planefence WHERE date=? AND complete=1 AND route IS NOT NULL AND route != 'n/a' LIMIT 1
            """, (TODAY_ISO,)).fetchone()
            has_images = conn.execute("""
                SELECT 1 FROM planefence WHERE date=? AND complete=1 AND image_thumb IS NOT NULL LIMIT 1
            """, (TODAY_ISO,)).fetchone()
            has_noise = conn.execute("""
                SELECT 1 FROM planefence WHERE date=? AND complete=1 AND noise_peak IS NOT NULL LIMIT 1
            """, (TODAY_ISO,)).fetchone()

        with get_db() as conn:
            conn.execute("""
                INSERT INTO daily_stats(date, has_route, has_images, has_noise)
                VALUES(?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    has_route=excluded.has_route,
                    has_images=excluded.has_images,
                    has_noise=excluded.has_noise
            """, (TODAY_ISO, 1 if has_route else 0, 1 if has_images else 0, 1 if has_noise else 0))

    update_stats(TODAY_ISO, lastupdate=NOWTIME)
    if new_lines:
        set_state("last_processed_timestamp", str(max_ts))

    pf_rows = get_daily_planes(TODAY_ISO, "planefence")
    pa_rows = get_daily_planes(TODAY_ISO, "plane_alert")

    fudge = FUDGELOC if 0 <= FUDGELOC <= 4 else 3
    pf_globals = {
        "dist:value": str(DIST), "dist:unit": DISTUNIT,
        "altitude:value": str(MAXALT), "altitude:unit": ALTUNIT,
        "lat": str(round(LAT, fudge)), "lon": str(round(LON, fudge)),
        "version": VERSION, "heatmapzoom": HEATMAPZOOM,
        "me": MY, "myurl": MYURL, "motd": PF_MOTD, "histtime": HISTTIME
    }
    pa_globals = {
        "dist:value": str(DIST), "dist:unit": DISTUNIT,
        "altitude:value": str(MAXALT), "altitude:unit": ALTUNIT,
        "lat": str(round(LAT, fudge)), "lon": str(round(LON, fudge)),
        "version": VERSION, "me": MY, "myurl": MYURL,
        "motd": PA_MOTD, "range": str(PA_RANGE) if PA_RANGE != 999999 else "-1"
    }

    generate_heatmap_js(TODAY_ISO)
    generate_json(pf_rows, "planefence", pf_globals, "LASTUPDATE")
    generate_json(pa_rows, "plane-alert", pa_globals, "LASTUPDATE")

    if GENERATE_CSV:
        generate_csv(pf_rows, "planefence")
        generate_csv(pa_rows, "plane-alert")

    if REMOTENOISE:
        link_latest_spectrofile()

    # Write legacy records file
    with get_db() as conn:
        stats = conn.execute("SELECT * FROM daily_stats WHERE date=?", (TODAY_ISO,)).fetchone()
    if stats:
        stats_dict = dict(stats)
        stats_dict["lastprocessedline"] = ""
        write_records_file(records_file, stats_dict)

    for f in glob.glob(os.path.join(NOISEDIR, "noisegraph-*")) + glob.glob(os.path.join(NOISEDIR, "noisecapt-*")):
        try:
            if os.path.getmtime(f) < time.time() - 7*86400:
                os.remove(f)
        except: pass
    for f in glob.glob("/tmp/.pf-noisecache-*"):
        shutil.rmtree(f, ignore_errors=True)

    log_print("INFO", "Processing complete.")

if __name__ == "__main__":
    try:
        process_data()
    except Exception as e:
        log_print("ERROR", f"Unhandled exception: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
