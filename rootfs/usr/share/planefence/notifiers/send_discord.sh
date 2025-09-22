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
  debug_print "[INFO] Discord notifications not enabled. Exiting."
  exit
fi
if [[ -z "$PF_DISCORD_WEBHOOKS" ]]; then
  debug_print "[FATAL] No Discord webhooks defined. Aborting."
  exit 1
fi

if [[ -z "$DISCORD_FEEDER_NAME" ]]; then
  debug_print "[FATAL] Discord Feeder Name not defined. Aborting."
  exit 1
fi

if [[ -f "/usr/share/planefence/notifiers/discord.template" ]]; then
  template="$(</usr/share/planefence/notifiers/discord.template)"
else
  debug_print "ERROR - No Discord template found at /usr/share/planefence/notifiers/discord.template. Aborting."
  exit 1
fi

READ_RECORDS

for (( idx=0; idx<=records[maxindex]; i++ )); do

  # Don't notify if the record is not complete or if notification has been sent already
  if ! chk_enabled "${records["$idx":complete]}" || chk:enabled "${records["$idx":discord:notified]}"; then continue; fi

  # re-read the template cleanly after each notification
  if [[ -f "/usr/share/planefence/notifiers/discord.template" ]]; then
    template="$(</usr/share/planefence/notifiers/discord.template)"
  else
    debug_print "ERROR - No Discord template found at /usr/share/planefence/notifiers/discord.template. Aborting."
    exit 1
  fi

  # Set title
  template="$(template_replace "##TITLE##" "${records["$idx":owner]} is overhead at ${records["$idx":nominatim]}}" "$template")"




  #shellcheck disable=SC2001
  if [[ "${*:2}" =~ .*tropoalert=.* ]]; then
    notify_tropo=true

  else
    unset notify_tropo
    template="${template//##TITLE##/VesselAlert}"
  fi

  if [[ -z "${DISCORD_WEBHOOKS}" ]]; then
    "${s6wrap[@]}" echo "[ERROR] DISCORD_WEBHOOKS not defined. Cannot send a Discord notification"
    exit 1
  fi

  if [[ -z "${DISCORD_NAME}" ]]; then
    "${s6wrap[@]}" echo "[ERROR] DISCORD_NAME not defined. Cannot send a Discord notification"
    exit 1
  fi

  readarray -td, webhooks <<<"${DISCORD_WEBHOOKS}"

  # First do some clean up
  if [[ -n "${VESSELS[$1:shipname]}" ]]; then
    VESSELS[$1:shipname]="$(sed -e ':a;s/^\(\([^"]*[,.]\?\|"[^",.]*"[,.]\?\)*"[^",.]*\)[,.]/\1 /;ta' -e 's|["'\''.]||g' -e 's|[^A-Z0-9,\.\-]\+| |g' -e 's|_,|,|g' <<< "${VESSELS[$1:shipname]}")"
  fi
  if [[ -n "${VESSELS[$1:destination]}" ]]; then
    VESSELS[$1:destination]="$(sed -e ':a;s/^\(\([^"]*[,.]\?\|"[^",.]*"[,.]\?\)*"[^",.]*\)[,.]/\1 /;ta' -e 's|["'\''.]||g' -e 's|[^A-Z0-9,\.\-\<\>]\+| |g' -e 's|_,|,|g' <<< "${VESSELS[$1:destination]}")"
  fi

  # If a screenshot exists, then make sure we'll include it:
  if [[ -f "${IMAGECACHE}/screenshots/$1.jpg" ]]; then
    SCREENSHOTCURL="-F file1=@${IMAGECACHE}/screenshots/$1.jpg"
    template="${template//##SCREENSHOTFILE##/$1.jpg}"
    template="${template//##SCRSHT--/}"
    template="${template//--SCRSHT##/}"
    "${s6wrap[@]}" echo "[INFO] Discord notification for $1 (${VESSELS[$1:shipname]}) - screenshot found"
  else
    SCREENSHOTCURL=""
    template="${template//##SCRSHT--*---SCRSHT##/}"
    "${s6wrap[@]}" echo "[INFO] Discord notification for $1 (${VESSELS[$1:shipname]}) - no screenshot found"
  fi

  # Add a Map URL if configured:
  [[ -n "${NOTIFICATION_MAPURL}" ]] && [[ "${NOTIFICATION_MAPURL:0:4}" == "http" ]] && NOTIFICATION_MAPURL="${NOTIFICATION_MAPURL}?mmsi=${VESSELS[$1:mmsi]}"
  [[ -n "${NOTIFICATION_MAPURL}" ]] && [[ "${NOTIFICATION_MAPURL:0:4}" != "http" ]] && NOTIFICATION_MAPURL="${AIS_URL}?mmsi=${VESSELS[$1:mmsi]}"
  if [[ -n "${NOTIFICATION_MAPURL}" ]]; then
    template="${template//##STNMAP##/${NOTIFICATION_MAPURL}}"
    template="${template//##SM--/}"
    template="${template//--SM##/}"
  else
    template="${template//##SM--*--SM##/}"
  fi

  # Now replace a bunch of parameters in the template:
  template="${template//##USER##/${DISCORD_NAME}}"

  {
    description=""
    if [[ -n "${notify_tropo}" ]]; then
      description+="TropoAlert - Long Distance Atmospheric Propagation: $(bc -l <<< "scale=1; ${VESSELS[$1:distance]} / 1") nm "
    else
      [[ -z "${VESSELS[$1:notification:last]}" ]] && description+="${NOTIF_TERM[NEW2]} " || description+="${NOTIF_TERM[AGAIN]} "
      [[ -n "${VESSELS[$1:shipname]}" ]] && description+="${NOTIF_TERM[SHIP]} ${VESSELS[$1:shipname]//_/ } " || description+="${NOTIF_TERM[SHIP]} $1 "
      [[ -n "${notify_distance}" ]] && description+="${NOTIF_TERM[ISMOVING]} " || description+="${NOTIF_TERM[ISSEENON]} "
    fi
    description+="$(date +"%R %Z")"
    template="${template//##DESCRIPTION##/${description}}"
  }

  [[ -n "${DISCORD_AVATAR_URL}" ]] && template="${template//##AVATAR##/${DISCORD_AVATAR_URL}}" || template="${template//\"avatar_url\": \"##AVATAR##\",/}"

  template="${template//##MMSI##/$1}"

  template="${template//##VESSELNAME##/${VESSELS[$1:shipname]//_/ }}"

  template="${template//##CALLSIGN##/${VESSELS[$1:callsign]}}"

  {
    type="${SHIPTYPE[${VESSELS[$1:shiptype]}]}"
    template="${template//##TYPE##/${type//#/}}"
  }

  {
    if chk_enabled "$USE_FRIENDLY_DESTINATION" && [[ -n "${VESSELS[$1:destination:friendly]}" ]]; then
      template="${template//##DESTINATION##/${VESSELS[$1:destination:friendly]//_/ }}"
    else
      template="${template//##DESTINATION##/${VESSELS[$1:destination]//_/ }}"
    fi
  }

  {
    flag="${COUNTRY[${VESSELS[$1:country]}]}"
    template="${template//##FLAG##/${flag}}"
  }

  template="${template//##COUNT##/${VESSELS[$1:count]}}"

  {
    printf -v signal -- "%.1f" "${VESSELS[$1:level]}"
    template="${template//##SIGNAL##/${signal}}"
  }

  {
    status="${SHIPSTATUS[${VESSELS[$1:status]}]}"
    status="${status#*#}";
    status="${status//_/ }";
    # [[ -z "${VESSELS[$1:notification:last]}" ]] && status+=" #New"
    # [[ "${notify_timing}" == "true" ]] && [[ -n "${VESSELS[$1:notification:last]}" ]] && status+=" #SeenBefore"
    # [[ -n "${notify_distance}" ]] && status+=" #OnTheMove"
    template="${template//##STATUS##/${status}}"
  }

  {
    if [[ -n "${notify_distance}" ]] && [[ -n "${VESSELS[$1:speed]}" ]]; then
      printf -v speed -- "%.1f kts -  ${NOTIF_TERM[DIST_SINCE_LAST]}" "${VESSELS[$1:speed]:-0}" "${notify_distance}"
    else
      printf -v speed -- "%.1f kts" "${VESSELS[$1:speed]:-0}"
    fi
    [[ -z "${VESSELS[$1:speed]}" ]] && speed=""
    template="${template//##SPEED##/${speed}}"
  }

  [[ "${VESSELS[$1:heading]}" != "null" ]] && template="${template//##HEADING##/${VESSELS[$1:heading]} deg}" || template="${template//##HEADING##/--}"

  {
    timestamp="$(date -d @$(( $(date +%s) - ${VESSELS[$1:last_signal]} )) +"%Y-%m-%dT%H:%M:%S%z")"
    template="${template//##TIMESTAMP##/${timestamp}}"
  }

  if [[ -n "${VESSELS[$1:lat]}" ]] && [[ -n "${VESSELS[$1:lon]}" ]] && [[ -n "$LAT" ]] && [[ -n "$LON" ]]; then
    distance="$(bc -l <<< "scale=1; $(distance "${VESSELS[$1:lat]}" "${VESSELS[$1:lon]}" "$LAT" "$LON") / 1")"
    template="${template//##DISTANCE##/${distance}}"
    template="${template//##HASDIST--/}"
    template="${template//--HASDIST##/}"
  else
    template="${template//##HASDIST--*--HASDIST##/}"
  fi

  # replace " " and "" by "--" to appease Discord's weird restriction on empty and almost empty strings
  template="${template//\" \"/\"--\"}"
  template="${template//\"\"/\"--\"}"

  # make the JSON object into a single line:
  template_org="$template"
  if ! template="$(jq -c . <<< "${template}")"; then 
    "${s6wrap[@]}" echo "[ERROR] JSON error for $1 (${VESSELS[$1:shipname]}). JSON is invalid: <!-->${template_org}<-->"
  fi

  # Now send the Discord notification:
  #shellcheck disable=SC2086
  for url in "${webhooks[@]}"; do
    url="${url//$'\n'/}"    # remove any stray newlines from the URL
    response="$(curl -sSL ${SCREENSHOTCURL} -F "payload_json=${template}" ${url} 2>&1)"

    # check if there was an error
    result="$(jq '.id' <<< "${response}" 2>/dev/null | xargs)"
    if [[ "${result}" != "null" ]]; then
      "${s6wrap[@]}" echo -n "[INFO] Discord post for $1 (${VESSELS[$1:shipname]}) generated successfully for webhook ending in ${url: -8}. Post ID is ${result//$'\n'/}."
      [[ -z "${VESSELS[$1:notification:last]}" ]] && echo -n " #NEW "
      #shellcheck disable=SC2154
      [[ -n "${notify_timing}" ]] && [[ -n "${VESSELS[$1:notification:last]}" ]] && echo -n " #OLD "
      [[ -n "${notify_distance}" ]] && echo -n " #ONTHEMOVE"
      echo ""
    else
      "${s6wrap[@]}" echo "[ERROR] Discord post error for $1 (${VESSELS[$1:shipname]}). Discord returned this error: ${response}"
      notification_error="true"
    fi
  done

  if [[ "$notification_error" != "true" ]]; then
    # Update the Assoc Array with the latest values:
    VESSELS[$1:notification:lat]="${VESSELS[$1:lat]}"
    VESSELS[$1:notification:lon]="${VESSELS[$1:lon]}"
    VESSELS[$1:notification:last]="$(date +%s)"
    VESSELS[$1:notification:discord]="true"

    source /usr/share/vesselalert/save_databases
  fi

done
