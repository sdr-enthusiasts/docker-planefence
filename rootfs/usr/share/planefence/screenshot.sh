#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2155
#
# PLANEFENCE - a Bash shell script to render a HTML and CSV table with nearby aircraft
#
# Usage: ./planefence.sh
#
# Copyright 2020-2026 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
#
# Summary of License Terms
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see https://www.gnu.org/licenses/.
# -----------------------------------------------------------------------------------
# Only change the variables below if you know what you are doing.

## DEBUG stuff:
#DEBUG=true

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf

declare -A screenshot_file_map=()
declare -A screenshot_checked_map=()
any_candidates=0

DEBUG=false
# ==========================
# Constants
# ==========================
SCREENFILEDIR="/usr/share/planefence/persist/planepix/cache"
MAXSCREENSHOTSPERRUN=5   # max number of screenshots to attempt per run, to ensure we can batch-process them

# ==========================
# Functions
# ==========================

build_index_and_stale_for_screenshot() {
  local -n _INDEX=$1
  local -n _STALE=$2
  local dataset_name=${3:-records}
  local -n _DATASET="$dataset_name"
  _INDEX=(); _STALE=()

  # Optional numeric ceiling from dataset[maxindex]
  local MAXIDX
  MAXIDX=${_DATASET[maxindex]}

  # Capture gawk output once, then demux without subshells
  local out
  out="$(
    {
      local k id field
      for k in "${!_DATASET[@]}"; do
        [[ $k == +([0-9]):* ]] || continue
        id=${k%%:*}
        [[ -n "$MAXIDX" && $id -gt $MAXIDX ]] && continue
        field=${k#*:}
        # Only pass fields we care about to reduce awk work
        case $field in
            complete|time:lastseen|checked:screenshot)
        printf '%s\t%s\t%s\n' "$id" "$field" "${_DATASET[$k]}"
            ;;
        esac
      done
    } | gawk -v CST="${CONTAINERSTARTTIME:-0}" '
      BEGIN { FS="\t" }
      {
        id=$1; key=$2; val=$3
        # Track presence/values per id
        if (key=="time:lastseen") { lastseen[id]=val+0; seen_last[id]=1 }
        else if (key=="complete") { complete[id]=val; seen_complete[id]=1 }
        else if (key=="checked:screenshot") { schecked[id]=val; seen_checked[id]=1 }
      }
      END {
        CSTN = CST+0
        # Consider all ids that have either lastseen or complete or checked
        for (id in seen_last) ids[id]=1
        for (id in seen_complete) ids[id]=1
        for (id in seen_checked) ids[id]=1

        for (id in ids) {
          # If checked:screenshot present with any non-empty value, skip the id entirely
          if (id in seen_checked && (schecked[id] != "")) continue

          # If complete missing or false/empty/0/no, skip
          if (!(id in seen_complete)) continue
          if (!is_truthy(complete[id])) continue

          # If lastseen exists and is less than container start, tag stale
          if ((id in seen_last) && (lastseen[id] < CSTN)) { stale[id]=1; continue }

          # Otherwise include as eligible
          ok[id]=1
        }

        # Print lists (tagged), numerically sorted
        ni=asorti(ok, oi, "@ind_num_asc"); for (i=1;i<=ni;i++) printf "I\t%s\n", oi[i]
        ns=asorti(stale, os, "@ind_num_asc"); for (i=1;i<=ns;i++) printf "S\t%s\n", os[i]
      }

      # Helper to determine truthy values (non-empty, not 0/false/no)
      function is_truthy(x, lx) { lx=tolower(x); return (x != "" && x != "0" && lx != "false" && lx != "no") }
    '
  )"

  local tag id
  while IFS=$'\t' read -r tag id; do
    [[ -z "$tag" ]] && continue
    if [[ "$tag" == I ]]; then _INDEX+=("$id"); else _STALE+=("$id"); fi
  done <<< "$out"
}


GET_SCREENSHOT () {
	# Function to get a screenshot
	# Usage: GET_SCREENSHOT index dataset_name dataset_label
  # returns file path to screenshot if successful, or empty if no screenshot was captured
  
  local idx="$1"
  local dataset_name="$2"
  local dataset_label="$3"
  local -n dataset_ref="$dataset_name"
  local icao="${dataset_ref["$idx":icao]}"
  local last_seen="${dataset_ref["$idx":time:lastseen]}"
  local safe_label=${dataset_label//[^A-Za-z0-9_-]/_}
  local screenfile="$SCREENFILEDIR/${safe_label,,}-screenshot-${icao}-${last_seen}.png"
  local image curl_error curl_status err_msg
  if [[ -z "$idx" ]]; then return; fi
  if [[ -z "$icao" ]]; then return; fi

  curl_error=$(mktemp)
  if [[ -z "$curl_error" ]]; then
    log_print ERR "${dataset_label}: Unable to create temp file for curl stderr"
    return
  fi
  
  # get new screenshot
  if curl -sL --fail --max-time "${SCREENSHOT_TIMEOUT:-60}" "${SCREENSHOTURL:-http://screenshot:5042}/snap/${icao}" --clobber > "$screenfile" 2>"$curl_error"; then
    image=$(mktemp)
    # pngquant will reduce the image to about 1/3 of its original size
    # drawback: it takes about a second or so to run
    if pngquant -f -o "$image" 64 "$screenfile" &>/dev/null; then
      mv -f "$image" "$screenfile"
    fi
    echo "$screenfile"
    rm -f "$curl_error"
    return
  else
    curl_status=$?
    err_msg=$(<"$curl_error")
    rm -f "$curl_error"
    # if retrieving the screenshot failed, remove any leftovers and return nothing
    rm -f "$screenfile"
    log_print ERR "${dataset_label}: Failed to get screenshot for #$idx ${icao} (${dataset_ref["$idx":tail]}): ${err_msg:-curl exited with status $curl_status}"
    return
  fi
}

process_dataset_for_screenshots() {
  local dataset_name="$1"
  local dataset_label="$2"
  local per_dataset_limit=${3:-$MAXSCREENSHOTSPERRUN}
  local -n dataset_ref="$dataset_name"
  local -a INDEX=()
  local -a STALE=()
  local -a rev_index=()
  local idx shot_path attempts max_to_process shots_remaining

  shots_remaining=$per_dataset_limit

  build_index_and_stale_for_screenshot INDEX STALE "$dataset_name"

  if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
    log_print DEBUG "${dataset_label}: no records eligible for screenshotting."
    return 0
  fi

  any_candidates=1
  log_print DEBUG "${dataset_label}: ${#INDEX[@]} new, ${#STALE[@]} stale"

  if (( ${#STALE[@]} > 0 )); then
    for idx in "${STALE[@]}"; do
      screenshot_checked_map["$dataset_name|$idx"]="stale"
      log_print DEBUG "${dataset_label}: marking stale record #$idx ${dataset_ref["$idx":icao]} (${dataset_ref["$idx":tail]}) as checked"
    done
  fi

  if (( shots_remaining <= 0 )); then
    log_print DEBUG "${dataset_label}: no screenshot slots remaining."
    return 0
  fi

  max_to_process=$shots_remaining
  if (( ${#INDEX[@]} < max_to_process )); then
    max_to_process=${#INDEX[@]}
  fi
  if (( max_to_process == 0 )); then
    return 0
  fi

  readarray -t rev_index < <(printf '%s\n' "${INDEX[@]}" | sort -nr)

  attempts=0
  for idx in "${rev_index[@]}"; do
    if (( attempts >= max_to_process || shots_remaining <= 0 )); then break; fi
    attempts=$((attempts + 1))
    shots_remaining=$((shots_remaining - 1))

    log_print DEBUG "${dataset_label}: attempting screenshot (${attempts}/${max_to_process}) for #$idx ${dataset_ref["$idx":icao]} (${dataset_ref["$idx":tail]})"
    shot_path="$(GET_SCREENSHOT "$idx" "$dataset_name" "$dataset_label")"
    if [[ -n "$shot_path" ]]; then
      screenshot_file_map["$dataset_name|$idx"]="$shot_path"
      log_print INFO "${dataset_label}: screenshot (${attempts}/${max_to_process}) successful for #$idx ${dataset_ref["$idx":icao]} (${dataset_ref["$idx":tail]}) -> $shot_path"
    else
      unset "screenshot_file_map[$dataset_name|$idx]"
      log_print DEBUG "${dataset_label}: screenshot failed for #$idx"
    fi
    screenshot_checked_map["$dataset_name|$idx"]="true"
  done
}

dataset_has_pending_updates() {
  local dataset_name="$1"
  local map_key current

  for map_key in "${!screenshot_file_map[@]}"; do
    current=${map_key%%|*}
    [[ "$current" == "$dataset_name" ]] && return 0
  done
  for map_key in "${!screenshot_checked_map[@]}"; do
    current=${map_key%%|*}
    [[ "$current" == "$dataset_name" ]] && return 0
  done
  return 1
}

persist_screenshot_updates() {
  local dataset_name="$1"
  local dataset_label="$2"
  local map_key idx status handled=1

  handled=1

  for map_key in "${!screenshot_file_map[@]}"; do
    local key_dataset=${map_key%%|*}
    [[ "$key_dataset" == "$dataset_name" ]] || continue
    idx=${map_key#*|}
    if [[ -z "$idx" ]]; then
      unset "screenshot_file_map[$map_key]"
      continue
    fi
    case "$dataset_name" in
      pa_records)
        if declare -p pa_records &>/dev/null; then
          pa_records["$idx":screenshot:file]="${screenshot_file_map[$map_key]}"
        else
          log_print WARN "${dataset_label}: dataset array missing when writing screenshot for #$idx"
        fi
        ;;
      records)
        records["$idx":screenshot:file]="${screenshot_file_map[$map_key]}"
        ;;
      *)
        log_print WARN "${dataset_label}: unknown dataset '$dataset_name' when writing screenshot"
        ;;
    esac
    log_print DEBUG "${dataset_label}: saved screenshot path for #$idx"
    unset "screenshot_file_map[$map_key]"
    handled=0
  done

  for map_key in "${!screenshot_checked_map[@]}"; do
    local key_dataset=${map_key%%|*}
    [[ "$key_dataset" == "$dataset_name" ]] || continue
    idx=${map_key#*|}
    status=${screenshot_checked_map[$map_key]:-true}
    if [[ -z "$idx" ]]; then
      unset "screenshot_checked_map[$map_key]"
      continue
    fi
    case "$dataset_name" in
      pa_records)
        if declare -p pa_records &>/dev/null; then
          pa_records["$idx":checked:screenshot]="$status"
        else
          log_print WARN "${dataset_label}: dataset array missing when writing status for #$idx"
        fi
        ;;
      records)
        records["$idx":checked:screenshot]="$status"
        ;;
      *)
        log_print WARN "${dataset_label}: unknown dataset '$dataset_name' when writing status"
        ;;
    esac
    log_print DEBUG "${dataset_label}: marked #$idx screenshot status '$status'"
    unset "screenshot_checked_map[$map_key]"
    handled=0
  done

  return $handled
}

# ==========================
# Main code
# ==========================
log_print DEBUG "Hello. Starting screenshot run"

if ! CHK_NOTIFICATIONS_ENABLED; then
  source /usr/share/planefence/plane-alert.conf
  if ! CHK_NOTIFICATIONS_ENABLED; then
    log_print ERR "No notifications enabled, exiting"
    exit 0
  fi
fi

if ! CHK_SCREENSHOT_ENABLED; then
  log_print ERR "Screenshots disabled or screenshot container cannot be reached, exiting"
  exit 0
fi

SCREENSHOT_TIMEOUT="${SCREENSHOT_TIMEOUT:-60}"
# max seconds to wait for screenshot retrieval


log_print DEBUG "Getting RECORDSFILE"
READ_RECORDS ignore-lock

any_candidates=0

process_dataset_for_screenshots records "Planefence" "$MAXSCREENSHOTSPERRUN"
if dataset_has_pending_updates records; then
  log_print DEBUG "Planefence: saving records after screenshot attempts"
  LOCK_RECORDS
  READ_RECORDS ignore-lock
  persist_screenshot_updates records "Planefence"
  WRITE_RECORDS ignore-lock
else
  log_print DEBUG "Planefence: no updates to persist"
fi

if declare -p pa_records &>/dev/null; then
  process_dataset_for_screenshots pa_records "Plane-Alert" "$MAXSCREENSHOTSPERRUN"
  if dataset_has_pending_updates pa_records; then
    log_print DEBUG "Plane-Alert: saving records after screenshot attempts"
    LOCK_RECORDS
    READ_RECORDS ignore-lock
    persist_screenshot_updates pa_records "Plane-Alert"
    WRITE_RECORDS ignore-lock
  else
    log_print DEBUG "Plane-Alert: no updates to persist"
  fi
else
  log_print DEBUG "Plane-Alert dataset not found; skipping"
fi

if (( any_candidates == 0 )); then
  log_print DEBUG "No records eligible for screenshotting."
  exit 0
fi

# Cleanup old screenshots
find "$SCREENFILEDIR" -type f -name '*-screenshot-*.png' -mmin +180 -exec rm -f {} \;
log_print INFO "Screenshot run completed."

