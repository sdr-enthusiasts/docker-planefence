#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1091,SC2154,SC2034
# send_mqtt.sh
# A script to generate MQTT posts from Planefence
#
# Usage: ./send_mqtt.sh 
#
# This script is distributed as part of the Planefence package and is dependent
# on that package for its execution.
#
# Based on a script provided by @randomrobbie - https://github.com/sdr-enthusiasts/docker-planefence/issues/211
# Copyright 2024-2026 @randomrobbie, Ramon F. Kolb (kx1t), and contributors - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#

source /scripts/pf-common
source "/usr/share/planefence/planefence.conf"

# declare arrays to hold index and stale ids
declare -a INDEX=() STALE=() link=()

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
DEBUG=false

# Get today's date in yymmdd format
TODAY=$(date --date="today" '+%y%m%d')

# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------

generate_mqtt() {
  # Generate a MQTT notification

	local idx="$1" key 

	if [[ -n "$MQTT_URL" ]]; then
		# convert $records[@] into a JSON object; if (PF_)MQTT_FIELDS is defined, then only use those fields. Exclude any internal stuff
		declare -a keys=()
		for k in "${!records[@]}"; do
			if [[ $k == "$idx:"* ]]; then keys+=("$k"); fi
		done

		MQTT_JSON="$(for i in "${keys[@]}"; do 
									if [[ -z "$MQTT_FIELDS" ]] || [[ $MQTT_FIELDS == *${i#*:}* ]]; then 
										printf '{"%s":"%s"}\n' "${i#*:}" "$(json_encode "${records[$i]}")"
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
		log_print DEBUG "Attempting to send a MQTT notification for index $idx"
		log_print DEBUG "MQTT Host: $MQTT_HOST"
		log_print DEBUG "MQTT Port: ${MQTT_PORT:-1883}"
		log_print DEBUG "MQTT TLS: $MQTT_TLS"
		log_print DEBUG "MQTT Topic: $MQTT_TOPIC"
		log_print DEBUG "MQTT Client ID: ${MQTT_CLIENT_ID:-$(hostname)}"
		if [[ -n "$MQTT_USERNAME" ]]; then log_print DEBUG "MQTT Username: $MQTT_USERNAME"; fi
		if [[ -n "$MQTT_PASSWORD" ]]; then log_print DEBUG "MQTT Password: $MQTT_PASSWORD"; fi
		if [[ -n "$MQTT_QOS" ]]; then log_print DEBUG "MQTT QOS: $MQTT_QOS"; fi
		log_print DEBUG "MQTT Payload JSON Object: $MQTT_JSON"

		# send the MQTT message:
		mqtt_string=(--broker "$MQTT_HOST")
		if [[ -n "$MQTT_PORT" ]]; then mqtt_string+=(--port "$MQTT_PORT"); fi
		if [[ -n "$MQTT_TLS" ]]; then mqtt_string+=(--tls); fi
		mqtt_string+=(--topic \""$MQTT_TOPIC"\")
		if [[ -n "$MQTT_QOS" ]]; then mqtt_string+=(--qos "$MQTT_QOS"); fi
		mqtt_string+=(--client_id \""${MQTT_CLIENT_ID:-$(hostname)}"\")
		if [[ -n "$MQTT_USERNAME" ]]; then mqtt_string+=(--username "$MQTT_USERNAME"); fi
		if [[ -n "$MQTT_PASSWORD" ]]; then mqtt_string+=(--password "$MQTT_PASSWORD"); fi
		mqtt_string+=(--message "'${MQTT_JSON}'")

		outputmsg="$(printf '%s\0' "${mqtt_string[@]}" | xargs -0 mqtt)"


		if [[ "${outputmsg:0:6}" == "Failed" ]] || [[ "${outputmsg:0:5}" == "usage" ]]; then
			log_print DEBUG "MQTT Delivery Error: ${outputmsg//$'\n'/ }"
			return 1
		else
			log_print DEBUG "MQTT Delivery successful!"
			log_print DEBUG "Results string: ${outputmsg//$'\n'/ }"
		fi
	fi
}

log_print DEBUG "Starting generation of RSS feed"



if [[ -z "$MQTT_URL" ]]; then
  log_print DEBUG "MQTT notifications are disabled - exiting"
  exit 0
fi

# read the records file
READ_RECORDS

# build index and stale arrays
build_index_and_stale INDEX STALE mqtt pf

# check if there's anything to do
if (( ${#INDEX[@]} )); then
  log_print INFO "Records ready for MQTT notification: ${INDEX[*]}"
else
  log_print INFO "No records ready for MQTT notification"
fi
if (( ${#STALE[@]} )); then
  log_print INFO "Stale records (no MQTT notification will be sent): ${STALE[*]}"
else
  log_print INFO "No stale records for MQTT notification"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print INFO "No records eligible for MQTT notification. Exiting."
  exit 0
fi

# Loop through the STALE array and mark those records as notified with status "stale"
for idx in "${STALE[@]}"; do
	records["$idx":mqtt:notified]="stale"
	log_print DEBUG "Record index $idx (${records["$idx":icao]}/${records["$idx":tail]}) marked as stale"
done

# Loop through the INDEX array and send MQTT notifications

for idx in "${INDEX[@]}"; do
  if generate_mqtt "$idx"; then
  	link[idx]=true
	log_print INFO "MQTT notification successful for index $idx (${records["$idx":icao]}/${records["$idx":tail]})"
  else
  	link[idx]=false
	log_print ERR "MQTT notification FAILED for index $idx (${records["$idx":icao]}/${records["$idx":tail]})"
  fi
done

# Save the records again
log_print DEBUG "Updating records after MQTT notifications"

LOCK_RECORDS
READ_RECORDS ignore-lock

for idx in "${STALE[@]}"; do
  records["$idx":mqtt:notified]="stale"
done

if [[ ${#link[@]} -gt 0 ]]; then records[HASNOTIFS]=true; fi

for idx in "${!link[@]}"; do
    records["$idx":mqtt:notified]="${link[idx]}"
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "MQTT notifications run completed."
