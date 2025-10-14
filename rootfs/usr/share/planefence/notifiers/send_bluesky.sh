#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2164,SC1090,SC2154,SC1091
#---------------------------------------------------------------------------------------------
# Copyright (C) 2022-2025, Ramon F. Kolb (kx1t)
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
#---------------------------------------------------------------------------------------------
# This script sends a Blueskynotification
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/planefence.conf

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, but post2bsky is called from another script, and we don't want to polute the returns with info text


# shellcheck disable=SC2034
#DEBUG=true
declare -a INDEX STALE
declare -a link

SPACE=$'\x1F'   # "special" space

log_print INFO "Hello. Starting Bluesky notification run"


# Load a bunch of stuff and determine if we should notify

if [[ -z "$BLUESKY_HANDLE" || -z "$BLUESKY_APP_PASSWORD" ]]; then
  log_print INFO "Bluesky notifications not enabled. Exiting."
  exit
fi

if [[ -f "/usr/share/planefence/notifiers/bluesky.template" ]]; then
  template_clean="$(</usr/share/planefence/notifiers/bluesky.template)"
else
  log_print ERR "No Bluesky template found at /usr/share/planefence/notifiers/bluesky.template. Aborting."
  exit 1
fi

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  # shellcheck disable=SC2034
  screenshots=0
fi

debug_print "Reading records for Bluesky notification"

READ_RECORDS

debug_print "Getting indices of records ready for Bluesky notification and stale records"
build_index_and_stale INDEX STALE bsky

if (( ${#INDEX[@]} )); then
  debug_print "Records ready for Bluesky notification: ${INDEX[*]}"
else
  debug_print "No records ready for Bluesky notification"
fi
if (( ${#STALE[@]} )); then
  debug_print "Stale records (no notification will be sent): ${STALE[*]}"
else
  debug_print "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print INFO "No records eligible for Bluesky notification. Exiting."
  exit 0
fi

for idx in "${INDEX[@]}"; do
  debug_print "Preparing Bluesky notification for ${records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  squawk="${records["$idx":squawk:value]}"
  if [[ -n "$squawk" ]]; then
    template="$(template_replace "||SQUAWK||" "#Squawk: $squawk\n" "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      template="$(template_replace "||EMERGENCY||" "#Emergency: #${records["$idx":squawk:description]// /${SPACE}} " "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi
  if [[ -n "${records["$idx":owner]}" ]]; then
    template="$(template_replace "||OWNER||" "Owner: #${records["$idx":owner]// /${SPACE}}" "$template")" # replace spaces in the owner name by the special ${SPACE} to keep them together in a hashtag
  else
    template="$(template_replace "||OWNER||" "" "$template")"
  fi
  template="$(template_replace "||ICAO||" "${records["$idx":icao]}" "$template")"
  template="$(template_replace "||CALLSIGN||" "${records["$idx":callsign]}" "$template")"
  template="$(template_replace "||TAIL||" "$([[ "${records["$idx":tail]}" != "${records["$idx":callsign]}" ]] && echo "#${records["$idx":tail]}" || true)" "$template")"
  template="$(template_replace "||TYPE||" "${records["$idx":type]}" "$template")"
  if [[ "${records["$idx":route]}" != "n/a" ]]; then 
    template="$(template_replace "||ROUTE||" "#${records["$idx":route]}" "$template")"
  else
    template="$(template_replace "||ROUTE||" "" "$template")"
  fi
  template="$(template_replace "||TIME||" "$(date -d "@${records["$idx":time:time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")" "$template")"
  template="$(template_replace "||ALT||" "${records["$idx":altitude:value]} $ALTUNIT" "$template")"
  template="$(template_replace "||DIST||" "${records["$idx":distance:value]} $DISTUNIT (${records["$idx":angle:value]}° ${records["$idx":angle:name]})" "$template")"
  if [[ -n ${records["$idx":sound:loudness]} ]]; then
    template="$(template_replace "||LOUDNESS||" "Loudness: ${records["$idx":sound:loudness]} dB" "$template")"
  else
    template="$(template_replace "||LOUDNESS||" "" "$template")"
  fi
  template="$(template_replace "||ATTRIB||" "$ATTRIB " "$template")"

  links="${records["$idx":link:map]}${records["$idx":link:map]:+ }"
  links+="${records["$idx":link:fa]}${records["$idx":link:fa]:+ }"
  links+="${records["$idx":link:faa]}"
  template="$(template_replace "||LINKS||" "$links" "$template")"

  # Handle images
  img_array=()
  if [[ -n "${records["$idx":image:file]}" && -f "${records["$idx":image:file]}" ]]; then
    img_array+=("${records["$idx":image:file]}")
  fi
  if [[ -n "${records["$idx":screenshot:file]}" && -f "${records["$idx":screenshot:file]}" ]]; then
    img_array+=("${records["$idx":screenshot:file]}")
  fi

  # Post to Bsky
  debug_print "Posting to Bsky: ${records["$idx":tail]} (${records["$idx":icao]})"

  # shellcheck disable=SC2068,SC2086
  posturl="$(/scripts/post2bsky.sh "$template" ${img_array[@]})" || true
  if posturl="$(extract_url "$posturl")"; then
    log_print INFO "Bluesky notification successful for #$idx ${records["$idx":tail]} (${records["$idx":icao]}): $posturl"
  else
    log_print ERR "Bluesky notification failed for #$idx ${records["$idx":tail]} (${records["$idx":icao]})"
    log_print ERR "Bluesky notification error details:\n$posturl"
  fi
  link[idx]="$posturl"
done

# read, update, and thensave the records:
log_print DEBUG "Updating records after Bluesky notifications"
LOCK_RECORDS
READ_RECORDS ignore-lock

for idx in "${STALE[@]}"; do
  records["$idx":bsky:notified]="stale"
done
for idx in "${!link[@]}"; do
  if [[ "${link[idx]:0:4}" == "http" ]]; then
    records["$idx":bsky:notified]=true
    records["$idx":bsky:link]="${link[idx]}"
  else
    records["$idx":bsky:notified]="error"
  fi
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Bluesky notifications run completed."
