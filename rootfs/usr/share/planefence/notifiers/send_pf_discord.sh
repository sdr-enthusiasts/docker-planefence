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
source /usr/share/planefence/planefence.conf

# shellcheck disable=SC2034
DEBUG=false

declare -a INDEX STALE link delivery_errors link

# Load a bunch of stuff and determine if we should notify

if ! chk_enabled "$PF_DISCORD"; then
  log_print DEBUG "Discord notifications not enabled."
  exit 0
fi

log_print DEBUG "Hello. Starting Discord notification run"

if [[ -z "$PF_DISCORD_WEBHOOKS" ]]; then
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
#DISCORD_FEEDER_NAME="${DISCORD_FEEDER_NAME//[^[:ascii:]]/}"
DISCORD_FEEDER_NAME="${DISCORD_FEEDER_NAME//\\/}"
if [[ "$DISCORD_FEEDER_NAME" == \[*\]\(*\) ]]; then
  DISCORD_FEEDER_NAME=${DISCORD_FEEDER_NAME#\[}
  DISCORD_FEEDER_NAME=${DISCORD_FEEDER_NAME%%]*}
fi

if [[ -f "/usr/share/planefence/notifiers/discord.pf.template" ]]; then
  template="$(</usr/share/planefence/notifiers/discord.pf.template)"
else
  log_print ERR "No Discord template found at /usr/share/planefence/notifiers/discord.pf.template. Aborting."
  exit 1
fi

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  screenshots=0
fi

VERSION="$(awk -F'=' '/^\s*VERSION/ {gsub(/^["'"'"']|["'"'"']$/, "", $2); print $2}' /usr/share/planefence/planefence.conf)"

log_print DEBUG "Reading records for Discord notification"
log_print DEBUG "Reading records for Discord notification"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Discord notification and stale records"
log_print DEBUG "Getting indices of records ready for Discord notification and stale records"
build_index_and_stale INDEX STALE discord

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

template_clean="$(</usr/share/planefence/notifiers/discord.pf.template)"

color="$(convert_color "${PF_DISCORD_COLOR:-yellow}")"

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Discord notification for ${records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # recolor to red if squawk in 7500|7600|7700:
  emergency=false
  case "${records["$idx":squawk:value]}" in
    7500|7600|7700)
      color="$(convert_color red)"
      emergency=true
    ;;
  esac

  # Set strings:
  template="$(template_replace "||TITLE||" "${records["$idx":owner]:-${records["$idx":callsign]}} (${records["$idx":tail]}) is at ${records["$idx":altitude:value]} $ALTUNIT above ${records["$idx":nominatim]}" "$template")"
  template="$(template_replace "||USER||" "$DISCORD_FEEDER_NAME" "$template")"
  template="$(template_replace "||DESCRIPTION||" "[Track on $(extract_base "${records["$idx":link:map]}")](${records["$idx":link:map]})" "$template")"
  template="$(template_replace "||COLOR||" "$color" "$template")"
  template="$(template_replace "||CALLSIGN||" "${records["$idx:callsign"]}" "$template")"
  template="$(template_replace "||ICAO||" "${records["$idx:icao"]}" "$template")"
  template="$(template_replace "||TYPE||" "${records["$idx:type"]}" "$template")"
  template="$(template_replace "||DISTANCE||" "${records["$idx:distance:value"]} $DISTUNIT (${records["$idx":angle:value]}°)" "$template")"
  template="$(template_replace "||ALTITUDE||" "${records["$idx:altitude:value"]} $ALTUNIT" "$template")"
  template="$(template_replace "||GROUNDSPEED||" "${records["$idx:groundspeed:value"]} $SPEEDUNIT" "$template")"
  template="$(template_replace "||TAIL||" "${records["$idx:tail"]}" "$template")"
  template="$(template_replace "||ROUTE||" "${records["$idx:route"]:-n/a}" "$template")"
  template="$(template_replace "||TRACK||" "${records["$idx:track:value"]}°" "$template")"
  template="$(template_replace "||TIMESTAMP||" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$template")"
  template="$(template_replace "||YEAR||" "$(date -u +'%Y')" "$template")"
  template="$(template_replace "||VERSION||" "$VERSION" "$template")"

  if [[ -n "${DISCORD_AVATAR_URL}" ]]; then
    template="$(template_replace "||AVATAR||" "${DISCORD_AVATAR_URL}" "$template")"
  else
    template="$(template_replace '"avatar_url": "||AVATAR||",' "" "$template")"
  fi

  # Do a few more complex replacements:
  if [[ -n ${records["$idx":sound:loudness]} ]]; then
    template="$(template_replace "||NOISE--" "" "$template")"
    template="$(template_replace "--NOISE||" "" "$template")"
    template="$(template_replace "||LOUDNESS||" "${records["$idx":sound:loudness]} dB" "$template")"
  else
    template="$(sed -z 's/||NOISE--.*--NOISE||//g' <<< "$template")"
  fi

  if chk_enabled "$emergency"; then
    template="$(template_replace "||EMERGENCY||" "Emergency: Squawk ${records["$idx":squawk:value]} - " "$template")"
  else
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi
  if [[ -n "${records["$idx":squawk:value]}" ]]; then
    template="$(template_replace "||SQUAWK--" "" "$template")"
    template="$(template_replace "--SQUAWK||" "" "$template")"
    template="$(template_replace "||SQUAWKSTRING||" "${records["$idx":squawk:value]}${records["$idx":squawk:description]:+ (}${records["$idx":squawk:description]}${records["$idx":squawk:description]:+)}" "$template")"
  else
    template="$(sed -z 's/||SQUAWK--.*--SQUAWK||//g' <<< "$template")"
  fi

  # Handle media attachments
  image=""; thumb=""; curlfile=""
  log_print DEBUG "DISCORD_MEDIA is set to '$DISCORD_MEDIA'"
  case "$DISCORD_MEDIA" in
    "photo")
      image="${records["$idx":image:thumblink]}"
      ;;
    "photo+screenshot")
      image="${records["$idx":image:thumblink]}"
      if chk_enabled $screenshots && [[ -f "${records["$idx":screenshot:file]}" ]]; then
          thumb="attachment://$(basename "${records["$idx":screenshot:file]}")"
          curlfile="-F file1=@${records["$idx":screenshot:file]}"
      fi
      ;;
    "screenshot+photo")
      thumb="${records["$idx":image:thumblink]}"
      if chk_enabled $screenshots && [[ -f "${records["$idx":screenshot:file]}" ]]; then
        image="attachment://$(basename "${records["$idx":screenshot:file]}")"
        curlfile="-F file1=@${records["$idx":screenshot:file]}"
      fi
      ;;
    "screenshot")
      if chk_enabled $screenshots && [[ -f "${records["$idx":screenshot:file]}" ]]; then
        image="attachment://$(basename "${records["$idx":screenshot:file]}")"
        curlfile="-F file1=@${records["$idx":screenshot:file]}"
      fi
      ;;
  esac

  if [[ -z "${image}" ]]; then
    log_print DEBUG "No image available for ${records["$idx":tail]}, removing image section from template"
    template="$(sed -z 's/||IMAGE--.*--IMAGE||//g' <<< "$template")"
  else
    log_print DEBUG "Image available for ${records["$idx":tail]}, adding to template"
    template="$(template_replace "||IMAGE--" "" "$template")"
    template="$(template_replace "--IMAGE||" "" "$template")"
    template="$(template_replace "||IMAGE||" "$image" "$template")"
  fi
  if [[ -z "${thumb}" ]]; then
    log_print DEBUG "No thumbnail available for ${records["$idx":tail]}, removing thumbnail section from template"
    template="$(sed -z 's/||THUMBNAIL--.*--THUMBNAIL||//g' <<< "$template")"
  else
    log_print DEBUG "Thumbnail available for ${records["$idx":tail]}, adding to template"
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
    log_print ERR "JSON error for ${records["$idx":tail]}. JSON is invalid: <!-->${template_org}<-->"
  fi

  # Now send the notification to Discord
  readarray -td, webhooks <<<"${PF_DISCORD_WEBHOOKS}"

  #shellcheck disable=SC2086
  for url in "${webhooks[@]}"; do
    url="${url//$'\n'/}"    # remove any stray newlines from the URL
    response="$(curl -sSL ${curlfile} -F "payload_json=${template}" ${url}?wait=true)"
    # check if there was an error
    if channel_id=$(jq -r '.channel_id' <<<"$response") && message_id=$(jq -r '.id' <<<"$response"); then
      discord_link="https://discord.com/channels/@me/${channel_id}/${message_id}"
      log_print INFO "Discord notification successful at Webhook ending in ${url: -8} for #$idx ${records["$idx":tail]} (${records["$idx":icao]}): ${discord_link}"
      link[idx]+="${link[idx]:+,}$discord_link"
    else
      log_print WARNING "Discord notification failed at Webhook ending in ${url: -8} for #$idx ${records["$idx":tail]} (${records["$idx":icao]}). Discord returned this error: ${response}"
      delivery_errors[idx]=true
    fi
  done
done

# Save the records again
log_print DEBUG "Updating records after Discord notifications"

LOCK_RECORDS
READ_RECORDS ignore-lock

if [[ ${#link[@]} -gt 0 || ${#delivery_errors[@]} -gt 0 ]]; then records[HASNOTIFS]=true; fi

for idx in "${STALE[@]}"; do
  records["$idx":discord:notified]="stale"
done

for idx in "${!delivery_errors[@]}"; do
  records["$idx":discord:notified]="error"
done

# For the ones that were successful, even if they had some errors on other webhooks, mark as notified
for idx in "${!link[@]}"; do
  records["$idx":discord:notified]=true
  records["$idx":discord:link]="${link[idx]}"
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Discord notifications run completed."
