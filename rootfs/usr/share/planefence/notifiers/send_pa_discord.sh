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
# This script sends a Discord notification
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/persist/planefence.config

# shellcheck disable=SC2034
DEBUG=false

declare -a INDEX STALE link delivery_errors link

# Load a bunch of stuff and determine if we should notify

if ! chk_enabled "$PA_DISCORD"; then
  log_print DEBUG "Discord notifications not enabled."
  exit 0
fi

log_print DEBUG "Hello. Starting Discord notification run"

if [[ -z "$PA_DISCORD_WEBHOOKS" ]]; then
  log_print ERR "No Discord webhooks defined. Aborting."
  exit 1
fi

if [[ -z "$DISCORD_FEEDER_NAME" ]]; then
  log_print ERR "Discord Feeder Name not defined. Aborting."
  exit 1
fi

export LC_ALL=C
#DISCORD_FEEDER_NAME_CLEAN="${DISCORD_FEEDER_NAME//[^[:ascii:]]/}"
# strip feeder name from any non ASCII and URL
# DISCORD_FEEDER_NAME="${DISCORD_FEEDER_NAME//[^[:ascii:]]/}"
DISCORD_FEEDER_NAME="${DISCORD_FEEDER_NAME//\\/}"
if [[ "$DISCORD_FEEDER_NAME" == \[*\]\(*\) ]]; then
  DISCORD_FEEDER_NAME=${DISCORD_FEEDER_NAME#\[}
  DISCORD_FEEDER_NAME=${DISCORD_FEEDER_NAME%%]*}
fi


if [[ -f "/usr/share/planefence/notifiers/discord.pa.template" ]]; then
  template="$(</usr/share/planefence/notifiers/discord.pa.template)"
else
  log_print ERR "No Discord template found at /usr/share/planefence/notifiers/discord.pa.template. Aborting."
  exit 1
fi

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  screenshots=0
fi

VERSION="$(GET_PARAM pf VERSION)"
log_print DEBUG "Reading records for Discord notification"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Discord notification and stale records"
build_index_and_stale INDEX STALE discord pa

if (( ${#INDEX[@]} )); then
  log_print DEBUG "Records ready for Discord notification: ${INDEX[*]}"
else
  log_print DEBUG "No records ready for Discord notification"
fi
if (( ${#STALE[@]} )); then
  log_print DEBUG "Stale records (no notification will be sent): ${STALE[*]}"
else
  log_print DEBUG "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print DEBUG "No records eligible for Discord notification."
  exit 0
fi

template_clean="$(</usr/share/planefence/notifiers/discord.pa.template)"

color="$(convert_color "${PA_DISCORD_COLOR:-yellow}")"

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Discord notification for ${pa_records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # recolor to red if squawk in 7500|7600|7700:
  emergency=false
  case "${pa_records["$idx":squawk:value]}" in
    7500|7600|7700)
      color="$(convert_color red)"
      emergency=true
    ;;
  esac

  # Set strings:
  template="$(template_replace "||TITLE||" "Plane-Alert: ${pa_records["$idx":owner]:-${pa_records["$idx":callsign]}} (${pa_records["$idx":tail]}) first seen at ${pa_records["$idx":altitude:value]} $ALTUNIT above ${pa_records["$idx":nominatim]}" "$template")"
  template="$(template_replace "||USER||" "$DISCORD_FEEDER_NAME" "$template")"
  template="$(template_replace "||DESCRIPTION||" "[Track on $(extract_base "${pa_records["$idx":link:map]}")](${pa_records["$idx":link:map]})" "$template")"
  template="$(template_replace "||COLOR||" "$color" "$template")"
  template="$(template_replace "||CALLSIGN||" "${pa_records["$idx:callsign"]}" "$template")"
  template="$(template_replace "||ICAO||" "${pa_records["$idx:icao"]}" "$template")"
  template="$(template_replace "||TYPE||" "${pa_records["$idx:type"]}" "$template")"
  template="$(template_replace "||DISTANCE||" "${pa_records["$idx:distance:value"]} $DISTUNIT (${pa_records["$idx":angle:value]}°)" "$template")"
  template="$(template_replace "||ALTITUDE||" "${pa_records["$idx:altitude:value"]} $ALTUNIT" "$template")"
  template="$(template_replace "||GROUNDSPEED||" "${pa_records["$idx:groundspeed:value"]} $SPEEDUNIT" "$template")"
  template="$(template_replace "||TAIL||" "${pa_records["$idx:tail"]}" "$template")"
  template="$(template_replace "||TRACK||" "${pa_records["$idx:track:value"]}°" "$template")"
  template="$(template_replace "||TIMESTAMP||" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$template")"
  template="$(template_replace "||YEAR||" "$(date -u +'%Y')" "$template")"
  template="$(template_replace "||VERSION||" "$VERSION" "$template")" 
  
  if [[ -n "${DISCORD_AVATAR_URL}" ]]; then
    template="$(template_replace "||AVATAR||" "${DISCORD_AVATAR_URL}" "$template")"
  else
    template="$(template_replace '"avatar_url": "||AVATAR||",' "" "$template")"
  fi

  #Do a few more complex replacements:
  if [[ -n ${pa_records["$idx":sound:loudness]} ]]; then
    template="$(template_replace "||NOISE--" "" "$template")"
    template="$(template_replace "--NOISE||" "" "$template")"
    template="$(template_replace "||LOUDNESS||" "${pa_records["$idx":sound:loudness]} dB" "$template")"
  else
    template="$(sed -z 's/||NOISE--.*--NOISE||//g' <<< "$template")"
  fi

  if chk_enabled "$emergency"; then
    template="$(template_replace "||EMERGENCY||" "Emergency: Squawk ${pa_records["$idx":squawk:value]} - " "$template")"
  else
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi

  if [[ -n "${pa_records["$idx":squawk:value]}" ]]; then
    template="$(template_replace "||SQUAWK--" "" "$template")"
    template="$(template_replace "--SQUAWK||" "" "$template")"
    template="$(template_replace "||SQUAWKSTRING||" "${pa_records["$idx":squawk:value]}${pa_records["$idx":squawk:description]:+ (}${pa_records["$idx":squawk:description]}${pa_records["$idx":squawk:description]:+)}" "$template")"
  else
    template="$(sed -z 's/||SQUAWK--.*--SQUAWK||//g' <<< "$template")"
  fi

  if [[ -n "${pa_records["$idx":route]}" && "${pa_records["$idx":route]}" != "n/a" ]]; then
    template="$(template_replace "||ROUTE--" "" "$template")"
    template="$(template_replace "--ROUTE||" "" "$template")"
    template="$(template_replace "||ROUTE||" "${pa_records["$idx":route]}" "$template")"
  else
    template="$(sed -z 's/||ROUTE--.*--ROUTE||//g' <<< "$template")"
  fi    

  if [[ -n "${pa_records["$idx":db:category]}" ]]; then
    template="$(template_replace "||CATEGORY--" "" "$template")"
    template="$(template_replace "--CATEGORY||" "" "$template")"
    template="$(template_replace "||CATEGORY||" "${pa_records["$idx":db:category]}" "$template")"
  else
    template="$(sed -z 's/||CATEGORY--.*--CATEGORY||//g' <<< "$template")"
  fi

  if [[ -n "${pa_records["$idx":db:tag1]}" ]]; then
    template="$(template_replace "||TAG1--" "" "$template")"
    template="$(template_replace "--TAG1||" "" "$template")"
    template="$(template_replace "||TAG1||" "${pa_records["$idx":db:tag1]}" "$template")"
  else
    template="$(sed -z 's/||TAG1--.*--TAG1||//g' <<< "$template")"
  fi
  if [[ -n "${pa_records["$idx":db:tag2]}" ]]; then
    template="$(template_replace "||TAG2--" "" "$template")"
    template="$(template_replace "--TAG2||" "" "$template")"
    template="$(template_replace "||TAG2||" "${pa_records["$idx":db:tag2]}" "$template")"
  else
    template="$(sed -z 's/||TAG2--.*--TAG2||//g' <<< "$template")"
  fi
  if [[ -n "${pa_records["$idx":db:tag3]}" ]]; then
    template="$(template_replace "||TAG3--" "" "$template")"
    template="$(template_replace "--TAG3||" "" "$template")"
    template="$(template_replace "||TAG3||" "${pa_records["$idx":db:tag3]}" "$template")"
  else
    template="$(sed -z 's/||TAG3--.*--TAG3||//g' <<< "$template")"
  fi
  if [[ -n "${pa_records["$idx":db:link]}" ]]; then
    template="$(template_replace "||LINK--" "" "$template")"
    template="$(template_replace "--LINK||" "" "$template")"
    template="$(template_replace "||LINKURL||" "${pa_records["$idx":db:link]}" "$template")"
    template="$(template_replace "||LINKTITLE||" "$(extract_base "${pa_records["$idx":db:link]}")" "$template")"
  else
    template="$(sed -z 's/||LINK--.*--LINK||//g' <<< "$template")"
  fi

  if [[ -n "${pa_records["$idx":time:firstseen]}" ]]; then
    template="$(template_replace "||FIRSTSEEN--" "" "$template")"
    template="$(template_replace "--FIRSTSEEN||" "" "$template")"
    template="$(template_replace "||FIRSTSEEN||" "$(date -d "@${pa_records["$idx:time:firstseen"]}" +'%H:%M:%S %Z')" "$template")"
  else
    template="$(sed -z 's/||FIRSTSEEN--.*--FIRSTSEEN||//g' <<< "$template")"
  fi

  #################################
  image=""; thumb=""; curlfile=""
  log_print DEBUG "DISCORD_MEDIA is set to '$DISCORD_MEDIA'"
  case "$DISCORD_MEDIA" in
    "photo")
      image="${pa_records["$idx":image:thumblink]}"
      ;;
    "photo+screenshot")
      image="${pa_records["$idx":image:thumblink]}"
      if chk_enabled $screenshots && [[ -f "${pa_records["$idx":screenshot:file]}" ]]; then
          thumb="attachment://$(basename "${pa_records["$idx":screenshot:file]}")"
          curlfile="-F file1=@${pa_records["$idx":screenshot:file]}"
      fi
      ;;
    "screenshot+photo")
      thumb="${pa_records["$idx":image:thumblink]}"
      if chk_enabled $screenshots && [[ -f "${pa_records["$idx":screenshot:file]}" ]]; then
        image="attachment://$(basename "${pa_records["$idx":screenshot:file]}")"
        curlfile="-F file1=@${pa_records["$idx":screenshot:file]}"
      fi
      ;;
    "screenshot")
      if chk_enabled $screenshots && [[ -f "${pa_records["$idx":screenshot:file]}" ]]; then
        image="attachment://$(basename "${pa_records["$idx":screenshot:file]}")"
        curlfile="-F file1=@${pa_records["$idx":screenshot:file]}"
      fi
      ;;
  esac

  if [[ -z "${image}" ]]; then
    log_print DEBUG "No image available for ${pa_records["$idx":tail]}, removing image section from template"
    template="$(sed -z 's/||IMAGE--.*--IMAGE||//g' <<< "$template")"
  else
    log_print DEBUG "Image available for ${pa_records["$idx":tail]}, adding to template"
    template="$(template_replace "||IMAGE--" "" "$template")"
    template="$(template_replace "--IMAGE||" "" "$template")"
    template="$(template_replace "||IMAGE||" "$image" "$template")"
  fi
  if [[ -z "${thumb}" ]]; then
    log_print DEBUG "No thumbnail available for ${pa_records["$idx":tail]}, removing thumbnail section from template"
    template="$(sed -z 's/||THUMBNAIL--.*--THUMBNAIL||//g' <<< "$template")"
  else
    log_print DEBUG "Thumbnail available for ${pa_records["$idx":tail]}, adding to template"
    template="$(template_replace "||THUMBNAIL--" "" "$template")"
    template="$(template_replace "--THUMBNAIL||" "" "$template")"
    template="$(template_replace "||THUMBNAIL||" "$thumb" "$template")"
  fi

  # replace " " and "" by "--" to appease Discord's weird restriction on empty and almost empty strings
  template="${template//\" \"/\"--\"}"
  template="${template//\"\"/\"--\"}"

  # make the JSON object into a single line:
  template_org="$template"
  if ! template="$(jq -c . <<< "${template}")"; then
    log_print ERR "JSON error for ${pa_records["$idx":tail]}. JSON is invalid: <!-->${template_org}<-->"
  fi

  # Now send the notification to Discord
  readarray -td, webhooks <<<"${PA_DISCORD_WEBHOOKS}"

  #shellcheck disable=SC2086
  for url in "${webhooks[@]}"; do
    url="${url//$'\n'/}"    # remove any stray newlines from the URL
    response="$(curl -sSL ${curlfile} -F "payload_json=${template}" ${url}?wait=true)"
    # check if there was an error
    if channel_id=$(jq -r '.channel_id' <<<"$response") && message_id=$(jq -r '.id' <<<"$response"); then
      discord_link="https://discord.com/channels/@me/${channel_id}/${message_id}"
      log_print INFO "Discord notification successful at Webhook ending in ${url: -8} for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]}): ${discord_link}"
      link[idx]+="${link[idx]:+,}$discord_link"
    else
      log_print WARNING "Discord notification failed at Webhook ending in ${url: -8} for #$idx ${pa_records["$idx":tail]} (${pa_records["$idx":icao]}). Discord returned this error: ${response}"
      delivery_errors[idx]=true
    fi
  done
done

# Save the records again
log_print DEBUG "Updating records after Discord notifications"

LOCK_RECORDS
READ_RECORDS ignore-lock

if [[ ${#link[@]} -gt 0 || ${#delivery_errors[@]} -gt 0 ]]; then pa_records[HASNOTIFS]=true; fi

for idx in "${STALE[@]}"; do
  pa_records["$idx":discord:notified]="stale"
done

for idx in "${!delivery_errors[@]}"; do
  pa_records["$idx":discord:notified]="error"
done

# For the ones that were successful, even if they had some errors on other webhooks, mark as notified
for idx in "${!link[@]}"; do
  pa_records["$idx":discord:notified]=true
  pa_records["$idx":discord:link]="${link[idx]}"
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Discord notifications run completed."
