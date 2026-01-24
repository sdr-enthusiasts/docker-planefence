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
source /usr/share/planefence/plane-alert.conf

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, butspost2telegram is called from another script, and we don't want to polute the returns with info text


# shellcheck disable=SC2034
DEBUG=false
declare -a INDEX STALE
declare -a link

SPACE="_"   # "special" space replacement character for hashtagged items

log_print INFO "Hello. Starting Telegram notification run"

# Check a bunch of stuff and determine if we should notify

if ! chk_enabled "$TELEGRAM_ENABLED"; then
  log_print INFO "Telegram is not enabled. Exiting."
fi

if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
  log_print ERR "Telegram is enabled, but TELEGRAM_BOT_TOKEN or PF_TELEGRAM_CHAT_ID aren't set. Aborting."
  exit
fi

if [[ -f "/usr/share/planefence/notifiers/telegram.pa.template" ]]; then
  template_clean="$(</usr/share/planefence/notifiers/telegram.pa.template)"
else
  log_print ERR "No Telegram template found at /usr/share/planefence/notifiers/telegram.pa.template. Aborting."
  exit 1
fi

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  # shellcheck disable=SC2034
  screenshots=0
fi

log_print DEBUG "Reading records for Telegram notification"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Telegram notification and stale records"
build_index_and_stale INDEX STALE telegram pa

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
  log_print INFO "No records eligible for Telegram notification. Exiting."
  exit 0
fi

# Fix $ATTRIB so it will show as a shortened URL:
ATTRIB="$(replace_urls "$ATTRIB")"

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Telegram notification for ${pa_records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  squawk="${pa_records["$idx":squawk:value]}"
  if [[ -n "$squawk" ]]; then
    template="$(template_replace "||SQUAWK||" "#Squawk: $squawk${NEWLINE}" "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      template="$(template_replace "||EMERGENCY||" "#Emergency: #${pa_records["$idx":squawk:description]// /${SPACE}} " "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi
  if [[ -n "${pa_records["$idx":owner]}" ]]; then
    template="$(template_replace "||OWNER||" "Owner: #${pa_records["$idx":owner]// /${SPACE}}" "$template")" # replace spaces in the owner name by the special ${SPACE} to keep them together in a hashtag
  else
    template="$(template_replace "||OWNER||" "" "$template")"
  fi
  template="$(template_replace "||ICAO||" "${pa_records["$idx":icao]}" "$template")"
  template="$(template_replace "||CALLSIGN||" "${pa_records["$idx":callsign]//-/}" "$template")"
  template="$(template_replace "||TAIL||" "$([[ "${pa_records["$idx":tail]}" != "${pa_records["$idx":callsign]}" ]] && echo "#${pa_records["$idx":tail]//-/}" || true)" "$template")"
  if [[ "${pa_records["$idx":route]}" != "n/a" ]]; then 
    template="$(template_replace "||ROUTE||" "#${pa_records["$idx":route]//-/-#}" "$template")"
  else
    template="$(template_replace "||ROUTE||" "" "$template")"
  fi
  template="$(template_replace "||TIME||" "$(date -d "@${pa_records["$idx":time:time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")" "$template")"
  template="$(template_replace "||ALT||" "${pa_records["$idx":altitude:value]} $ALTUNIT" "$template")"
  template="$(template_replace "||DIST||" "${pa_records["$idx":distance:value]} $DISTUNIT (${pa_records["$idx":angle:value]}° ${pa_records["$idx":angle:name]})" "$template")"
  template="$(template_replace "||ATTRIB||" "$ATTRIB " "$template")"

  links=""
  if [[ -n "${pa_records["$idx":link:map]}" ]]; then links+="•<a href=\"${pa_records["$idx":link:map]}\">$(extract_base "${pa_records["$idx":link:map]}")</a>"; fi
  if [[ -n "${pa_records["$idx":link:fa]}" ]]; then links+="•<a href=\"${pa_records["$idx":link:fa]}\">$(extract_base "${pa_records["$idx":link:fa]}")</a>"; fi
  if [[ -n "${pa_records["$idx":link:faa]}" ]]; then links+="•<a href=\"${pa_records["$idx":link:faa]}\">$(extract_base "${pa_records["$idx":link:faa]}")</a>"; fi
  template="$(template_replace "||LINKS||" "$links" "$template")"
  template="$(template_replace "||TYPE||" "${pa_records["$idx":type]:+#}${pa_records["$idx":type]}" "$template")"

  # Handle images
  img_array=()
  if [[ -n "${pa_records["$idx":image:file]}" && -f "${pa_records["$idx":image:file]}" ]]; then
    img_array+=("${pa_records["$idx":image:file]}")
  fi
  if [[ -n "${pa_records["$idx":screenshot:file]}" && -f "${pa_records["$idx":screenshot:file]}" ]]; then
    img_array+=("${pa_records["$idx":screenshot:file]}")
  fi

  # Post to Telegram
  log_print DEBUG "Posting to Telegram: ${pa_records["$idx":tail]} (${pa_records["$idx":icao]})"

  # shellcheck disable=SC2068,SC2086
  if ! posturl="$(/scripts/post2telegram.sh PA "$template" ${img_array[@]})"; then result=false; else result=true; fi
  if $result; then
    log_print INFO "Telegram notification successful for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]}): $posturl"
  else
    log_print ERR "Telegram notification failed for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]})"
    log_print ERR "Telegram notification error details:\n$posturl"

    if [[ "$(jq '.ok' <<< "$posturl")" == "false" && "$(jq -r '.error_code' <<< "$posturl")" == "429" ]]; then
      retry_after="$(jq -r '.parameters.retry_after' <<< "$posturl")"
      if [[ $retry_after =~ ^[0-9]+$ ]]; then
        log_print ERR "Telegram rate limit exceeded. Retrying after $retry_after seconds..."
        sleep "$((retry_after + 1))"
        if posturl="$(extract_url "$posturl")"; then
          log_print INFO "Telegram notification successful for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]}): $posturl"
        else
          log_print ERR "Telegram notification failed also the 2nd time for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]})"
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
  pa_records["$idx":telegram:notified]="stale"
done
for idx in "${!link[@]}"; do
  if [[ "${link[idx]:0:4}" == "http" ]]; then
    pa_records["$idx":telegram:notified]=true
    pa_records["$idx":telegram:link]="${link[idx]}"
  elif [[ "${link[idx]}" == "private" ]]; then
    pa_records["$idx":telegram:notified]=true
    pa_records["$idx":telegram:link]=""
  else
    pa_records["$idx":telegram:notified]="error"
  fi
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Telegram notifications run completed."
