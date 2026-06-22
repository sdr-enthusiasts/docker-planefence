#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

DB_PATH="${PF_RECORDS_DB_PATH:-/run/planefence/planefence-records.sqlite}"
PERSIST_DB_PATH="${PF_RECORDS_PERSIST_DB_PATH:-/usr/share/planefence/persist/records/planefence-records.sqlite}"
HELPER="/usr/share/planefence/pf-db.py"

echo "== pf-db smoketest =="
echo "backend=${PF_RECORDS_BACKEND:-${RECORDS_BACKEND:-unset}}"
echo "db=${DB_PATH}"
echo "persist_db=${PERSIST_DB_PATH}"

if [[ ! -x "$HELPER" ]]; then
  echo "ERROR: missing helper at $HELPER" >&2
  exit 1
fi

if [[ ! -f "$DB_PATH" ]]; then
  echo "ERROR: runtime db not found: $DB_PATH" >&2
  exit 1
fi

python3 "$HELPER" integrity-check --db "$DB_PATH"
python3 "$HELPER" show-profile

python3 - "$DB_PATH" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)

for table in ("pf_records", "pa_records", "heatmap", "day_snapshots"):
    count = conn.execute(f"select count(*) from {table}").fetchone()[0]
    print(f"{table}={count}")

row = conn.execute(
    "select value from globals_kv where key='LASTPROCESSEDLINE'"
).fetchone()
if row and row[0]:
    print("LASTPROCESSEDLINE=present")
else:
    print("LASTPROCESSEDLINE=missing")
PY

echo "== ok =="