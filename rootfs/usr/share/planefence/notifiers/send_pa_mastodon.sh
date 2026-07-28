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
# This script sends a Mastodon notification
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/plane-alert.conf

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, but post2bsky is called from another script, and we don't want to pollute the returns with info text


# shellcheck disable=SC2034
DEBUG="${DEBUG:-false}"
declare -a INDEX STALE
declare -a link

#SPACE=$'\x1F'   # "special" space
SPACE="_"   # Mastodon does not allow special spaces in hashtags, so use underscore instead

# Load a bunch of stuff and determine if we should notify

if [[ -z "$MASTODON_ACCESS_TOKEN" || -z "$MASTODON_SERVER" ]]; then
  log_print DEBUG "Mastodon notifications not enabled."
  exit 0
fi

log_print DEBUG "Hello. Starting Mastodon notification run"

if [[ -f "/usr/share/planefence/notifiers/mastodon.pa.template" ]]; then
  template_clean="$(</usr/share/planefence/notifiers/mastodon.pa.template)"
else
  log_print ERR "No Mastodon template found at /usr/share/planefence/notifiers/mastodon.pa.template. Aborting."
  exit 1
fi

notif_lang="$(pf_notification_init_language)"
pf_notification_log_language_warning

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  # shellcheck disable=SC2034
  screenshots=0
fi

log_print DEBUG "Reading records for Mastodon notification"

# Pin records date/file for the entire run to avoid midnight rollover races.
TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/run/planefence}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Mastodon notification and stale records"
build_index_and_stale INDEX STALE mastodon pa

if (( ${#INDEX[@]} )); then
  log_print DEBUG "Records ready for Mastodon notification: ${INDEX[*]}"
else
  log_print DEBUG "No records ready for Mastodon notification"
fi
if (( ${#STALE[@]} )); then
  log_print DEBUG "Stale records (no notification will be sent): ${STALE[*]}"
else
  log_print DEBUG "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print DEBUG "No records eligible for Mastodon notification."
  exit 0
fi

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Mastodon notification for ${pa_records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  template="$(template_replace "||TXT_PREFIX_PA||" "$(pf_notification_string "notify.text.prefix.pa" "#PlaneAlert " "$notif_lang")" "$template")"

  squawk="${pa_records["$idx":squawk:value]}"
  if [[ -n "$squawk" ]]; then
    line_squawk="$(pf_notification_format_string "notify.text.line.squawk" "Squawk: #{squawk}" "squawk" "$squawk")"
    template="$(template_replace "||LINE_SQUAWK||" "${line_squawk}\\n" "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      emergency_tag="$(pf_notification_format_string "notify.text.emergencyTag" "#Emergency: #{description} " "description" "${pa_records["$idx":squawk:description]// /${SPACE}}")"
      template="$(template_replace "||EMERGENCY||" "$emergency_tag" "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||LINE_SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi

  line_icao="$(pf_notification_format_string "notify.text.line.icao" "ICAO: #{icao}" "icao" "${pa_records["$idx":icao]}")"
  template="$(template_replace "||LINE_ICAO||" "$line_icao" "$template")"

  if [[ -n "${pa_records["$idx":owner]}" ]]; then
    line_owner="$(pf_notification_format_string "notify.text.line.owner" "Owner: #{owner}" "owner" "${pa_records["$idx":owner]// /${SPACE}}")"
    template="$(template_replace "||LINE_OWNER||" "$line_owner" "$template")"
  else
    template="$(template_replace "||LINE_OWNER||" "" "$template")"
  fi
  callsign_tag="#${pa_records["$idx":callsign]//-/}"
  tail_tag="$([[ "${pa_records["$idx":tail]//-/}" != "${pa_records["$idx":callsign]//-/}" ]] && echo "#${pa_records["$idx":tail]//-/}" || true)"
  route_tag=""
  if [[ "${pa_records["$idx":route]}" != "n/a" ]]; then
    route_tag="#${pa_records["$idx":route]}"
  fi
  line_flight="$(pf_notification_format_string "notify.text.line.flight" "Flt: {callsign} {tail} #{type} {route}" "callsign" "$callsign_tag" "tail" "$tail_tag" "type" "${pa_records["$idx":type]}" "route" "$route_tag")"
  line_flight="$(sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' <<< "$line_flight")"
  template="$(template_replace "||LINE_FLIGHT||" "$line_flight" "$template")"

  line_time="$(pf_notification_format_string "notify.text.line.time" "Time: {time}" "time" "$(date -d "@${pa_records["$idx":time:time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")")"
  template="$(template_replace "||LINE_TIME||" "$line_time" "$template")"

  line_min_alt="$(pf_notification_format_string "notify.text.line.minAlt" "Min Alt: {alt}" "alt" "${pa_records["$idx":altitude:value]} $ALTUNIT")"
  template="$(template_replace "||LINE_MIN_ALT||" "$line_min_alt" "$template")"

  if [[ -n ${pa_records["$idx":sound:loudness]} ]]; then
    line_loudness="$(pf_notification_format_string "notify.text.line.loudness" "Loudness: {loudness} dB" "loudness" "${pa_records["$idx":sound:loudness]}")"
    template="$(template_replace "||LINE_LOUDNESS||" "$line_loudness" "$template")"
  else
    template="$(template_replace "||LINE_LOUDNESS||" "" "$template")"
  fi
  template="$(template_replace "||ATTRIB||" "$ATTRIB " "$template")"

  links="${pa_records["$idx":link:map]}${pa_records["$idx":link:map]:+ }"
  links+="${pa_records["$idx":link:fa]}${pa_records["$idx":link:fa]:+ }"
  links+="${pa_records["$idx":link:faa]}"
  template="$(template_replace "||LINKS||" "$links" "$template")"

  # Handle images
  img_array=()
  if [[ -n "${pa_records["$idx":image:file]}" && -f "${pa_records["$idx":image:file]}" ]]; then
    img_array+=("${pa_records["$idx":image:file]}")
  elif [[ -n "${pa_records["$idx":image:link]}" ]]; then
    img_array+=("${pa_records["$idx":image:link]}")
  fi
  if [[ -n "${pa_records["$idx":screenshot:file]}" && -f "${pa_records["$idx":screenshot:file]}" ]]; then
    img_array+=("${pa_records["$idx":screenshot:file]}")
  fi

  # Post to Bsky
  log_print DEBUG "Posting to Bsky: ${pa_records["$idx":tail]} (${pa_records["$idx":icao]})"

  # shellcheck disable=SC2068,SC2086
  posturl="$(/scripts/post2mastodon.sh pa "$template" ${img_array[@]})" || true
  if url="$(extract_url "$posturl")"; then
    log_print INFO "Mastodon notification successful for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]}): $url"
  else
    log_print ERR "Mastodon notification failed for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]})"
    log_print ERR "Mastodon notification error details: $posturl"
  fi
  link[idx]="$posturl"
done

# read, update, and thensave the records:
log_print DEBUG "Updating records after Mastodon notifications"
LOCK_RECORDS
READ_RECORDS ignore-lock

for idx in "${STALE[@]}"; do
  pa_records["$idx":mastodon:notified]="stale"
done
for idx in "${!link[@]}"; do
  if [[ "${link[idx]:0:4}" == "http" ]]; then
    pa_records["$idx":mastodon:notified]=true
    pa_records["$idx":mastodon:link]="${link[idx]}"
  else
    pa_records["$idx":mastodon:notified]="error"
  fi
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Mastodon notifications run completed."
