#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2155
#
# PLANEFENCE - a Bash shell script to render a HTML and CSV table with nearby aircraft
#
# Usage: ./planefence.sh
#
# Copyright 2020-2025 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
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
DEBUG=true

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf

declare -A screenshot_file=()
declare -A screenshot_checked=()
declare -a INDEX STALE


# ==========================
# Constants
# ==========================
SCREENFILEDIR="/usr/share/planefence/persist/planepix/cache"
MAXSCREENSHOTSPERRUN=5   # max number of screenshots to attempt per run, to ensure we can batch-process them

# ==========================
# Functions
# ==========================

build_index_and_stale() {
  local -n _INDEX=$1
  local -n _STALE=$2
  _INDEX=(); _STALE=()

  # Optional numeric ceiling from records[maxindex]
  local MAXIDX
  MAXIDX=${records[maxindex]}

  # Capture gawk output once, then demux without subshells
  local out
  out="$(
    {
      local k id field
      for k in "${!records[@]}"; do
        [[ $k == +([0-9]):* ]] || continue
        id=${k%%:*}
        [[ -n "$MAXIDX" && $id -gt $MAXIDX ]] && continue
        field=${k#*:}
        # Only pass fields we care about to reduce awk work
        case $field in
            complete|time:lastseen|checked:screenshot)
            printf '%s\t%s\t%s\n' "$id" "$field" "${records[$k]}"
            ;;
        esac
      done
    } | gawk -v CST="${CONTAINERSTARTTIME:-0}" -v SS="${screenshots:-0}" '
      BEGIN { FS="\t" }
      {
        id=$1; key=$2; val=$3
        if (key=="time:lastseen")           { lastseen[id]=val+0; ids[id]=1 }
        else if (key=="complete")           complete[id]=val
        else if (key=="checked:screenshot") schecked[id]=val
      }
      END {        
        CSTN = CST+0
        # Evaluate only ids that have lastseen
        for (id in ids) {
          ls = lastseen[id]
          # stale first
          if (ls < CSTN && n == "") { stale[id]=1; continue }
          # eligibility checks
          c  = (id in complete)? complete[id] : ""
          if (!enabled(c)) continue
          if (enabled(n)) continue
          if (n=="error") continue
          if (SS && !enabled((id in schecked)? schecked[id] : "")) continue
          ok[id]=1
        }
        # Print lists (tagged), numerically sorted
        ni=asorti(ok, oi, "@ind_num_asc"); for (i=1;i<=ni;i++) printf "I\t%s\n", oi[i]
        ns=asorti(stale, os, "@ind_num_asc"); for (i=1;i<=ns;i++) printf "S\t%s\n", os[i]
      }
      function enabled(x, y){ y=tolower(x); return (x!="" && x!="0" && y!="false" && y!="no") }
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
	# Usage: GET_SCREENSHOT index 
  # returns file path to screenshot if successful, or empty if no screenshot was captured
  
  local idx="$1"
  local screenfile="$SCREENFILEDIR/screenshot-${records["$idx":icao]}-${records["$idx":lastseen]}.png"
  local image
  if [[ -z "$idx" ]]; then return; fi
  
  # get new screenshot
  if curl -sL --fail --max-time "${SCREENSHOT_TIMEOUT:-60}" "${SCREENSHOTURL:-screenshot}/snap/${records["$idx":icao]}" --clobber > "$screenfile"; then
    image=$(mktemp)
    # pngquant will reduce the image to about 1/3 of its original size
    # drawback: it takes about a second or so to run
    if pngquant -f -o "$image" 64 "$screenfile" &>/dev/null; then
      mv -f "$image" "$screenfile"
    fi
    echo "$screenfile"
    return
  fi

  # if retrieving the screenshot failed, remove any leftovers and return nothing
  rm -f "$screenfile"
  return
}

# ==========================
# Main code
# ==========================
log_print INFO "Hello. Starting screenshot run"

if ! CHK_NOTIFICATIONS_ENABLED; then
  log_print ERR "No notifications enabled, exiting"
  exit 0
fi

if ! CHK_SCREENSHOT_ENABLED; then
  log_print ERR "Screenshots disabled or screenshot container cannot be reached, exiting"
  exit 0
fi

log_print DEBUG "Getting RECORDSFILE"
READ_RECORDS ignore-lock

# Make an index of records to process
debug_print "Getting indices ready for new and stale records"
build_index_and_stale INDEX STALE

# If there's nothing to do, exit
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print INFO "No records eligible for Bluesky notification. Exiting."
  exit 0
else debug_print "Records to process: ${#INDEX[@]} new, ${#STALE[@]} stale"
fi

counter=0
if (( ${#INDEX[@]} < MAXSCREENSHOTSPERRUN )); then MAXSCREENSHOTSPERRUN=${#INDEX[@]}; fi

# Go through the indices in reverse order. That way, the newest/latest are processed first

readarray -t rev_index < <(printf '%s\n' "${INDEX[@]}" | sort -nr)

for idx in "${rev_index[@]}"; do
  # Process each record in the records array
  counter=$((++counter))
  if (( counter > MAXSCREENSHOTSPERRUN )); then
    log_print DEBUG "Reached max screenshots per run ($MAXSCREENSHOTSPERRUN), stopping here"
    break
  fi

  log_print DEBUG "Attempting screenshot ($counter/$MAXSCREENSHOTSPERRUN) for #$idx ${records["$idx":icao]} (${records["$idx":tail]})"
  screenshot_file["$idx"]="$(GET_SCREENSHOT "$idx")"

  if [[ -n "${screenshot_file["$idx"]}" ]]; then
    log_print DEBUG "Got screenshot ($counter/$MAXSCREENSHOTSPERRUN) for #$idx ${records["$idx":icao]} (${records["$idx":tail]}): ${screenshot_file["$idx"]}"
  else
    unset "${screenshot_file["$idx"]}"
    log_print DEBUG "Screenshot ($counter/$MAXSCREENSHOTSPERRUN) failed for #$idx ${records["$idx":icao]} (${records["$idx":tail]})"
  fi
  screenshot_checked["$idx"]=true
done

for idx in "${stale_indices[@]}"; do
  # Mark stale records as checked, so we don't try again
  screenshot_checked["$idx"]=true
  log_print DEBUG "Marking stale record #$idx ${records["$idx":icao]} (${records["$idx":tail]}) as checked"
done

# Read records again, lock them, update them, and write them back
log_print DEBUG "Saving records after screenshot attempts"
LOCK_RECORDS
READ_RECORDS ignore-lock
for idx in "${!screenshot_file[@]}"; do
    records["$idx":screenshot:file]="${screenshot_file["$idx"]}"
done
for idx in "${!screenshot_checked[@]}"; do
    records["$idx":checked:screenshot]=true
done
log_print DEBUG "Wrote screenshot files to indices: ${!screenshot_file[*]}"
log_print DEBUG "Wrote screenshot checked to indices: ${!screenshot_checked[*]}"
WRITE_RECORDS ignore-lock

# Cleanup old screenshots
find "$SCREENFILEDIR" -type f -name 'screenshot-*.png' -mmin +180 -exec rm -f {} \;
log_print INFO "Screenshot run completed."
