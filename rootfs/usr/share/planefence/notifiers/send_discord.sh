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
# This script sends a Discord notification

source /scripts/pf-common
source /usr/share/planefence/planefence.conf



# Load a bunch of stuff and determine if we should notify

if ! chk_enabled "$PF_DISCORD"; then
  log_print INFO "Discord notifications not enabled. Exiting."
  exit
fi
if [[ -z "$PF_DISCORD_WEBHOOKS" ]]; then
  log_print ERR "No Discord webhooks defined. Aborting."
  exit 1
fi

if [[ -z "$DISCORD_FEEDER_NAME" ]]; then
  log_print ERR "Discord Feeder Name not defined. Aborting."
  exit 1
fi

if [[ -f "/usr/share/planefence/notifiers/discord.template" ]]; then
  template="$(</usr/share/planefence/notifiers/discord.template)"
else
  log_print ERR "No Discord template found at /usr/share/planefence/notifiers/discord.template. Aborting."
  exit 1
fi

READ_RECORDS

for (( idx=0; idx<=records[maxindex]; i++ )); do

  # Don't notify if the record is not complete or if notification has been sent already
  if ! chk_enabled "${records["$idx":complete]}" || chk_enabled "${records["$idx":discord:notified]}"; then continue; fi

  # re-read the template cleanly after each notification
  if [[ -f "/usr/share/planefence/notifiers/discord.template" ]]; then
    template="$(</usr/share/planefence/notifiers/discord.template)"
  else
    log_print ERR "No Discord template found at /usr/share/planefence/notifiers/discord.template. Aborting."
    exit 1
  fi

  # Set strings:
  template="$(template_replace "||TITLE||" "${records["$idx":owner]} is overhead at ${records["$idx":nominatim]}}" "$template")"
  template="$(template_replace "||USER||" "$DISCORD_FEEDER_NAME" "$template")"
  template="$(template_replace "||DESCRIPTION||" "[Track on $TRACKSERVICE](${records["$idx":map:link]})" "$template")"
  template="$(template_replace "||CALLSIGN||" "${records["$idx:callsign"]}" "$template")"
  template="$(template_replace "||ICAO||" "${records["$idx:icao"]}" "$template")"
  template="$(template_replace "||TYPE||" "${records["$idx:type"]}" "$template")"
  template="$(template_replace "||DISTANCE||" "${records["$idx:distance"]} $DISTUNIT (${records["$idx":angle]}°)" "$template")"
  template="$(template_replace "||ALTITUDE||" "${records["$idx:altitude"]} $ALTUNIT" "$template")"
  template="$(template_replace "||GROUNDSPEED||" "${records["$idx:groundspeed"]} $SPEEDUNIT" "$template")"
  template="$(template_replace "||TAIL||" "${records["$idx:tail"]}" "$template")"
  template="$(template_replace "||ROUTE||" "${records["$idx:route"]}" "$template")"
  template="$(template_replace "||TRACK||" "${records["$idx:track"]}°" "$template")"
  template="$(template_replace "||TIMESTAMP||" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$template")"
  if [[ -n "${DISCORD_AVATAR_URL}" ]]; then
    template="$(template_replace "!!AVATAR!!" "${DISCORD_AVATAR_URL}" "$template")"
  else
    template="${template_replace '"avatar_url": "||AVATAR||",' "" "$template"}"
  fi

  #Do a few more complex replacements:
  if chk_enabled "${records[HASNOISE]}"; then
    template="$(template_replace "||NOISE--" "" "$template")"
    template="$(template_replace "--NOISE||" "" "$template")"
    template="$(template_replace "||LOUDNESS||" "${records["$idx:noise"]} dB" "$template")"
  else
    template="$(sed -z 's/||NOISE--.*--NOISE||//g' <<< "$template")"
  fi
  case "$DISCORDMEDIA" in
    photo)
      image="${records["$idx":image:link]}"
      thumb=""
      curlfile=""
      ;;
    "photo+screenshot")
      image="${records["$idx":image:link]}"
      thumb="attachment://$(basename "${records["$idx":screenshot:file]}")"
      curlfile="-F file1=@${records["$idx":screenshot:file]}"
      ;;
    "screenshot+photo")
      thumb="${records["$idx":image:thumblink]}"
      image="attachment://$(basename "${records["$idx":screenshot:file]}")"
      curlfile="-F file1=@${records["$idx":screenshot:file]}"    
      ;;
    screenshot)
      image="attachment://$(basename "${records["$idx":screenshot:file]}")"
      thumb=""
      curlfile="-F file1=@${records["$idx":screenshot:file]}"
      ;;
    "")
      image=""
      thumb=""
      curlfile=""
  esac

  if [[ -z "${image}${thumb}" ]]; then
    template="$(sed -z 's/||IMAGE--.*--IMAGE||//g' <<< "$template")"
    template="$(sed -z 's/||THUMBNAIL--.*--THUMBNAIL||//g' <<< "$template")"
  else
    template="$(template_replace "||IMAGE--" "" "$template")"
    template="$(template_replace "--IMAGE||" "" "$template")"
    template="$(template_replace "||IMAGE||" "$image" "$template")"
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
    log_print ERR "JSON error for $1 (${VESSELS[$1:shipname]}). JSON is invalid: <!-->${template_org}<-->"
  fi

  # Now send the notification to Discord
  readarray -td, webhooks <<<"${PF_DISCORD_WEBHOOKS}"

  #shellcheck disable=SC2086
  for url in "${webhooks[@]}"; do
    url="${url//$'\n'/}"    # remove any stray newlines from the URL
    response="$(curl -sSL ${curlfile} -F "payload_json=${template}" ${url} 2>&1)"

    # check if there was an error
    result="$(jq '.id' <<< "${response}" 2>/dev/null | xargs)"
    if [[ "${result}" != "null" ]]; then
      log_print INFO "Discord post for ${records["$idx":tail]}) generated successfully for webhook ending in ${url: -8}. Post ID is ${result//$'\n'/}."
      records["$idx":discord:notified]=true
      records[HASNOTIFS]=true
    else
      log_print WARNING "Discord post error for ${records["$idx":tail]}). Discord returned this error: ${response}"
      records["$idx":discord:notified]=false
    fi
  done
done

# Save the records again
debug_print "Saving records after Discord notifications"
WRITE_RECORDS
log_print INFO "Discord notifications run completed."