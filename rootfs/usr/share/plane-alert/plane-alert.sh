#!/bin/bash
# shellcheck shell=bash disable=SC2164,SC2015,SC2006,SC2002,SC2154,SC2076,SC2153,SC2086,SC2001,SC2016,SC2094,SC1091
# PLANE-ALERT - a Bash shell script to assess aircraft from a socket30003 render a HTML and CSV table with nearby aircraft
# based on socket30003
#
# Usage: ./plane-alert.sh <inputfile>
#
# Copyright 2021-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
#
# Summary of License Terms
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see https://www.gnu.org/licenses/.
# -----------------------------------------------------------------------------------
#
source /scripts/common
PLANEALERTDIR=/usr/share/plane-alert # the directory where this file and planefence.py are located
# -----------------------------------------------------------------------------------
#
# PLEASE EDIT PARAMETERS IN 'plane-alert.conf' BEFORE USING PLANE-ALERT !!!
##echo $0 invoked
#
# -----------------------------------------------------------------------------------
# Exit if there is no input file defined. The input file contains the socket30003 logs that we are searching in
[ "$1" == "" ] && { echo "No inputfile detected. Syntax: $0 <inputfile>"; exit 1; } || INFILE="$1"

function cleanup
{
	# do some final clean-up before exiting - this function is called by a trap on receiving the EXIT signal
	rm -f "${OUTFILE%.*}"*.diff >/dev/null 2>/dev/null
	rm -f "${OUTFILE%.*}"*.old >/dev/null 2>/dev/null
	rm -f "$TMPDIR"/plalert*.tmp >/dev/null 2>/dev/null
	rm -f /tmp/pa-diff.csv /tmp/pa-old.csv /tmp/pa-new.csv /tmp/patmp
}
#
# Now make sure we call 'cleanup' upon exit:
trap cleanup EXIT
#
# -----------------------------------------------------------------------------------
# Let's see if there is a CONF file that defines some of the parameters
[ -f "$PLANEALERTDIR/plane-alert.conf" ] && source "$PLANEALERTDIR/plane-alert.conf" || echo "Warning - cannot stat $PLANEALERTDIR/plane-alert.conf"
# -----------------------------------------------------------------------------------
#
# -----------------------------------------------------------------------------------
# Mainly - add a random search item to the plane-alert db and add a plane into the CSV with the same hex ID we just added

[[ "$SCREENSHOT_TIMEOUT" == "" ]] && SCREENSHOT_TIMEOUT=45

[[ -n "$BASETIME" ]] && echo "10a1. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: parse alert list into dictionary" || true

#
# Now let's start
#
#
# Get the file with planes to monitor.
# The file is in CSV format with this syntax:
# ICAO,TailNr,Owner,PlaneDescription
# for example:
# 42001,3CONM,GovernmentofEquatorialGuinea,DassaultFalcon900B
#

# create an associative array / dictionary from the plane alert list

declare -A ALERT_DICT

ALERT_ENTRIES=0
while IFS="" read -r line; do
	read -d , -r hex <<< "$line" || continue
	[[ -n "$hex" ]] && ALERT_DICT["${hex}"]="$line" || echo "hey badger, bad alert-list entry: \"$line\"" && continue
	((ALERT_ENTRIES=ALERT_ENTRIES+1))
done < "$PLANEFILE"

[[ -n "$BASETIME" ]] && echo "10a2. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: check input for hex numbers on alert list" || true


# Now search through the input file to see if we detect any planes in the alert list
# note - we reverse the input file because later items have a higher chance to contain callsign and tail info
# the 'sort' command will put things back in order, but the '-u' option will make sure we keep the LAST item
# rather than the FIRST item

tac "$INFILE" | {
    while IFS="" read -r line; do
        read -d , -r hex <<< "$line"
        if [[ -n ${ALERT_DICT["${hex}"]} ]]; then
            echo "${line}"
        fi
    done
}   | sort -t',' -k1,1 -k5,5 -u		`# Filter out only the unique combinations of fields 1 (ICAO) and 5 (date)` \
	> "$TMPDIR"/plalert.out.tmp		`# write the result to a tmp file`

# remove the SQUAWKS. We're not interested in them if they were picked up because of the list, and having them here
# will cause duplicate entries down the line
if [[ -f "$TMPDIR/plalert.out.tmp" ]]
then
	rm -f "$TMPDIR"/patmp
	awk -F "," 'OFS="," {$9="";print}' "$TMPDIR"/plalert.out.tmp > "$TMPDIR"/patmp
	mv -f "$TMPDIR"/patmp "$TMPDIR"/plalert.out.tmp
fi

[ "$TESTING" == "true" ] && echo "2. $TMPDIR/plalert.out.tmp contains $(cat "$TMPDIR"/plalert.out.tmp | wc -l) lines"
# Now plalert.out.tmp contains SBS data

# Let's figure out if we also need to find SQUAWKS
rm -f "$TMPDIR"/patmp
touch "$TMPDIR"/patmp
if [[ -n "$SQUAWKS" ]]
then
		IFS="," read -ra sq <<< "$SQUAWKS"
		# add some zeros to the front, in case there are less than 4 chars
		sq=( "${sq[@]/#/0000}" )
		# Now go through $INFILE and look for each of the squawks. Put the SBS data in /tmp/patmp:
		for ((i=0; i<"${#sq[@]}"; i++))
		do
			sq[i]="${sq[i]: -4}"	# get the right-most 4 characters
			sq[i]="${sq[i]//x/.}"	# replace x with dot-wildcard
			awk -F "," "{if(\$9 ~ /${sq[i]}/){print}}" "$INFILE" >>"$TMPDIR"/patmp
		done

		# Now remove any erroneous squawks. We will consider a squawk valid only if there is another
		# message more than 15 seconds apart from the same plane with the same squawk
		# First read all
		# Get the first match and the last match of the ICAO + Squawk combo
		read -d " " -r a <<< "$(wc -l "$TMPDIR"/patmp)"
		if [[ "$a" != "0" ]]
		then
			rm -f "$TMPDIR"/patmp2
			touch "$TMPDIR"/patmp2
			while IFS="" read -r line
			do
				IFS="," read -ra record <<< "$line"
				# find the first match with the same Hex ID and Squawk
				starttime="$(date -d "$(cat "$INFILE" 2>/dev/null | awk -F "," -v "ICAO=${record[0]}" -v "SQ=${record[8]}" '{if ($1 == ICAO && $9 == SQ) {print $5 " " $6; exit;}}')" +%s)"
				endtime="$(date -d "$(tac "$INFILE" 2>/dev/null | awk -F "," -v "ICAO=${record[0]}" -v "SQ=${record[8]}" '{if ($1 == ICAO && $9 == SQ) {print $5 " " $6; exit;}}')" +%s)"
				#IFS=, read -ra firstrecord <<< $(awk -F "," -v ICAO="${record[0]}" -v SQ="${record[8]}" '$1==ICAO && $9==SQ {print;exit}' "$INFILE")
				#IFS=, read -ra lastrecord <<< $(tac "$INFILE" | awk -F "," -v ICAO="${record[0]}" -v SQ="${record[8]}" '$1==ICAO && $9==SQ {print;exit}')
				#(( $(date -d "${lastrecord[4]} ${lastrecord[5]}" +%s) - $(date -d "${firstrecord[4]} ${firstrecord[5]}" +%s) > SQUAWKTIME )) && printf "%s\n" $line >> $TMPDIR/patmp2 || echo "Pruned spurious Squawk: $line"
				if (( endtime - starttime > SQUAWKTIME ))
				then
					printf "%s\n" "$line" >> "$TMPDIR"/patmp2
					"${s6wrap[@]}" echo "Found acceptable Squawk (time diff=$(( endtime - starttime )) secs): $line"
				else
					"${s6wrap[@]}" echo "Pruned spurious Squawk (time diff=$(( endtime - starttime )) secs): $line"
				fi
			done < "$TMPDIR"/patmp
			mv -f "$TMPDIR"/patmp2 "$TMPDIR"/patmp
		fi

		# clean up /tmp/patmp
		tac "$TMPDIR"/patmp | sort -t',' -k1,1 -k9,9 -u  >> "$TMPDIR"/plalert.out.tmp # sort this from the reverse of the file
		sort -t',' -k5,5 -k6,6 "$TMPDIR"/plalert.out.tmp > "$TMPDIR"/patmp
		mv -f "$TMPDIR"/patmp "$TMPDIR"/plalert.out.tmp
		# Now plalert.out.tmp may contain duplicates if there's a match on BOTH the plane-alert-db AND the Squawk
		# Going to assume that this is OK for now even though it may result in double tweets.
		# Although -- twitter may reject the second tweet.

fi


# Create a backup of $OUTFILE so we can compare later on.
touch "$OUTFILE" # ensure it always exists, even is there's no $OUTFILE
cp -f "$OUTFILE" /tmp/pa-old.csv

# Process the intermediate file with the SBS data
# example:
# 0=hex_ident,1=altitude(feet),2=latitude,3=longitude,4=date,5=time,6=angle,7=distance(kilometer),8=squawk,9=ground_speed(knotph),10=track,11=callsign
# A0B674,750,42.29663,-71.00664,2021/03/17,16:43:52.598,122.36,30.2,0305,139,321,N145NE

[[ -n "$BASETIME" ]] && echo "10b. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: start processing new data" || true

while IFS= read -r line
do
	[ "$TESTING" == "true" ] && echo 3. Parsing line "$line"
	IFS=',' read -ra pa_record <<< "$line"		# load a single line into an array called $pa_record

	# Skip the line if it's out of range
	awk "BEGIN{ exit (${pa_record[7]} < $RANGE) }" && continue || true

	PLANELINE="${ALERT_DICT[${pa_record[0]}]}"
	IFS="," read -ra TAGLINE <<< "$PLANELINE"
	# Parse this into a single line with syntax ICAO,TailNr,Owner,PlaneDescription,date,time,lat,lon,callsign,adsbx_url,squawk

	ICAO="${pa_record[0]/ */}" # ICAO (stripped spaces)
	outrec="${ICAO},"

	TAIL="${TAGLINE[1]}"
	#Get a tail number if we don't have one
	if [[ $TAIL == "" ]]; then
		TAIL="$(grep -i -w "$ICAO" /run/planefence/icao2plane.txt 2>/dev/null | head -1 | awk -F "," '{print $2}')"
	fi
	outrec+="${TAIL}," # tail

	#Get an owner if there's none, we have a tail number and we are in the US
	OWNER="${TAGLINE[2]}"
	if [[ -z $OWNER ]] && [[ -n $TAIL ]]; then
		#if [[ "${TAIL:0:1}" == "N" ]]; then
		if [[ $TAIL =~ ^N[0-9][0-9a-zA-Z]+$ ]]; then
			OWNER="$(/usr/share/planefence/airlinename.sh "$TAIL")"
		fi
	fi
	#Get an owner if there's none and there is a flight number
	if [[ -z $OWNER ]] && [[ -n ${pa_record[11]/ */} ]]; then
		OWNER="$(/usr/share/planefence/airlinename.sh "${pa_record[11]/ */}")"
	fi
	outrec+="${OWNER}," # owner name
	outrec+="${TAGLINE[3]}," # equipment
	outrec+="${pa_record[4]},"		# Date first heard
	outrec+="${pa_record[5]:0:8},"	# Time first heard
	outrec+="${pa_record[2]},"		# Latitude
	outrec+="${pa_record[3]},"		# Longitude
	outrec+="${pa_record[11]/ */}," # callsign or flt nr (stripped spaces)

	epoch_sec="$(date -d"${pa_record[4]} ${pa_record[5]}" +%s)"
  if chk_enabled "$TRACK_FIRSTSEEN"; then TRACK_FIRSTSEEN="true"; else unset TRACK_FIRSTSEEN; fi
	outrec+="https://$TRACKSERVICE/?icao=${pa_record[0]}&zoom=$MAPZOOM&lat=${pa_record[2]}&lon=${pa_record[3]}${TRACK_FIRSTSEEN:+&timestamp=${epoch_sec}&showTrace=$(date -u -d@"${epoch_sec}" "+%Y-%m-%d")},"	# ICAO for insertion into ADSBExchange link

	# only add squawk if its in the list
	x=""
	for ((i=0; i<"${#sq[@]}"; i++))
	do
		x+=$(awk "{if(\$1 ~ /${sq[i]}/){print}}" <<< "${pa_record[8]}")
	done
	[[ -n "$x"  ]] && outrec+="${pa_record[8]}"		# squawk

	echo "$outrec" >> "$OUTFILE"	# Append this line to $OUTWRITEFILE

done < "$TMPDIR"/plalert.out.tmp
# I like this better but the line below sorts nicer: awk -F',' '!seen[$1 $5)]++' "$OUTFILE" > /tmp/pa-new.csv
sort -t',' -k5,5  -k1,1 -k11,11 -u -o /tmp/pa-new.csv "$OUTFILE" 	# sort by field 5=date and only keep unique entries based on ICAO, date, and squawk. Use an intermediate file so we dont overwrite the file we are reading from
sort -t',' -k5,5  -k6,6 -o "$OUTFILE" /tmp/pa-new.csv		# sort once more by date and time but keep all entries
# the log files are now done, but we want to figure out what is new

[[ -n "$BASETIME" ]] && echo "10c. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: done processing new data" || true

# create some diff files
rm -f /tmp/pa-diff.csv
touch /tmp/pa-diff.csv
#  compare the new csv file to the old one and only print the added entries
comm -23 <(sort < "$OUTFILE") <(sort < /tmp/pa-old.csv ) >/tmp/pa-diff.csv

[[ "$(wc -l < /tmp/pa-diff.csv)" -gt "0" ]] && [[ "$LOGLEVEL" != "ERROR" ]] && echo "[planefence/plane-alert][$(date)] Plane-Alert DIFF file has $(cat /tmp/pa-diff.csv | wc -l) lines and contains:" && cat /tmp/pa-diff.csv || true
# -----------------------------------------------------------------------------------
# Next, let's do some stuff with the newly acquired aircraft of interest
# but only if there are actually newly acquired records
#

# Read the header - we will need it a few times later:

# shellcheck disable=SC2001
[[ -n "$ALERTHEADER" ]] && IFS="," read -ra header <<< "$(sed 's/\#\$/$#/g' <<< "$ALERTHEADER")" || IFS="," read -ra header <<< "$(head -n1 "$PLANEFILE" | sed 's/\#\$/$#/g')"
# if ALERTHEADER is set, then use that one instead of

[[ -n "$BASETIME" ]] && echo "10d. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: start Tweet run" || true

# If there's any new alerts send them out
if [[ "$(cat /tmp/pa-diff.csv | wc -l)" != "0" ]]
then
	# Loop through the new planes and notify them. Initialize $ERRORCOUNT to capture the number of Tweet failures:
	ERRORCOUNT=0
	while IFS= read -r line
	do
		XX=$(echo -n "$line" | tr -d '[:cntrl:]')
		line=$XX

		unset pa_record
		IFS=',' read -ra pa_record <<< "$line"

		[[ -n "$BASETIME" ]] && echo "10d1. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: processing ${pa_record[1]}" || true

		ICAO="${pa_record[0]}"

		# Get a screenshot if there\'s one available!
		snapfile="/tmp/pasnapshot.png"
		rm -f $snapfile
		GOTSNAP="false"
		newsnap="$(find /usr/share/planefence/persist/planepix -iname "${ICAO}.jpg" -print -quit 2>/dev/null || true)"

		if [[ "${SCREENSHOTURL,,}" != "off" ]] && [[ -z "${newsnap}" ]] && curl -L -s --max-time $SCREENSHOT_TIMEOUT --fail "$SCREENSHOTURL"/snap/"${pa_record[0]#\#}" -o $snapfile
		then
			GOTSNAP="true"
			"${s6wrap[@]}" echo "Screenshot successfully retrieved at $SCREENSHOTURL for ${ICAO}; saved to $snapfile"
		fi

		# Special feature for Denis @degupukas -- if no screenshot was retrieved, see if there is a picture we can add
		if [[ -n "$newsnap" ]] && [[ "$GOTSNAP" == "false" ]]
		then
			GOTSNAP="true"
			ln -sf "$newsnap" "$snapfile"
			"${s6wrap[@]}" echo "Replacing screenshot with picture from $newsnap"
		else
			link=$(awk -F "," -v icao="${ICAO,,}" 'tolower($1) ==  icao { print $2 ; exit }' /usr/share/planefence/persist/planepix.txt 2>/dev/null || true)
			[[ -n "$link" ]] && "${s6wrap[@]}" echo "Attempting to get screenshot from $link"
			if [[ -n "$link" ]] && curl -A "Mozilla/5.0 (X11; Linux x86_64; rv:97.0) Gecko/20100101 Firefox/97.0" -s -L --fail $link -o $snapfile --show-error 2>/dev/stdout
			then
				"${s6wrap[@]}" echo "Using picture from $link"
				GOTSNAP="true"
				[[ ! -f "/usr/share/planefence/persist/planepix/${ICAO}.jpg" ]] && cp "$snapfile" "/usr/share/planefence/persist/planepix/${ICAO}.jpg" || true
			else
				[[ -n "$link" ]] && "${s6wrap[@]}" echo "Failed attempt to get picture from $link" || true
			fi
		fi

		[[ "$GOTSNAP" == "false" ]] && "${s6wrap[@]}" echo "Screenshot retrieval failed at $SCREENSHOTURL for ${ICAO}." || true

		# Send Discord alerts if that's enabled
		if [[ "${PA_DISCORD,,}" != "false" ]] && [[ -n "$PA_DISCORD_WEBHOOKS" ]] && [[ -n "$DISCORD_FEEDER_NAME" ]]
		then
			[[ "$LOGLEVEL" != "ERROR" ]] && "${s6wrap[@]}" echo "PlaneAlert sending Discord notification" || true
			timeout 120 python3 $PLANEALERTDIR/send-discord-alert.py "$line"
		fi

		# Build the message field:

		[[ "${header[0]:0:1}" == "$" ]] && pa_record[0]="#${pa_record[0]}" 	# ICAO field

		[[ "${header[1]:0:1}" == "$" ]] && [[ -n "${pa_record[1]}" ]] && pa_record[1]="#${pa_record[1]//[[:space:]-]/}" 	# tail field
		[[ "${header[2]:0:1}" == "$" ]] && [[ -n "${pa_record[2]}" ]] && pa_record[2]="#${pa_record[2]}" 	# owner field
		[[ "${header[3]:0:1}" == "$" ]] && [[ -n "${pa_record[2]}" ]] && pa_record[3]="#${pa_record[3]}" # equipment field
		[[ "${header[1]:0:1}" == "$" ]] && [[ -n "${pa_record[8]}" ]] && pa_record[8]="#${pa_record[8]//[[:space:]-]/}" # flight nr field (connected to tail header)
		[[ -n "${pa_record[10]}" ]] && pa_record[10]="#${pa_record[10]}" # 	# squawk

		# First build the text of the tweet: reminder:
		# 0-ICAO,1-TailNr,2-Owner,3-PlaneDescription,4-date,5-time,6-lat,7-lon
		# 8-callsign,9-adsbx_url,10-squawk

		TWITTEXT="#PlaneAlert "
		TWITTEXT+="ICAO: ${pa_record[0]} "
		[[ -n "${pa_record[1]}" ]] && TWITTEXT+="Tail: ${pa_record[1]} "
		[[ -n "${pa_record[8]}" ]] && TWITTEXT+="Flt: ${pa_record[8]} "
		[[ -n "${pa_record[10]}" ]] && TWITTEXT+="#Squawk: ${pa_record[10]}"
		[[ "${pa_record[10]//#/}" == "7700 " ]] && TWITTEXT+=" #EMERGENCY!"
		[[ -n "${pa_record[2]}" ]] && TWITTEXT+="\nOwner: ${pa_record[2]//[ &\']/}" # trailing ']}" for vim broken syntax
		TWITTEXT+="\nAircraft: ${pa_record[3]}\n"
                twdate="$(date -d "${pa_record[4]} ${pa_record[5]}" +"${NOTIF_DATEFORMAT:-%F %T %Z}")"
		TWITTEXT+="${twdate//\//\\\/}\n"

		PLANELINE="${ALERT_DICT["${ICAO}"]}"
		IFS="," read -ra TAGLINE <<< "$PLANELINE"
		# Add any hashtags:
		for i in {4..13}
		do
			(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
			if [[ "${header[i]:0:1}" == "$" ]] || [[ "${header[i]:0:2}" == '$#' ]]
			then
				tag="${TAGLINE[i]}"
				if [[ "${tag:0:4}" == "http" ]]
				then
					TWITTEXT+="$(sed 's|/|\\/|g' <<< "$tag") "
				elif [[ -n "$tag"  ]]
				then
					TWITTEXT+="#$(tr -dc '[:alnum:]' <<< "$tag") "
				fi
			fi
		done

		TWITTEXT+="\n$(sed 's|/|\\/|g' <<< "${pa_record[9]//globe.adsbexchange.com/"$TRACKSERVICE"}")"

		TWITTEXT+="\n\n$ATTRIB"
                TWITTEXT="${TWITTEXT//\'/}"

		if [[ -n "$MASTODON_SERVER" ]] || [[ "$TWITTER" != "false" ]] || [[ -n "$BLUESKY_HANDLE" ]]; then
			"${s6wrap[@]}" echo "Attempting to Tweet, Toot, or Post this message:"
			"${s6wrap[@]}" echo "$(sed -e 's|\\/|/|g' -e 's|\\n| |g' -e 's|%0A| |g' <<< "${TWITTEXT}")"
		fi

		# Inject MQTT integration here:
		if [[ -n "$MQTT_URL" ]]; then
			# do some prep work:
			PLANELINE="${ALERT_DICT["${ICAO}"]}"
			IFS="," read -ra TAGLINE <<< "$PLANELINE"

			unset msg_array
			declare -A msg_array

			# now put all relevant info into the associative array:
			msg_array[icao]="${pa_record[0]//#/}"
			msg_array[tail]="${pa_record[1]//#/}"
			msg_array[squawk]="${pa_record[10]//#/}"
			[[ "${msg_array[squawk]}" == "7700 " ]] && msg_array[emergency]=true || msg_array[emergency]=false
			msg_array[flight]="${pa_record[8]//#/}"
			if [[ -n "${pa_record[2]}" ]]; then
				msg_array[operator]="${pa_record[2]//[\'\"]/ }"
				msg_array[operator]="${msg_array[operator]//[&]/ and }"
				msg_array[operator]="$(echo "${msg_array[operator]//#/}" | xargs)"
			fi
			msg_array[type]="${pa_record[3]//#/}"
			msg_array[datetime]="$(date -d "${pa_record[4]} ${pa_record[5]}" "+${MQTT_DATETIME_FORMAT:-%s}")"
			msg_array[tracklink]="${pa_record[9]//globe.adsbexchange.com/"$TRACKSERVICE"}"
			msg_array[latitude]="${pa_record[6]}"
			msg_array[longitude]="${pa_record[7]}"

			# Add any hashtags:
			for i in {4..13}; do
				(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
				if [[ "${header[i]:0:1}" == "$" ]] || [[ "${header[i]:0:2}" == '$#' ]]; then
					hdr="${header[i]//[#$]/}"
					hdr="${hdr// /_}"
					hdr="${hdr,,}"
					msg_array[$hdr]="${TAGLINE[i]}"
				fi
			done

			# convert $msg_array[@] into a JSON object:
                        MQTT_JSON="$(for i in "${!msg_array[@]}"; do printf '{"%s":"%s"}\n' "$i" "${msg_array[$i]}"; done | jq -sc add)"

			# prep the MQTT host, port, etc
			unset MQTT_TOPIC MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_HOST
			MQTT_HOST="${MQTT_URL,,}"
			MQTT_HOST="${MQTT_HOST##*:\/\/}" # strip protocol header (mqtt:// etc)
			while [[ "${MQTT_HOST: -1}" == "/" ]]; do MQTT_HOST="${MQTT_HOST:0: -1}"; done # remove any trailing / from the HOST
			if [[ $MQTT_HOST == *"/"* ]]; then MQTT_TOPIC="${MQTT_TOPIC:-${MQTT_HOST#*\/}}"; fi # if there's no explicitly defined topic, then use the URL's topic if that exists
			MQTT_TOPIC="${MQTT_TOPIC:-$(hostname)/planealert}" # add default topic if there is still none defined
			MQTT_HOST="${MQTT_HOST%%/*}" # remove everything from the first / onward

			if [[ $MQTT_HOST == *"@"* ]]; then
				MQTT_USERNAME="${MQTT_USERNAME:-${MQTT_HOST%@*}}"
				MQTT_PASSWORD="${MQTT_PASSWORD:-${MQTT_USERNAME#*:}}"
				MQTT_USERNAME="${MQTT_USERNAME%:*}"
				MQTT_HOST="${MQTT_HOST#*@}"
			fi
			if [[ $MQTT_HOST == *":"* ]]; then MQTT_PORT="${MQTT_PORT:-${MQTT_HOST#*:}}"; fi
			MQTT_HOST="${MQTT_HOST%:*}" # finally strip the host so there's only a hostname or ip address

			# log the message we are going to send:
			"${s6wrap[@]}" echo "pting to send a MQTT notification:"
			"${s6wrap[@]}" echo "TT_HOST}"
			"${s6wrap[@]}" echo "MQTT Port: ${MQTT_PORT:-1883}"
			"${s6wrap[@]}" echo "MQTT Topic: ${MQTT_TOPIC}"
			"${s6wrap[@]}" echo "MQTT Client ID: ${MQTT_CLIENT_ID:-$(hostname)}"
			if [[ -n "$MQTT_USERNAME" ]]; then "${s6wrap[@]}" echo "Username: ${MQTT_USERNAME}"; fi
			if [[ -n "$MQTT_PASSWORD" ]]; then "${s6wrap[@]}" echo "MQTT Password: ${MQTT_PASSWORD}"; fi
			if [[ -n "$MQTT_QOS" ]]; then "${s6wrap[@]}" echo "QOS: ${MQTT_QOS}"; fi
			"${s6wrap[@]}" echo "MQTT Payload JSON Object: ${MQTT_JSON}"

			# send the MQTT message:
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

			if [[ "${outputmsg:0:6}" == "Failed" ]] || [[ "${outputmsg:0:5}" == "usage" ]] ; then
				"${s6wrap[@]}" echo "MQTT Delivery Error: ${outputmsg//$'\n'/ }"
			else
				"${s6wrap[@]}" echo "MQTT Delivery successful!"
				if chk_enabled "$MQTT_DEBUG"; then "${s6wrap[@]}" echo "Results string: ${outputmsg//$'\n'/ }"; fi
			fi
		fi

		# Inject BlueSky integration here:
		if [[ -n "$BLUESKY_HANDLE" ]] && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then
			# get a list of images to upload
			unset images
			if [[ "$GOTSNAP" == "true" ]]; then images+=("$snapfile"); fi

			# check if there are any images in the plane-alert-db
			field=()
			readarray -td, field <<< "${ALERT_DICT[${pa_record[0]#\#}]}"
			rm -f "/tmp/planeimg*"
			for (( i=0 ; i<=20; i++ ))
			do
				fld="$(echo ${field[$i]}|xargs -0)"
				if  [[ " jpg peg png gif " =~ " ${fld: -3} " ]] && (( ${#images[@]} < 4)); then
					[[ "${fld:0:4}" != "http" ]] && fld="https://$fld" || true
					if curl -sL -A "Mozilla/5.0 (X11; Linux x86_64; rv:97.0) Gecko/20100101 Firefox/97.0" "$fld" -o "/tmp/planeimg-$i.${fld: -3}"
					then
						images+=("/tmp/planeimg-$i.${fld: -3}")
					fi
				fi
			done

			# now send the BlueSky message:
			echo "DEBUG: posting to BlueSky: /scripts/post2bsky.sh \"$(sed -e 's|\\/|/|g' -e 's|\\n|\n|g' -e 's|%0A|\n|g' <<< "${TWITTEXT}")\" ${images[*]}"
			# shellcheck disable=SC2068
			/scripts/post2bsky.sh "$(sed -e 's|\\/|/|g' -e 's|\\n|\n|g' -e 's|%0A|\n|g' <<< "${TWITTEXT}")" ${images[@]} || true
			rm -f "/tmp/planeimg*"

		fi

		# Inject Mastodon integration here:
		if [[ -n "$MASTODON_SERVER" ]]
		then
			mast_id=()
        	MASTTEXT="$(sed -e 's|\\/|/|g' -e 's|\\n|\n|g' -e 's|%0A|\n|g' <<< "${TWITTEXT}")"

			# upload a map screenshot if one is available
			if [[ "$GOTSNAP" == "true" ]]
			then
				response="$(curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "https://${MASTODON_SERVER}/api/v1/media" --form file="@${snapfile}")"
				mast_id+=("$(jq '.id' <<< "$response"|xargs -0)")

			fi

			# check if there are any images in the plane-alert-db
			field=()
			readarray -td, field <<< "${ALERT_DICT[${pa_record[0]#\#}]}"

			for (( i=0 ; i<=20; i++ ))
			do
				fld="$(echo ${field[$i]}|xargs -0)"
				ext="${fld: -3}"
				if  [[ " jpg png peg bmp gif " =~ " $ext " ]] && (( ${#mast_id[@]} < MASTODON_MAXIMGS ))
				then
					rm -f "/tmp/planeimg.*"
					[[ "$ext" == "peg" ]] && ext="jpeg" || true
					[[ "${fld:0:4}" != "http" ]] && fld="https://$fld" || true
					if curl -sL -A "Mozilla/5.0 (X11; Linux x86_64; rv:97.0) Gecko/20100101 Firefox/97.0" "$fld" -o "/tmp/planeimg.$ext"
					then
						response="$(curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "https://${MASTODON_SERVER}/api/v1/media" --form file="@/tmp/planeimg.$ext")"
						[[ "$(jq '.id' <<< "$response" | xargs -0)" != "null" ]] && mast_id+=("$(jq '.id' <<< "$response" | xargs -0)") || true
						rm -f "/tmp/planeimg.$ext"
					fi
				fi
			done
			#shellcheck disable=SC2068
			if (( ${#mast_id[@]} > 0 ))
			then
				printf -v media_ids -- '-F media_ids[]=%s ' ${mast_id[@]}
				"${s6wrap[@]}" echo "${#mast_id[@]} images uploaded to Mastodon"
			else
				media_ids=""
			fi
			# now send the Mastodon Toot.
			response="$(curl -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -s "https://${MASTODON_SERVER}/api/v1/statuses" -X POST $media_ids -F "status=${MASTTEXT}" -F "language=eng" -F "visibility=${MASTODON_VISIBILITY}")"
			# check if there was an error
			if [[ "$(jq '.error' <<< "$response"|xargs -0)" == "null" ]]
			then
				"${s6wrap[@]}" echo "Planefence post to Mastodon generated successfully with visibility=${MASTODON_VISIBILITY}. Mastodon post available at: $(jq '.url' <<< "$response"|xargs)"
			else
				"${s6wrap[@]}" echo "Mastodon post error. Mastodon returned this error: $(jq '.error' <<< "$response"|xargs -0)"
			fi
		fi

		# Send Twitter alerts if that's enabled
		if [[ "$TWITTER" != "false" ]]
		then
			# add a hashtag to the item if needed:

			[ "$TESTING" == "true" ] && ( echo 6. TWITTEXT contains this: ; echo "$TWITTEXT" )
			[ "$TESTING" == "true" ] && ( echo 7. Twitter IDs from "$TWIDFILE" )

			# Upload a screenshot if there\'s one available!
			TWIMG="false"
			if [[ "$GOTSNAP" == "true" ]]
			then
				# If the curl call succeeded, we have a snapshot.png file saved!
				TW_MEDIA_ID=$(twurl -X POST -H upload.twitter.com "/1.1/media/upload.json" -f $snapfile -F media | sed -n 's/.*\"media_id\":\([0-9]*\).*/\1/p')
				[[ "$TW_MEDIA_ID" -gt "0"  ]] && TWIMG="true" || TW_MEDIA_ID=""

				#else
				# this entire ELSE statement is test code and should be removed
				#	TW_MEDIA_ID=$(twurl -X POST -H upload.twitter.com "/1.1/media/upload.json" -f /tmp/test.png -F media | sed -n 's/.*\"media_id\":\([0-9]*\).*/\1/p')
				#	[[ "$TW_MEDIA_ID" > 0 ]] && TWIMG="true" || TW_MEDIA_ID=""
			fi
			[[ "$TWIMG" == "true" ]] && "${s6wrap[@]}" echo "Twitter Media ID=$TW_MEDIA_ID" || "${s6wrap[@]}" echo "Twitter screenshot upload unsuccessful for ${pa_record[0]}"

			if [[ "$TWITTER" == "DM" ]]
			then
				# Now loop through the Twitter IDs in $TWIDFILE and tweet the message:
				while IFS= read -r twitterid
				do
					# tweet and add the processed output to $result:
					[[ "$TESTING" == "true" ]] && echo Tweeting with the following data: recipient = \""$twitterid"\" Tweet DM = \""$TWITTEXT"\"
					[[ "$twitterid" == "" ]] && continue

					# send a tweet.
					# the conditional makes sure that tweets can be sent with or without image:
					if [[ "$TWIMG" == "true" ]] && [[ -f "$TWIDFILE" ]]
					then
						# Tweet a DM with a screenshot:
						rawresult=$($TWURL -A 'Content-type: application/json' -X POST /1.1/direct_messages/events/new.json -d '{ "event": { "type": "message_create", "message_create": { "target": { "recipient_id": "'"$twitterid"'"}, "message_data": { "text": "'"$TWITTEXT"'", "attachment": { "type": "media", "media": { "id": "'"$TW_MEDIA_ID"'" }}}}}}')
					elif [[ -f "$TWIDFILE" ]]
					then
						# Tweet a DM without a screenshot:
						rawresult=$($TWURL -A 'Content-type: application/json' -X POST /1.1/direct_messages/events/new.json -d '{"event": {"type": "message_create", "message_create": {"target": {"recipient_id": "'"$twitterid"'"}, "message_data": {"text": "'"$TWITTEXT"'"}}}}')
					fi

					processedresult=$(echo "$rawresult" | jq '.errors[].message' 2>/dev/null || true) # parse the output through JQ and if there\'s an error, provide the text to $result
					if [[ -n "$processedresult"  ]]
					then
						"${s6wrap[@]}" echo "-alert Tweet error for ${pa_record[0]}: $rawresult"
						"${s6wrap[@]}" echo "Diagnostics:"
						"${s6wrap[@]}" echo "Error: $processedresult"
						"${s6wrap[@]}" echo "Twitter ID: $twitterid"
						"${s6wrap[@]}" echo "Text: $TWITTEXT"
						(( ERRORCOUNT++ ))
					else
						"${s6wrap[@]}" echo "Plane-alert Tweet sent successfully to $twitterid for ${pa_record[0]} "
					fi
				done < "$TWIDFILE"	# done with the DM tweeting
			elif [[ "$TWITTER" == "TWEET" ]]
			then
				# tweet and add the processed output to $result:
				# replace \n by %0A -- for some reason, regular tweeting doesn't like \n's
				# also replace \/ by a regular /
				TWITTEXT="${TWITTEXT//\\n/%0A}"	# replace \n by %0A
				TWITTEXT="${TWITTEXT//\\\//\/}" # replace \/ by a regular /
				TWITTEXT="${TWITTEXT//\&/%26}" # replace & by %26

				# let\'s do some calcs on the actual tweet length, so we only strip as much as necessary
				# this problem is non trivial, so just cut 1 char at a time and loop until our teststring is short enough
				truncated=0
				while true; do
					teststring="${TWITTEXT//%0A/ }" # replace newlines with a single character
					teststring="${teststring//%26/_}" # replace %26 (&) with single char
					teststring="$(sed 's/https\?:\/\/[^ ]*\s/12345678901234567890123 /g' <<< "$teststring ")" # replace all URLS with 23 spaces - note the extra space after the string
					tweetlength=$(( ${#teststring} ))
					if (( tweetlength > 280 )); then
						truncated=$((truncated + 1))
						TWITTEXT="${TWITTEXT:0:-1}"
					else
						break
					fi
				done
				if (( truncated > 0 )); then
					TWITTEXT="$(sed 's/ https\?:\///' <<< "${TWITTEXT}")"
					"${s6wrap[@]}" echo "WARNING: Tweet has been truncated, cut $truncated characters at the end!"
				fi

				"${s6wrap[@]}" echo "Tweeting a regular tweet"

				# send a tweet.
				# the conditional makes sure that tweets can be sent with or without image:
				if [[ "$TWIMG" == "true" ]]
				then
					# Tweet a regular message with a screenshot:
					rawresult=$($TWURL -r "status=$TWITTEXT&media_ids=$TW_MEDIA_ID" /1.1/statuses/update.json)
				else
					# Tweet a regular message without a screenshot:
					rawresult=$($TWURL -r "status=$TWITTEXT" /1.1/statuses/update.json)
				fi

				processedresult=$(echo "$rawresult" | jq '.errors[].message' 2>/dev/null || true) # parse the output through JQ and if there's an error, provide the text to $result
				if [[ -n "$processedresult"  ]]
				then
					"${s6wrap[@]}" echo "Plane-alert Tweet error for ${pa_record[0]}: $rawresult"
					"${s6wrap[@]}" echo "Diagnostics:"
					"${s6wrap[@]}" echo "Error: $processedresult"
					"${s6wrap[@]}" echo "Twitter ID: $twitterid"
					"${s6wrap[@]}" echo "Text: $TWITTEXT"
					(( ERRORCOUNT++ ))
				else
					"${s6wrap[@]}" echo "Plane-alert Tweet sent successfully to $twitterid for ${pa_record[0]} "
				fi
			fi
		fi
	done < /tmp/pa-diff.csv
fi

[[ -n "$BASETIME" ]] && echo "10e. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: finished Tweet run, start building webpage" || true

(( ERRORCOUNT > 0 )) && "${s6wrap[@]}" echo "There were $ERRORCOUNT tweet errors."

# Now everything is in place, let\'s update the website

cp -f $PLANEALERTDIR/plane-alert.header.html "$TMPDIR"/plalert-index.tmp
#cat ${OUTFILE%.*}*.csv | tac > $WEBDIR/$CONCATLIST

# Create a FD for plalert-index.tml to reduce write cycles
exec 3>> "$TMPDIR"/plalert-index.tmp

# figure out if there are squawks:
awk -F "," '$12 != "" {rc = 1} END {exit !rc}' "$OUTFILE" && sqx="true" || sqx="false"

[[ -n "$BASETIME" ]] && echo "10e1. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: webpage - writing table headers" || true

# first add the fixed part of the header:
cat <<EOF >&3
<table border="1" id="mytable" class="display" id="mytable" style="width: auto; align: left" align="left">
<thead border="1">
<tr>
	<th style="text-align: center">No.</th>
	<th>Icon</th>
	<th style="text-align: center">$(sed 's/^[#$]*\(.*\)/\1/g' <<< "${header[0]}")</th> <!-- ICAO -->
	<th style="text-align: center">$(sed 's/^[#$]*\(.*\)/\1/g' <<< "${header[1]}")</th> <!-- tail -->
	<th>$(sed 's/^[#$]*\(.*\)/\1/g' <<< "${header[2]}")</th> <!-- owner -->
	<th>$(sed 's/^[#$]*\(.*\)/\1/g' <<< "${header[3]}")</th> <!-- equipment -->
	<th style="text-align: center">Date/Time First Seen</th>
	<th style="text-align: center">Lat/Lon First Seen</th>
	<th>Flight No.</th>
	$([[ "$sqx" == "true" ]] && echo "<th>Squawk</th>")
	<!-- th>Flight Map</th -->
EOF

#print the variable headers:
ICAO_INDEX=-1
for i in {4..13}
do
	(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
	[[ "${header[i]:0:1}" != "#" ]] && [[ "${header[i]:0:2}" != '$#' ]] && printf '<th>%s</th>  <!-- custom header %d -->\n' "$(sed 's/^[#$]*\(.*\)/\1/g' <<< "${header[i]}")" "$i" >&3
	[[ "${header[i]^^}" == "#ICAO TYPE" ]] || [[ "${header[i]^^}" == '$ICAO TYPE' ]] || [[ "${header[i]^^}" == '$#ICAO TYPE' ]] || [[ "${header[i]^^}" == "ICAO TYPE" ]] && ICAO_INDEX=$i

done
echo "</tr></thead><tbody border=\"1\">" >&3

[[ -n "$BASETIME" ]] && echo "10e2. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: webpage - writing table content" || true

COUNTER=1
REFDATE=$(date -d "$HISTTIME days ago" '+%Y/%m/%d %H:%M:%S')
OUTSTRING=$(tr -d -c '[:print:]\n' <"$OUTFILE")

IMGBASE="silhouettes/"

while read -r line
do
	IFS=',' read -ra pa_record <<< "$line"
	if [[ -n "${pa_record[0]}" ]] && [[ "${pa_record[4]} ${pa_record[5]}" > "$REFDATE" ]]
	then
		# prep-work for later use:
        PLANELINE="${ALERT_DICT["${pa_record[0]}"]}"
		IFS="," read -ra TAGLINE <<< "$PLANELINE"

		if [[ "${pa_record[10]}" == "7700" ]]
		then
			printf "%s\n" "<tr style=\"vertical-align: middle; color:#D9EBF9; height:20px; line-height:20px; background:#7F0000;\">" >&3
		else
			printf "%s\n" "<tr>" >&3
		fi
		printf "    %s%s%s\n" "<td style=\"text-align: center\">" "$((COUNTER++))" "</td>" >&3 # column: Number

		# determine which icon is to be used. If there's no ICAO Type field, or if there's no type in the field, or if the corresponding file doesn't exist, then replace it by BLANK.bmp
		IMGURL="$IMGBASE"

		# If there's a squawk, use it to determine the image:
		if [[ -n "${pa_record[10]}"  ]]
		then
			if [[ -f /usr/share/planefence/html/plane-alert/$IMGURL${pa_record[10]}.bmp ]]
			then
				IMGURL+="${pa_record[10]}.bmp"
			else
				IMGURL+="SQUAWK.bmp"
			fi
		else
			# there is no squawk. If there's an ICAO_INDEX value, then try to get the image URL
			if [[ "$ICAO_INDEX" != "-1" ]]
			then
				if [[ -f /usr/share/planefence/html/plane-alert/$IMGURL${TAGLINE[$ICAO_INDEX]^^}.bmp ]]
				then
					IMGURL+=${TAGLINE[$ICAO_INDEX]^^}.bmp
				else
					IMGURL+="BLNK.bmp"
				fi
			else
				# there is no squawk and no known image, so use the blank
				IMGURL+="BLNK.bmp"
			fi
		fi

		if [[ -n "${pa_record[10]}"  ]]
		then
			# print Squawk

			# determine text color for squawk
			case "${pa_record[10]}" in
				"7700")
					SQCOLOR="#7F0000"
					;;
				"7600")
					SQCOLOR="#FF6A00"
					;;
				"7500")
					SQCOLOR="#00194C"
					;;
				"7400")
					SQCOLOR="#2D3F00"
					;;
				*)
					SQCOLOR="#000000"
					;;
			esac

			printf "    %s%s%s\n" "<td style=\"padding:0;\"><div style=\"vertical-align: middle; font-weight:bold; color:#D9EBF9; height:20px; text-align:center; line-height:20px; background:$SQCOLOR;\">" "SQUAWK ${pa_record[10]}" "</div></td>" >&3

		else
			# print aircraft silhouette if it exists
			if [[ -f /usr/share/planefence/html/plane-alert/$IMGURL ]]
			then
				IMG="<img src=\"$IMGURL\">"
			else
				IMG=""
			fi

			printf "    %s%s%s\n" "<td style=\"padding: 0;\"><div style=\"vertical-align: middle; font-weight:bold; color:#D9EBF9; height:20px; text-align:center; line-height:20px; background:none;\">" "$IMG" "</div></td>" >&3
		fi

		printf "    <td style=\"text-align: center\"><a href=\"%s\" target=\"_blank\">%s</a></td>\n" "${pa_record[9]//globe.adsbexchange.com/"$TRACKSERVICE"}" "${pa_record[0]}" >>"$TMPDIR"/plalert-index.tmp # column: ICAO
		printf "    <td style=\"text-align: center\"><a href=\"%s\" target=\"_blank\">%s</a></td>\n" "https://flightaware.com/live/modes/${pa_record[0]}/ident/${pa_record[1]}/redirect" "${pa_record[1]}" >>"$TMPDIR"/plalert-index.tmp # column: Tail
		#		printf "    %s%s%s\n" "<td>" "${pa_record[0]}" "</td>" >&3 # column: ICAO
		#		printf "    %s%s%s\n" "<td>" "${pa_record[1]}" "</td>" >&3 # column: Tail
		printf "    %s%s%s\n" "<td>" "${pa_record[2]}" "</td>" >&3 # column: Owner
		printf "    %s%s%s\n" "<td>" "${pa_record[3]}" "</td>" >&3 # column: Plane Type
		printf "    %s%s%s\n" "<td style=\"text-align: center\">" "$(date -d "${pa_record[4]} ${pa_record[5]}" +"${NOTIF_DATEFORMAT:-%F %T %Z}")" "</td>" >&3 # column: Date Time
		# printf "    %s%s%s\n" "<td style=\"text-align: center\">" "<a href=\"http://www.openstreetmap.org/?mlat=${pa_record[6]}&mlon=${pa_record[7]}&zoom=$MAPZOOM\" target=\"_blank\">${pa_record[6]}N, ${pa_record[7]}E</a>" "</td>" >&3 # column: LatN, LonE
		printf "    %s%s%s\n" "<td style=\"text-align: center\">" "<a href=\"${pa_record[9]//globe.adsbexchange.com/"$TRACKSERVICE"}\" target=\"_blank\">${pa_record[6]}N, ${pa_record[7]}E</a>" "</td>" >&3 # column: LatN, LonE with link to adsbexchange
		printf "    %s%s%s\n" "<td>" "${pa_record[8]}" "</td>" >&3 # column: Flight No
		[[ "$sqx" == "true" ]] && printf "    %s%s%s\n" "<td>" "${pa_record[10]}" "</td>" >&3 # column: Squawk
		printf "    %s%s%s\n" "<!-- td>" "<a href=\"${pa_record[9]}\" target=\"_blank\">ADSBExchange link</a>" "</td -->" >&3 # column: ADSBX link


        # get appropriate entry from dictionary

		#for i in {4..13}
		for (( i=4; i<${#header[@]}; i++ ))
		do
			#(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
			if [[ "${header[i]:0:1}" != "#" ]] && [[ "${header[i]:0:2}" != '$#' ]] && [[ "${TAGLINE[i]:0:4}" == "http" ]]
			then
				printf '    <td><a href=\"%s\" target=\"_blank\">%s</a></td>  <!-- custom field %d -->\n' "${TAGLINE[i]}" "${TAGLINE[i]}" "$i" >&3
			elif [[ "${header[i]:0:1}" != "#" ]] && [[ "${header[i]:0:2}" != '$#' ]]
			then
				printf '    <td>%s</td>  <!-- custom field %d -->\n' "${TAGLINE[i]}" "$i" >&3
			fi
		done
		printf "%s\n" "</tr>" >&3
	fi
done <<< "$OUTSTRING"

[[ -n "$BASETIME" ]] && echo "10e3. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: webpage - done writing table content" || true

cat $PLANEALERTDIR/plane-alert.footer.html >&3
echo "<!-- ALERTLIST = $ALERTLIST -->" >&3

# Close the FD for $TMPDIR/plalert-index.tmp:
exec 3>&-

# Now the basics have been written, we need to replace some of the variables in the template with real data:
sed -i "s|##PA_MOTD##|$PA_MOTD|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##TRACKSERVICE##|$TRACKSERVICE|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##TABLESIZE##|$TABLESIZE|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##NAME##|$NAME|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##ADSBLINK##|$ADSBLINK|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##LASTUPDATE##|$LASTUPDATE|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##ALERTLIST##|$ALERTLIST|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##CONCATLIST##|$CONCATLIST|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##HISTTIME##|$HISTTIME|g" "$TMPDIR"/plalert-index.tmp
sed -i "s|##BUILD##|$([[ -f /usr/share/planefence/branch ]] && cat /usr/share/planefence/branch || cat /root/.buildtime)|g"  "$TMPDIR"/plalert-index.tmp
sed -i "s|##VERSION##|$(sed -n 's/\(^\s*VERSION=\)\(.*\)/\2/p' /usr/share/planefence/planefence.conf)|g" "$TMPDIR"/plalert-index.tmp
if chk_enabled "${AUTOREFRESH,,}"; then
    sed -i "s|##AUTOREFRESH##|meta http-equiv=\"refresh\" content=\"$(sed -n 's/\(^\s*PF_INTERVAL=\)\(.*\)/\2/p' /usr/share/planefence/persist/planefence.config)\"|g" "$TMPDIR"/plalert-index.tmp
else
    sed -i "s|##AUTOREFRESH##|!-- autorefresh disabled--|g" "$TMPDIR"/plalert-index.tmp
fi
[[ -n "$PF_LINK"  ]] && sed -i "s|##PFLINK##|<li> Additionally, click <a href=\"$PF_LINK\" target=\"_blank\">here</a> to visit Planefence: a list of aircraft heard that are within a short distance of the station.|g" "$TMPDIR"/plalert-index.tmp || sed -i "s|##PFLINK##||g" "$TMPDIR"/plalert-index.tmp
if [[ -n "$MASTODON_SERVER" && -n "$MASTODON_ACCESS_TOKEN" && -n "$MASTODON_NAME" ]]; then
	sed -i "s|##MASTODONLINK##|<li>Get notified instantaneously of aircraft in range by following <a rel=\"me\" href=\"https://$MASTODON_SERVER/@$MASTODON_NAME\" target=\"_blank\">@$MASTODON_NAME</a> on the <a rel=\"me\" href=\"https://$MASTODON_SERVER/\" target=\"_blank\">$MASTODON_SERVER</a> Mastodon Server|g" "$TMPDIR"/plalert-index.tmp
	sed -i "s|##MASTOHEADER##|<link href=\"https://$MASTODON_SERVER/@$MASTODON_NAME\" rel=\"me\">|g" "$TMPDIR"/plalert-index.tmp
else
    sed -i "s|##MASTODONLINK##||g" "$TMPDIR"/plalert-index.tmp
	sed -i "s|##MASTOHEADER##||g" "$TMPDIR"/plalert-index.tmp
fi
if [[ -n "$BLUESKY_HANDLE" ]] && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then 
	sed -i "s|##BLUESKYLINK##|<li>Plane-Alert notifications are sent to <a href=\"https://bsky.app/profile/$BLUESKY_HANDLE\" target=\"_blank\">@$BLUESKY_HANDLE</a> at BlueSky|g" "$TMPDIR"/plalert-index.tmp
else
	sed -i "s|##BLUESKYLINK##||g" "$TMPDIR"/plalert-index.tmp
fi
if chk_enabled "$DARKMODE"; then
  sed -i "s|##DARKMODE0##|class=\"dark\"|g" "$TMPDIR"/plalert-index.tmp
	sed -i "s|##DARKMODE1##|background-color: black; color: white;|g" "$TMPDIR"/plalert-index.tmp
	sed -i "s|##DARKMODE2##|background-color: black; color: white;|g" "$TMPDIR"/plalert-index.tmp
else
	sed -i "s|##DARKMODE0##||g" "$TMPDIR"/plalert-index.tmp
	sed -i "s|##DARKMODE1##|background-image: url(\'pa_background.jpg\'); background-repeat: no-repeat; background-attachment: fixed; background-size: cover;|g" "$TMPDIR"/plalert-index.tmp
	sed -i "s|##DARKMODE2##|background-color: #f0f6f6; color: black;|g" "$TMPDIR"/plalert-index.tmp
fi

if (( $(cat "$OUTFILE" | wc -l ) > 0 )); then
	# shellcheck disable=SC2046
	sed -i "s|##MEGALINK##|<li>Click <a href=\"https://$TRACKSERVICE/?icaoFilter=$(printf "%s," $(awk -F, 'BEGIN {ORS="\n"} !seen[$1]++ {print $1}' "$OUTFILE" | tail -$TRACKLIMIT))\">here</a> for a map with the current locations of most recent $TRACKLIMIT unique aircraft|g" "$TMPDIR"/plalert-index.tmp
else
	sed -i "s|##MEGALINK##||g" "$TMPDIR"/plalert-index.tmp
fi

#Finally, put the temp index into its place:
mv -f "$TMPDIR"/plalert-index.tmp "$WEBDIR"/index.html
[[ -n "$BASETIME" ]] && echo "10f. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- plane-alert.sh: done building webpage, finished Plane-Alert" || true
