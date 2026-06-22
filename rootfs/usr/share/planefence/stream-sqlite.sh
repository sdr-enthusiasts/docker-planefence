#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154,SC2034
# -----------------------------------------------------------------------------------
# Phase 5 Stream Alternative: Direct SQLite Query Backend
# This module provides stream functionality via direct sqlite queries instead of
# pre-generated JSON files. Can be used alongside the legacy file-based approach
# for gradual migration.
# -----------------------------------------------------------------------------------
set -eo pipefail

source /scripts/pf-common

# ============================================================================
# Phase 5: Direct SQLite Query Functions
# ============================================================================

stream_pf_records_sqlite() {
  # Stream planefence records directly from sqlite for a given day
  # Usage: stream_pf_records_sqlite YYMMDD [--flatten]
  local day="${1:-}"
  local flatten="${2:-}"

  [[ -z "$day" ]] && return 1

  # Query all pf_records for the day
  local result
  result=$(DB_QUERY_RECORDS --table pf_records --day "$day" 2>/dev/null)

  # Emit as NDJSON (newline-delimited JSON)
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    printf '%s\n' "$rec"
  done <<< "$(printf '%s' "$result" | jq -c '.records[]? // empty' 2>/dev/null || echo "")"
}

stream_pa_records_sqlite() {
  # Stream plane-alert records directly from sqlite for a given day
  # Usage: stream_pa_records_sqlite YYMMDD
  local day="${1:-}"

  [[ -z "$day" ]] && return 1

  # Query all pa_records for the day
  local result
  result=$(DB_QUERY_RECORDS --table pa_records --day "$day" 2>/dev/null)

  # Emit as NDJSON
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    printf '%s\n' "$rec"
  done <<< "$(printf '%s' "$result" | jq -c '.records[]? // empty' 2>/dev/null || echo "")"
}

stream_pf_with_globals_sqlite() {
  # Stream planefence records with global state emitted first
  # Usage: stream_pf_with_globals_sqlite YYMMDD
  local day="${1:-}"

  [[ -z "$day" ]] && return 1

  # Emit globals first (no index field means it's globals)
  {
    # Get globals from kv storage
    local lastupdate maxindex hasimages hasnoise hasroute totallines
    lastupdate=$(DB_GET_KV --key "records:LASTUPDATE" 2>/dev/null || echo "0")
    maxindex=$(DB_GET_KV --key "records:maxindex" 2>/dev/null || echo "-1")
    hasimages=$(DB_GET_KV --key "records:HASIMAGES" 2>/dev/null || echo "false")
    hasnoise=$(DB_GET_KV --key "records:HASNOISE" 2>/dev/null || echo "false")
    hasroute=$(DB_GET_KV --key "records:HASROUTE" 2>/dev/null || echo "false")

    # Emit globals object (jq will handle JSON escaping)
    jq -n \
      --arg lastupdate "$lastupdate" \
      --arg maxindex "$maxindex" \
      --arg hasimages "$hasimages" \
      --arg hasnoise "$hasnoise" \
      --arg hasroute "$hasroute" \
      '{LASTUPDATE: $lastupdate, maxindex: $maxindex, HASIMAGES: $hasimages, HASNOISE: $hasnoise, HASROUTE: $hasroute}'
  }

  # Emit records
  stream_pf_records_sqlite "$day"
}

aggregate_pa_history_sqlite() {
  # Aggregate plane-alert history from sqlite for multiple days
  # Returns combined records from newest-first days, capped at MAX_ROWS
  local hist_days="${1:-14}"
  local max_rows="${2:-500}"
  local day=0 req_date

  declare -a all_records=()

  # Walk days backward, collect records until we hit MAX_ROWS
  for (( day=0; day<hist_days; day++ )); do
    req_date="$(date -u -d "-${day} days" +%y%m%d 2>/dev/null || true)"
    [[ -z "$req_date" ]] && continue

    local result
    result=$(DB_QUERY_RECORDS --table pa_records --day "$req_date" 2>/dev/null)

    while IFS= read -r rec; do
      [[ -z "$rec" ]] && continue
      (( ${#all_records[@]} < max_rows )) || break 2
      all_records+=("$rec")
    done <<< "$(printf '%s' "$result" | jq -c '.records[]? // empty' 2>/dev/null || echo "")"
  done

  # Emit as JSON array with globals first
  jq -n \
    --argjson records "$(printf '%s\n' "${all_records[@]}" | jq -s '.' 2>/dev/null || echo '[]')" \
    '{globals: {maxindex: ($records|length-1), totallines: ($records|length)}, records: $records}'
}

# ============================================================================
# Test functions (can be invoked directly)
# ============================================================================

test_sqlite_stream() {
  # Simple test of sqlite streaming
  local today="$(date +%y%m%d)"
  
  printf 'Testing sqlite stream for day: %s\n' "$today"
  printf 'PF Records:\n'
  stream_pf_records_sqlite "$today" | head -5 || echo "(none)"
  
  printf '\nPA Records:\n'
  stream_pa_records_sqlite "$today" | head -5 || echo "(none)"
  
  printf '\nPF with globals:\n'
  stream_pf_with_globals_sqlite "$today" | head -3 || echo "(none)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  test_sqlite_stream "$@"
fi
