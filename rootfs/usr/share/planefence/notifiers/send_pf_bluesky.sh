#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2164,SC1090,SC2154,SC1091
#---------------------------------------------------------------------------------------------
# Copyright (C) 2022-2026, Ramon F. Kolb (kx1t)
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
                    # Normally this isn't an issue, but post2bsky is called from another script, and we don't want to pollute the returns with info text


# shellcheck disable=SC2034
DEBUG="${DEBUG:-false}"
declare -a INDEX STALE
declare -a link

SPACE=$'\x1F'   # "special" space

# Load a bunch of stuff and determine if we should notify

if [[ -z "$BLUESKY_HANDLE" || -z "$BLUESKY_APP_PASSWORD" ]]; then
  log_print DEBUG "Bluesky notifications not enabled."
  exit 0
fi

log_print DEBUG "Hello. Starting Bluesky notification run"

if [[ -f "/usr/share/planefence/notifiers/bluesky.pf.template" ]]; then
  template_clean="$(</usr/share/planefence/notifiers/bluesky.pf.template)"
else
  log_print ERR "No Bluesky template found at /usr/share/planefence/notifiers/bluesky.pf.template. Aborting."
  exit 1
fi

pf_notification_init_language >/dev/null
pf_notification_log_language_warning

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  # shellcheck disable=SC2034
  screenshots=0
fi

log_print DEBUG "Reading records for Bluesky notification"

# Pin records date/file for the entire run to avoid midnight rollover races.
TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/run/planefence}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Bluesky notification and stale records"
build_index_and_stale INDEX STALE bsky

if (( ${#INDEX[@]} )); then
  log_print DEBUG "Records ready for Bluesky notification: ${INDEX[*]}"
else
  log_print DEBUG "No records ready for Bluesky notification"
fi
if (( ${#STALE[@]} )); then
  log_print DEBUG "Stale records (no notification will be sent): ${STALE[*]}"
else
  log_print DEBUG "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print DEBUG "No records eligible for Bluesky notification."
  exit 0
fi

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Bluesky notification for ${records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  squawk="${records["$idx":squawk:value]}"
  if [[ -n "$squawk" ]]; then
    line_squawk="$(pf_notification_format_string "notify.text.line.squawk" "Squawk: #{squawk}" "squawk" "$squawk")"
    template="$(template_replace "||LINE_SQUAWK||" "${line_squawk} " "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      emergency_tag="$(pf_notification_format_string "notify.text.emergencyTag" "#Emergency: #{description} " "description" "${records["$idx":squawk:description]// /${SPACE}}")"
      template="$(template_replace "||EMERGENCY||" "$emergency_tag" "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||LINE_SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi

  line_icao="$(pf_notification_format_string "notify.text.line.icao" "ICAO: #{icao}" "icao" "${records["$idx":icao]}")"
  template="$(template_replace "||LINE_ICAO||" "$line_icao" "$template")"

  if [[ -n "${records["$idx":owner]}" ]]; then
    line_owner="$(pf_notification_format_string "notify.text.line.owner" "Owner: #{owner}" "owner" "${records["$idx":owner]// /${SPACE}}")"
    template="$(template_replace "||LINE_OWNER||" "$line_owner" "$template")"
  else
    template="$(template_replace "||LINE_OWNER||" "" "$template")"
  fi
  callsign_tag="#${records["$idx":callsign]}"
  tail_tag="$([[ "${records["$idx":tail]}" != "${records["$idx":callsign]}" ]] && echo "#${records["$idx":tail]//-/}" || true)"
  route_tag=""
  if [[ -n "${records["$idx":route]}" && "${records["$idx":route]}" != "n/a" ]]; then
    route_tag="#${records["$idx":route]//-/-#}"
  fi
  line_flight="$(pf_notification_format_string "notify.text.line.flight" "Flt: {callsign} {tail} #{type} {route}" "callsign" "$callsign_tag" "tail" "$tail_tag" "type" "${records["$idx":type]}" "route" "$route_tag")"
  line_flight="$(sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' <<< "$line_flight")"
  template="$(template_replace "||LINE_FLIGHT||" "$line_flight" "$template")"

  line_time="$(pf_notification_format_string "notify.text.line.time" "Time: {time}" "time" "$(date -d "@${records["$idx":time:time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")")"
  template="$(template_replace "||LINE_TIME||" "$line_time" "$template")"

  line_min_alt="$(pf_notification_format_string "notify.text.line.minAlt" "Min Alt: {alt}" "alt" "${records["$idx":altitude:value]} $ALTUNIT")"
  template="$(template_replace "||LINE_MIN_ALT||" "$line_min_alt" "$template")"

  line_min_dist="$(pf_notification_format_string "notify.text.line.minDist" "Min Dist: {dist}" "dist" "${records["$idx":distance:value]} $DISTUNIT (${records["$idx":angle:value]}deg ${records["$idx":angle:name]})")"
  template="$(template_replace "||LINE_MIN_DIST||" "$line_min_dist" "$template")"

  if [[ -n ${records["$idx":sound:loudness]} ]]; then
    line_loudness="$(pf_notification_format_string "notify.text.line.loudness" "Loudness: {loudness} dB" "loudness" "${records["$idx":sound:loudness]}")"
    template="$(template_replace "||LINE_LOUDNESS||" "$line_loudness" "$template")"
  else
    template="$(template_replace "||LINE_LOUDNESS||" "" "$template")"
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
  elif [[ -n "${records["$idx":image:link]}" ]]; then
    img_array+=("${records["$idx":image:link]}")
  fi
  if [[ -n "${records["$idx":screenshot:file]}" && -f "${records["$idx":screenshot:file]}" ]]; then
    img_array+=("${records["$idx":screenshot:file]}")
  fi

  # Post to Bsky
  log_print DEBUG "Posting to Bsky: ${records["$idx":tail]} (${records["$idx":icao]})"

  # shellcheck disable=SC2068,SC2086
  posturl="$(/scripts/post2bsky.sh pf "$template" ${img_array[@]})" || true
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
