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
# This script sends a Telegram notification
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/planefence.conf

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, butspost2telegram is called from another script, and we don't want to pollute the returns with info text


# shellcheck disable=SC2034
DEBUG="${DEBUG:-false}"
declare -a INDEX STALE
declare -a link

SPACE="_"   # "special" space replacement character for hashtagged items

# Check a bunch of stuff and determine if we should notify

if ! chk_enabled "$TELEGRAM_ENABLED"; then
  log_print DEBUG "Telegram is not enabled."
  exit 0
fi

log_print DEBUG "Hello. Starting Telegram notification run"

if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
  log_print ERR "Telegram is enabled, but TELEGRAM_BOT_TOKEN or PF_TELEGRAM_CHAT_ID aren't set. Aborting."
  exit
fi

if [[ -f "/usr/share/planefence/notifiers/telegram.pf.template" ]]; then
  template_clean="$(</usr/share/planefence/notifiers/telegram.pf.template)"
else
  log_print ERR "No Telegram template found at /usr/share/planefence/notifiers/telegram.pf.template. Aborting."
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

log_print DEBUG "Reading records for Telegram notification"

# Pin records date/file for the entire run to avoid midnight rollover races.
TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/run/planefence}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Telegram notification and stale records"
build_index_and_stale INDEX STALE telegram

if (( ${#INDEX[@]} )); then
  log_print DEBUG "Records ready for Telegram notification: ${INDEX[*]}"
else
  log_print DEBUG "No records ready for Telegram notification"
fi
if (( ${#STALE[@]} )); then
  log_print DEBUG "Stale records (no notification will be sent): ${STALE[*]}"
else
  log_print DEBUG "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print DEBUG "No records eligible for Telegram notification."
  exit 0
fi

# Fix $ATTRIB so it will show as a shortened URL:
ATTRIB="$(replace_urls "$ATTRIB")"

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Telegram notification for ${records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  aircraft_text="${records["$idx":owner]:-${records["$idx":callsign]}} (${records["$idx":tail]})"
  title_text="$(pf_notification_format_string "notify.text.title.pf" "{aircraft} is at {altitude} above {location}" "aircraft" "$aircraft_text" "altitude" "${records["$idx":altitude:value]} $ALTUNIT" "location" "${records["$idx":nominatim]}")"
  template="$(template_replace "||TITLE||" "$title_text" "$template")"
  squawk="${records["$idx":squawk:value]}"
  if [[ -n "$squawk" ]]; then
    line_squawk="$(pf_notification_format_string "notify.text.line.squawk" "Squawk: #{squawk}" "squawk" "$squawk")"
    template="$(template_replace "||LINE_SQUAWK||" "$line_squawk" "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      emergency_text="$(pf_notification_format_string "notify.text.emergencyPrefix" "Emergency: Squawk {squawk} - " "squawk" "$squawk")"
      template="$(template_replace "||EMERGENCY||" "$emergency_text" "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||LINE_SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi
  if [[ -n "${records["$idx":owner]}" ]]; then
    line_owner="$(pf_notification_format_string "notify.text.line.owner" "Owner: #{owner}" "owner" "${records["$idx":owner]// /${SPACE}}")"
    template="$(template_replace "||LINE_OWNER||" "$line_owner" "$template")"
  else
    template="$(template_replace "||LINE_OWNER||" "" "$template")"
  fi
  line_icao="$(pf_notification_format_string "notify.text.line.icao" "ICAO: #{icao}" "icao" "${records["$idx":icao]}")"
  template="$(template_replace "||LINE_ICAO||" "$line_icao" "$template")"
  callsign_tag="#${records["$idx":callsign]//-/}"
  tail_tag="$([[ "${records["$idx":tail]}" != "${records["$idx":callsign]}" ]] && echo "#${records["$idx":tail]//-/}" || true)"
  route_tag=""
  if [[ "${records["$idx":route]}" != "n/a" ]]; then
    route_tag="#${records["$idx":route]//-/-#}"
  else
    route_tag=""
  fi
  line_flight="$(pf_notification_format_string "notify.text.line.flight" "Flt: {callsign} {tail} #{type} {route}" "callsign" "$callsign_tag" "tail" "$tail_tag" "type" "${records["$idx":type]}" "route" "$route_tag")"
  line_flight="$(sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' <<< "$line_flight")"
  template="$(template_replace "||LINE_FLIGHT||" "$line_flight" "$template")"
  line_time="$(pf_notification_format_string "notify.text.line.time" "Time: {time}" "time" "$(date -d "@${records["$idx":time:time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")")"
  template="$(template_replace "||LINE_TIME||" "$line_time" "$template")"
  line_min_alt="$(pf_notification_format_string "notify.text.line.minAlt" "Min Alt: {alt}" "alt" "${records["$idx":altitude:value]} $ALTUNIT")"
  template="$(template_replace "||LINE_MIN_ALT||" "$line_min_alt" "$template")"
  line_min_dist="$(pf_notification_format_string "notify.text.line.minDist" "Min Dist: {dist}" "dist" "${records["$idx":distance:value]} $DISTUNIT (${records["$idx":angle:value]}° ${records["$idx":angle:name]})")"
  template="$(template_replace "||LINE_MIN_DIST||" "$line_min_dist" "$template")"
  if [[ -n ${records["$idx":sound:loudness]} ]]; then
    line_loudness="$(pf_notification_format_string "notify.text.line.loudness" "Loudness: {loudness} dB" "loudness" "${records["$idx":sound:loudness]}")"
    template="$(template_replace "||LINE_LOUDNESS||" "$line_loudness" "$template")"
  else
    template="$(template_replace "||LINE_LOUDNESS||" "" "$template")"
  fi
  template="$(template_replace "||ATTRIB||" "$ATTRIB " "$template")"

  links=""
  if [[ -n "${records["$idx":link:map]}" ]]; then links+="•<a href=\"${records["$idx":link:map]}\">$(extract_base "${records["$idx":link:map]}")</a>"; fi
  if [[ -n "${records["$idx":link:fa]}" ]]; then links+="•<a href=\"${records["$idx":link:fa]}\">$(extract_base "${records["$idx":link:fa]}")</a>"; fi
  if [[ -n "${records["$idx":link:faa]}" ]]; then links+="•<a href=\"${records["$idx":link:faa]}\">$(extract_base "${records["$idx":link:faa]}")</a>"; fi
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

  # Post to Telegram
  log_print DEBUG "Posting to Telegram: ${records["$idx":tail]} (${records["$idx":icao]})"

  # shellcheck disable=SC2068,SC2086
  if ! posturl="$(/scripts/post2telegram.sh PF "$template" ${img_array[@]})"; then result=false; else result=true; fi
  if $result; then
    log_print INFO "Telegram notification successful for #$idx ${records["$idx":tail]} (${records["$idx":icao]}): $posturl"
  else
    log_print ERR "Telegram notification failed for #$idx ${records["$idx":tail]} (${records["$idx":icao]})"
    log_print ERR "Telegram notification error details:\n$posturl"

    if [[ "$(jq '.ok' <<< "$posturl")" == "false" && "$(jq -r '.error_code' <<< "$posturl")" == "429" ]]; then
      retry_after="$(jq -r '.parameters.retry_after' <<< "$posturl")"
      if [[ $retry_after =~ ^[0-9]+$ ]]; then
        log_print ERR "Telegram rate limit exceeded. Retrying after $retry_after seconds..."
        sleep "$((retry_after + 1))"
        if posturl="$(extract_url "$posturl")"; then
          log_print INFO "Telegram notification successful for #$idx ${records["$idx":tail]} (${records["$idx":icao]}): $posturl"
        else
          log_print ERR "Telegram notification failed also the 2nd time for #$idx ${records["$idx":tail]} (${records["$idx":icao]})"
          log_print ERR "Telegram notification error details:\n$posturl"
        fi
      fi
    fi
  fi
  link[idx]="$posturl"
  sleep 3 # be nice to Telegram and space out messages a bit
done

# read, update, and thensave the records:
log_print DEBUG "Updating records after Telegram notifications"
LOCK_RECORDS
READ_RECORDS ignore-lock

for idx in "${STALE[@]}"; do
  records["$idx":telegram:notified]="stale"
done
for idx in "${!link[@]}"; do
  if [[ "${link[idx]:0:4}" == "http" ]]; then
    records["$idx":telegram:notified]=true
    records["$idx":telegram:link]="${link[idx]}"
  elif [[ "${link[idx]}" == "private" ]]; then
    records["$idx":telegram:notified]=true
    records["$idx":telegram:link]=""
  else
    records["$idx":telegram:notified]="error"
  fi
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Telegram notifications run completed."
