#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1091,SC2154
# planefence-rss.sh
# A script to generate RSS feeds from Planefence CSV files
#
# Usage: ./planefence-rss.sh 
#
# This script is distributed as part of the Planefence package and is dependent
# on that package for its execution.
#
# Based on a script provided by @randomrobbie - https://github.com/sdr-enthusiasts/docker-planefence/issues/211
# Copyright 2024-2025 @randomrobbie, Ramon F. Kolb (kx1t), and contributors - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#

# Set paths - use the same as planefence.sh
source "/usr/share/planefence/planefence.conf"

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
HTMLDIR=/tmp
OUTFILEDIR=/tmp
set -eo pipefail
DEBUG=true

# Get today's date in yymmdd format
TODAY=$(date --date="today" '+%y%m%d')

# Site configuration - you can modify these
SITE_TITLE="Planefence Aircraft Detections"
SITE_DESC="Recent aircraft detected within range of our ADS-B receiver"
SITE_LINK="${RSS_SITELINK}"  # Replace with your actual URL
SITE_IMAGE="${RSS_FAVICONLINK}"  # Optional site image

#  If there is a site link, make sure it ends with a /
if [[ -n "$SITE_LINK" ]] && [[ "${SITE_LINK: -1}" != "/" ]]; then SITE_LINK="${SITE_LINK}/"; fi

# define the RECORDSFILE with the records assoc array
RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"
source /scripts/common

# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------

debug_print() {
    local currenttime
    if [[ -z "$execstarttime" ]]; then
      execstarttime="$(date +%s.%3N)"
      execlaststeptime="$execstarttime"
    fi
    currenttime="$(date +%s.%3N)"
    if chk_enabled "$DEBUG"; then 
      "${s6wrap[@]}" printf "[DEBUG] %s (%s secs, total time elapsed %s secs)\n" "$1" "$(bc -l <<< "$currenttime - $execlaststeptime")" "$(bc -l <<< "$currenttime - $execstarttime")" >&2
    fi
    execlaststeptime="$currenttime"
}

# Function to encode special characters for XML
xml_encode() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

generate_mqtt() {
  # Generate a MQTT notification
			if [[ -n "$MQTT_URL" ]]; then
				unset msg_array
				declare -A msg_array

				msg_array[icao]="${RECORD[0]}"
				msg_array[flight]="${RECORD[1]#@}"
				msg_array[operator]="${AIRLINE//[\'\"]/ }"
				msg_array[operator]="${msg_array[operator]//[&]/ and }"
				msg_array[operator]="$(echo "${msg_array[operator]//#/}" | xargs)"
				if [[ -n "$ROUTE" ]]; then
					if [[ "${ROUTE:0:4}" == "org:" ]]; then
						msg_array[origin]="${ROUTE:6}"
					elif [[ "${ROUTE:0:5}" == "dest:" ]]; then
						msg_array[destination]="${ROUTE:7}"
					else
						msg_array[origin]="${ROUTE:1:3}"
						msg_array[destination]="${ROUTE: -3}"
					fi
				fi
				msg_array[first_seen]="$(date -d "${RECORD[2]}" "+${MQTT_DATETIME_FORMAT:-%s}")"
				msg_array[last_seen]="$(date -d "${RECORD[3]}" "+${MQTT_DATETIME_FORMAT:-%s}")"
				msg_array[min_alt]="${RECORD[4]} $ALTUNIT $ALTPARAM"
        msg_array[timezone]="$(date +%Z)"
				msg_array[min_dist]="${RECORD[5]} $DISTUNIT"
				msg_array[link]="${RECORD[6]//globe.adsbexchange.com/$TRACKSERVICE}"
				if ((RECORD[7] < 0)); then
					msg_array[peak_audio]="${RECORD[7]} dBFS"
					msg_array[loudness]="$((RECORD[7] - RECORD[11])) dB"
				fi
				if [[ -f "/usr/share/planefence/persist/planepix/cache/${msg_array[icao]}.thumb.link" ]]; then
					msg_array[thumbnail]="$(<"/usr/share/planefence/persist/planepix/cache/${msg_array[icao]}.thumb.link")"
				fi
				if [[ -f "/usr/share/planefence/persist/planepix/cache/${msg_array[icao]}.link" ]]; then
					msg_array[planespotters_link]="$(<"/usr/share/planefence/persist/planepix/cache/${msg_array[icao]}.link")"
				fi

				# convert $msg_array[@] into a JSON object; if (PF_)MQTT_FIELDS is defined, then only use those fields:
				MQTT_JSON="$(for i in "${!msg_array[@]}"; do 
										 	if [[ -z "$MQTT_FIELDS" ]] || [[ $MQTT_FIELDS == *$i* ]]; then 
												printf '{"%s":"%s"}\n' "$i" "${msg_array[$i]}"
											fi 
										 done | jq -sc add)"

				# prep the MQTT host, port, etc
				unset MQTT_TOPIC MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_HOST
				MQTT_HOST="${MQTT_URL##*:\/\/}"                                                     # strip protocol header (mqtt:// etc)
				while [[ "${MQTT_HOST: -1}" == "/" ]]; do MQTT_HOST="${MQTT_HOST:0:-1}"; done       # remove any trailing / from the HOST
				if [[ $MQTT_HOST == *"/"* ]]; then MQTT_TOPIC="${MQTT_TOPIC:-${MQTT_HOST#*\/}}"; fi # if there's no explicitly defined topic, then use the URL's topic if that exists
				MQTT_TOPIC="${MQTT_TOPIC:-$(hostname)/planefence}"                                  # add default topic if there is still none defined
				MQTT_HOST="${MQTT_HOST%%/*}"                                                        # remove everything from the first / onward

				if [[ $MQTT_HOST == *"@"* ]]; then
					MQTT_USERNAME="${MQTT_USERNAME:-${MQTT_HOST%@*}}"
					MQTT_PASSWORD="${MQTT_PASSWORD:-${MQTT_USERNAME#*:}}"
					MQTT_USERNAME="${MQTT_USERNAME%:*}"
					MQTT_HOST="${MQTT_HOST#*@}"
				fi
				if [[ $MQTT_HOST == *":"* ]]; then MQTT_PORT="${MQTT_PORT:-${MQTT_HOST#*:}}"; fi
				MQTT_HOST="${MQTT_HOST%:*}" # finally strip the host so there's only a hostname or ip address

				# log the message we are going to send:
				"${s6wrap[@]}" echo "Attempting to send a MQTT notification:"
				"${s6wrap[@]}" echo "MQTT Host: $MQTT_HOST"
				"${s6wrap[@]}" echo "MQTT Port: ${MQTT_PORT:-1883}"
				"${s6wrap[@]}" echo "MQTT Topic: $MQTT_TOPIC"
				"${s6wrap[@]}" echo "MQTT Client ID: ${MQTT_CLIENT_ID:-$(hostname)}"
				if [[ -n "$MQTT_USERNAME" ]]; then "${s6wrap[@]}" echo "MQTT Username: $MQTT_USERNAME"; fi
				if [[ -n "$MQTT_PASSWORD" ]]; then "${s6wrap[@]}" echo "MQTT Password: $MQTT_PASSWORD"; fi
				if [[ -n "$MQTT_QOS" ]]; then "${s6wrap[@]}" echo "MQTT QOS: $MQTT_QOS"; fi
				"${s6wrap[@]}" echo "MQTT Payload JSON Object: $MQTT_JSON"

				# send the MQTT message:
				mqtt_string=(--broker "$MQTT_HOST")
				if [[ -n "$MQTT_PORT" ]]; then mqtt_string+=(--port "$MQTT_PORT"); fi
				mqtt_string+=(--topic \""$MQTT_TOPIC"\")
				if [[ -n "$MQTT_QOS" ]]; then mqtt_string+=(--qos "$MQTT_QOS"); fi
				mqtt_string+=(--client_id \""${MQTT_CLIENT_ID:-$(hostname)}"\")
				if [[ -n "$MQTT_USERNAME" ]]; then mqtt_string+=(--username "$MQTT_USERNAME"); fi
				if [[ -n "$MQTT_PASSWORD" ]]; then mqtt_string+=(--password "$MQTT_PASSWORD"); fi
				mqtt_string+=(--message "'${MQTT_JSON}'")

				# shellcheck disable=SC2068
				outputmsg="$(echo ${mqtt_string[@]} | xargs mqtt)"

				if [[ "${outputmsg:0:6}" == "Failed" ]] || [[ "${outputmsg:0:5}" == "usage" ]]; then
					"${s6wrap[@]}" echo "MQTT Delivery Error: ${outputmsg//$'\n'/ }"
				else
					"${s6wrap[@]}" echo "MQTT Delivery successful!"
					if chk_enabled "$MQTT_DEBUG"; then "${s6wrap[@]}" echo "Results string: ${outputmsg//$'\n'/ }"; fi
				fi
				LINK="${LINK:-mqtt}"

			fi
}

debug_print "Starting generation of RSS feed"

# Create/update symlink for today's feed
if [[ -f "$RECORDSFILE" ]]; then
    # shellcheck disable=SC1090
    source "$RECORDSFILE"
else
  debug_print "Cannot find $RECORDSFILE - aborting"
  exit 1
fi

if [[ -z "$MQTT_URL" ]]; then
  debug_print "MQTT notifications are disabled - exiting"
  exit 0
fi

for ((idx=0; idx<records[maxindex]; idx++)); do

  # Skip if the record is not complete or if a notification was already sent
  if ! chk_enabled "${records["$idx":complete]}" || chk_enabled "${records["$idx":mqtt:complete]}"; then continue; fi
  generate_mqtt
done
ln -sf "$OUTFILEDIR/planefence-$TODAY.rss" "$OUTFILEDIR/planefence.rss"
declare -p records > "$RECORDSFILE" # write records back to file - 
debug_print "Done!"

