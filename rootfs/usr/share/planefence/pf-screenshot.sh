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

## DEBUG stuff:
DEBUG=true

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf

declare -A screenshot_file=()
declare -A screenshot_checked=()


# ==========================
# Constants
# ==========================
SCREENFILEDIR="/usr/share/planefence/persist/planepix/cache"

# ==========================
# Functions
# ==========================

GET_SCREENSHOT () {
	# Function to get a screenshot
	# Usage: GET_SCREENSHOT index 
  # returns file path to screenshot if successful, or empty if no screenshot was captured
  
  local idx="$1"
  local screenfile="$SCREENFILEDIR/screenshot-${records["$idx":icao]}-${records["$idx":lastseen]}.jpg"

  if [[ -z "$idx" ]]; then return; fi
  
  # get new screenshot
  if curl -sL --fail --max-time "${SCREENSHOT_TIMEOUT:-60}" "${SCREENSHOTURL:-screenshot}/snap/${records["$idx":icao]}" --clobber > "$screenfile"; then
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

for ((idx=0; idx<records[maxindex]; idx++)); do
  # Process each record in the records array

  # Skip if record is incomplete or screenshot already checked
  if chk_enabled "${records["$idx":screenshot:checked]}" || ! chk_enabled "${records["$idx":complete]}"; then
    debug_print "Record incomplete or screenshot already attempted for #$idx ${records["$idx":icao]} (${records["$idx":tail]})"
    continue
  fi

  # Skip if lastseen is older than container start time (i.e. before this container was started). We won't notify or get screenshots for these
  # as getting screenshots is computationally expensive and pointless for old records
  if (( "${records["$idx":lastseen]}" <= CONTAINERSTARTTIME )); then
    debug_print "Skipping screenshot for #$idx ${records["$idx":icao]} (${records["$idx":tail]}) - lastseen before container start time"
    screenshot_checked["$idx"]=true
    continue
  fi

  # If we reach here, try to get a screenshot if not already checked and lastseen is after container start time
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
# Read records again, lock them, update them, and write them back
debug_print "Saving records after screenshot attempts"
LOCK_RECORDS
READ_RECORDS
for idx in "${!screenshot_file[@]}"; do
    records["$idx":screenshot:file]="${screenshot_file["$idx"]}"
done
for idx in "${!screenshot_checked[@]}"; do
    records["$idx":screenshot:checked]=true
done
debug_print "Wrote screenshot files to indices: ${!screenshot_file[*]}"
debug_print "Wrote screenshot checked to indices: ${!screenshot_checked[*]}"
WRITE_RECORDS ignore-lock
log_print INFO "Screenshot additions run completed."
