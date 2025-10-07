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
set -eo pipefail
LC_ALL=C

## DEBUG stuff:
DEBUG=true

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf

declare -A screenshot_file=()
declare -A screenshot_checked=()
declare -a index


# ==========================
# Constants
# ==========================
SCREENFILEDIR="/usr/share/planefence/persist/planepix/cache"
MAXSCREENSHOTSPERRUN=5   # max number of screenshots to attempt per run, to ensure we can batch-process them

# ==========================
# Functions
# ==========================

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
log_print INFO "Starting screenshot additions run"

if ! CHK_NOTIFICATIONS_ENABLED; then
  log_print ERR "No notifications enabled, exiting"
  exit 0
fi

if ! CHK_SCREENSHOT_ENABLED; then
  log_print ERR "Screenshots disabled or screenshot container cannot be reached, exiting"
  exit 0
fi

debug_print "Getting $RECORDSFILE"
READ_RECORDS ignore-lock

# Make an index of records to process
# Pre-filter keys in bash to reduce awk input volume
tmpfile="$(mktemp)"

# Only dump keys we care about; avoids 2/3 of 50k lines if many are irrelevant
for k in "${!records[@]}"; do
  case "$k" in
    *:complete|*:lastseen|*:screenshot:checked)
      printf '%s\037%s\n' "$k" "${records[$k]}" >>"$tmpfile"
      ;;
  esac
done

readarray -t index < <(
  awk -v CST="$CONTAINERSTARTTIME" -v RS='\n' -v FS='\037' '
    {
      # k = key "idx:..."; v = value
      k=$1; v=$2
      # split key into idx + components
      n=split(k, p, ":"); idx=p[1]
      if (idx !~ /^[0-9]+$/) next

      have[idx]=1
      # map attribute
      if (n==2) {
        if (p[2]=="complete")      complete[idx]=(v=="true")
        else if (p[2]=="lastseen") lastseen[idx]=v+0
      } else if (n==3 && p[2]=="screenshot" && p[3]=="checked") {
        scrchk[idx]=(v=="true")
      }
    }
    END {
      for (i in have)
        if (complete[i] && !scrchk[i] && (i in lastseen) && lastseen[i] >= CST)
          print i
    }
  ' "$tmpfile"
)

# Second query: indices where lastseen < CST and screenshot:checked != true
readarray -t stale_indices < <(
  awk -v CST="$CONTAINERSTARTTIME" -v FS='\037' '
    {
      k=$1; v=$2
      n=split(k, p, ":"); idx=p[1]
      if (idx !~ /^[0-9]+$/) next

      if (n==2 && p[2]=="lastseen")               lastseen[idx]=v+0
      else if (n==3 && p[2]=="screenshot" && p[3]=="checked") scrchk[idx]=(v=="true")
      seen[idx]=1
    }
    END {
      for (i in seen)
        if ((i in lastseen) && lastseen[i] < CST && !scrchk[i])
          print i
    }
  ' "$tmpfile"
)

rm -f "$tmpfile"

counter=0
for idx in "${index[@]}"; do
  # Process each record in the records array
  counter=$((counter++))
  if (( counter > MAXSCREENSHOTSPERRUN )); then
    debug_print "Reached max screenshots per run ($MAXSCREENSHOTSPERRUN), stopping here"
    break
  fi

  debug_print "Attempting screenshot for #$idx ${records["$idx":icao]} (${records["$idx":tail]})"
  screenshot_file["$idx"]="$(GET_SCREENSHOT "$idx")"

  if [[ -n "${screenshot_file["$idx"]}" ]]; then
    debug_print "Got screenshot for #$idx ${records["$idx":icao]} (${records["$idx":tail]}): ${screenshot_file["$idx"]}"
  else
    unset "${screenshot_file["$idx"]}"
    debug_print "Screenshot failed for #$idx ${records["$idx":icao]} (${records["$idx":tail]})"
  fi
  screenshot_checked["$idx"]=true
done

for idx in "${stale_indices[@]}"; do
  # Mark stale records as checked, so we don't try again
  screenshot_checked["$idx"]=true
  debug_print "Marking stale record #$idx ${records["$idx":icao]} (${records["$idx":tail]}) as checked"
done

# Read records again, lock them, update them, and write them back
debug_print "Saving records after screenshot attempts"
LOCK_RECORDS
READ_RECORDS ignore-lock
for idx in "${!screenshot_file[@]}"; do
    records["$idx":screenshot:file]="${screenshot_file["$idx"]}"
done
for idx in "${!screenshot_checked[@]}"; do
    records["$idx":screenshot:checked]=true
done
debug_print "Wrote screenshot files to indices: ${!screenshot_file[*]}"
debug_print "Wrote screenshot checked to indices: ${!screenshot_checked[*]}"
WRITE_RECORDS ignore-lock

# Cleanup old screenshots
find "$SCREENFILEDIR" -type f -name 'screenshot-*.png' -mmin +180 -exec rm -f {} \;
log_print INFO "Screenshot additions run completed."
