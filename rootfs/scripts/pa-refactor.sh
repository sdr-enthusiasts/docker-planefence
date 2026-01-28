#!/command/with-contenv bash
#shellcheck shell=bash 
# shellcheck disable=SC1091
# Consolidate Plane-Alert records from recent days.

# shellcheck source=/scripts/pf-common
source /scripts/pf-common

set -eo pipefail
LC_ALL=C

usage() {
  cat <<'USAGE' >&2
Usage: pa-refactor.sh [<num_of_days>] [<output_file>]
  <num_of_days>   Number of days to consolidate (default: 2)
  <output_file>   Output records file; may be provided as first arg if days are omitted
USAGE
  exit 1
}

ensure_assoc() {
  local name=$1
  if ! declare -p "$name" >/dev/null 2>&1; then
    declare -gA "$name"
  fi
}

find_records_file() {
  local day=$1
  local candidates=(
    "/run/planefence/planefence-records-${day}.gz"
    "/usr/share/planefence/persist/records/planefence-records-${day}.gz"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -f "$path" ]]; then
      printf '%s' "$path"
      return 0
    fi
  done
  return 1
}

merge_pa_records() {
  local -n src=$1
  local -A idx_map=()
  local key old_idx new_idx suffix

  for key in "${!src[@]}"; do
    if [[ $key == maxindex ]]; then
      continue
    elif [[ $key =~ ^([0-9]+):(.*)$ ]]; then
      old_idx=${BASH_REMATCH[1]}
      suffix=${BASH_REMATCH[2]}
      if [[ -z ${idx_map[$old_idx]+x} ]]; then
        merged_max=$(( merged_max + 1 ))
        idx_map[$old_idx]=$merged_max
      fi
      new_idx=${idx_map[$old_idx]}
      merged_pa_records["${new_idx}:$suffix"]="${src[$key]}"
    else
      merged_pa_records["$key"]="${src[$key]}"
    fi
  done
}

# Arguments
RAW_FIRST=${1:-}
RAW_SECOND=${2:-}

if [[ -n $RAW_FIRST && $RAW_FIRST =~ ^[0-9]+$ ]]; then
  DAYS=$RAW_FIRST
  OUTPUT_ARG=$RAW_SECOND
else
  DAYS=2
  OUTPUT_ARG=$RAW_FIRST
fi

if ! [[ $DAYS =~ ^[0-9]+$ ]] || (( DAYS < 1 )); then
  usage
fi

TODAY=$(date +%y%m%d)
DEFAULT_OUTPUT="/run/planefence/planefence-records-${TODAY}.gz"
RECORDSFILE=${OUTPUT_ARG:-$DEFAULT_OUTPUT}
mkdir -p -- "$(dirname "$RECORDSFILE")"

log_print INFO "Consolidating Plane-Alert records for last ${DAYS} day(s)"

declare -gA merged_pa_records=()
merged_pa_records[maxindex]=-1
merged_max=-1
todays_file=""

for (( offset=0; offset<DAYS; offset++ )); do
  day=$(date -d "-${offset} day" +%y%m%d)
  file=$(find_records_file "$day") || { log_print WARN "Records file for ${day} not found; skipping"; continue; }
  [[ $offset -eq 0 ]] && todays_file="$file"
  # shellcheck disable=SC1090
  if source <(gzip -cd "$file"); then
    ensure_assoc pa_records
    [[ -z ${pa_records[maxindex]+x} ]] && pa_records[maxindex]=-1
    merge_pa_records pa_records
  else
    log_print WARN "Could not read ${file}; skipping"
  fi
done

# Keep an explicit maxindex for the merged structure
merged_pa_records[maxindex]=$merged_max

# Re-load today's records (or initialize) for non-PA structures
if [[ -n $todays_file ]]; then
  # shellcheck disable=SC1090
  if ! source <(gzip -cd "$todays_file"); then
    log_print WARN "Failed to reload today's records; falling back to empty defaults"
    unset records heatmap last_idx_for_icao lastseen_for_icao pa_records pa_last_idx_for_icao LASTPROCESSEDLINE
  fi
else
  unset records heatmap last_idx_for_icao lastseen_for_icao pa_records pa_last_idx_for_icao LASTPROCESSEDLINE
fi

ensure_assoc records
ensure_assoc heatmap
ensure_assoc last_idx_for_icao
ensure_assoc lastseen_for_icao
ensure_assoc pa_records
ensure_assoc pa_last_idx_for_icao
[[ -z ${records[maxindex]+x} ]] && records[maxindex]=-1
[[ -z ${LASTPROCESSEDLINE+x} ]] && LASTPROCESSEDLINE=""

# Replace PA data with merged content
unset pa_records pa_last_idx_for_icao
declare -gA pa_records
declare -gA pa_last_idx_for_icao
pa_records=()
for key in "${!merged_pa_records[@]}"; do
  pa_records["$key"]="${merged_pa_records[$key]}"
  if [[ $key == maxindex ]]; then
    merged_max=${merged_pa_records[$key]}
  fi
done
[[ -z ${pa_records[maxindex]+x} ]] && pa_records[maxindex]=$merged_max

# Build pa_last_idx_for_icao map
# shellcheck disable=SC2034
if (( ${pa_records[maxindex]:--1} >= 0 )); then
  for (( idx=0; idx<=pa_records[maxindex]; idx++ )); do
    icao_val="${pa_records["${idx}:icao"]}"
    [[ -n $icao_val ]] && pa_last_idx_for_icao["$icao_val"]="$idx"
  done
fi

# Finalize maxindex
if (( merged_max >= 0 )); then
  pa_records[maxindex]=$merged_max
else
  pa_records[maxindex]=-1
fi

WRITE_RECORDS ""
log_print INFO "Consolidated Plane-Alert records written to ${RECORDSFILE}"
