#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC2015,SC1091,SC2005,SC2006,SC2094,SC2154
# PLANETWEET - a Bash shell script to send a Tweet when a plane is detected in the
# user-defined fence area.
#
# Usage: ./planefence_notify.sh
#
# Note: this script is meant to be run as a daemon using SYSTEMD
# If run manually, it will continuously loop to listen for new planes
#
# This script is distributed as part of the Planefence package and is dependent
# on that package for its execution.
#
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#
# The package contains parts of, and modifications or derivatives to the following:
# - Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# - Twurl by Twitter: https://github.com/twitter/twurl and https://developer.twitter.com
# These packages may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
# Feel free to make changes to the variables between these two lines. However, it is
# STRONGLY RECOMMENDED to RTFM! See README.md for explanation of what these do.
#
# -----------------------------------------------------------------------------------
# export all variables so send-discord-alert.py has access to the necessary params:
# set -a
#
# Let's see if there is a CONF file that overwrites some of the parameters already defined

source /scripts/common

[[ -z "$PLANEFENCEDIR" ]] && PLANEFENCEDIR=/usr/share/planefence
[[ -f "$PLANEFENCEDIR/planefence.conf" ]] && source "$PLANEFENCEDIR/planefence.conf"
#
# These are the input and output directories and file names
# HEADR determines the tags for each of the fields in the Tweet:
#         0      1      2           3           4         5         6         7        8          9        10     11
HEADR=("ICAO" "Flt" "Airline" "First seen" "End Time" "Min Alt" "Min Dist" "Link" "Loudness" "Peak Audio" "Org" "Dest")

# CSVFILE termines which file name we need to look in. We're using the 'date' command to
# get a filename in the form of 'planefence-200504.csv' where 200504 is yymmdd
#TODAYCSV=$(date -d today +"planefence-%y%m%d.csv")
#YSTRDAYCSV=$(date -d yesterday +"planefence-%y%m%d.csv")
# TWURLPATH is where we can find TWURL. This only needs to be filled in if you can't get it
# as part of the default PATH:
#[ ! `which twurl` ] && TWURLPATH="/root/.rbenv/shims/"

# If the VERBOSE variable is set to "1", then we'll write logs to LOGFILE.
# If you don't want logging, simply set  the VERBOSE=1 line below to VERBOSE=0
LOGFILE=/tmp/planetweet.log
#TMPFILE=/tmp/planetweet.tmp
[[ "$PLANETWEET" != "" ]] && TWEETON=yes || TWEETON=no

CSVDIR=$OUTFILEDIR
CSVNAMEBASE=$CSVDIR/planefence-
CSVNAMEEXT=".csv"
VERBOSE=1
CSVTMP=/tmp/planetweet2-tmp.csv
PLANEFILE=/usr/share/planefence/persist/plane-alert-db.txt
# MINTIME is the minimum time we wait before sending a tweet
# to ensure that at least $MINTIME of audio collection (actually limited to the Planefence update runs in this period) to get a more accurste Loudness.

((TWEET_MINTIME > 0)) && MINTIME=$TWEET_MINTIME || MINTIME=100

# $ATTRIB contains the attribution line at the bottom of the tweet
ATTRIB="${ATTRIB:-#adsb #planefence by kx1t - https://sdr-e.com/docker-planefence}"

if [ "$SOCKETCONFIG" != "" ]; then
	case "$(grep "^distanceunit=" "$SOCKETCONFIG" | sed "s/distanceunit=//g")" in
	nauticalmile)
		DISTUNIT="nm"
		;;
	kilometer)
		DISTUNIT="km"
		;;
	mile)
		DISTUNIT="mi"
		;;
	meter)
		DISTUNIT="m"
		;;
	esac
fi

# get ALTITUDE unit:
ALTUNIT="ft"
if [ "$SOCKETCONFIG" != "" ]; then
	case "$(grep "^altitudeunit=" "$SOCKETCONFIG" | sed "s/altitudeunit=//g")" in
	feet)
		ALTUNIT="ft"
		;;
	meter)
		ALTUNIT="m"
		;;
	esac
fi

# determine if altitude is ASL or AGL
((ALTCORR > 0)) && ALTPARAM="AGL" || ALTPARAM="MSL"

# -----------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------
#
# First create an function to write to the log
LOG() {
	if [ "$VERBOSE" != "" ]; then
		printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$1" >>$LOGFILE
	fi
}

getRoute() {
	# Uses MrJackWills's API to look up flight information based on Callsign. See https://github.com/mrjackwills/adsbdb
	# Usage: routeString="$(getRoute "$CallSign")"
	#
	# Returns a string:
	#    if both Origin and Destination airport are available:  "#BOS-#JFK"
	#    if only either Origin or Destination airport are known: "org: #BOS" or "dest: #JFK"
	#    if neither is available: empty string
	#
	# Prerequisites/dependencies: JQ, CURL

	# first make sure we have an argument
	if [[ -z "$1" ]]; then
		return
	fi

	# Now get the results object from the API:
	routeObj="$(curl -sL "https://api.adsbdb.com/v0/callsign/$1")"

	# Unknown Call -> return empty
	if [[ "$(jq '.response' <<<"$routeObj")" == "\"unknown callsign\"" ]]; then
		return
	fi

	# Get origin/dest:
	origin="$(jq '.response.flightroute.origin.iata_code' 2>/dev/null <<<"$routeObj" | tr -d '\"')"
	destination="$(jq '.response.flightroute.destination.iata_code' 2>/dev/null <<<"$routeObj" | tr -d '\"')"
	response=""

	if [[ -n "$origin" ]] && [[ -n "$destination" ]]; then
		response="#$origin - #$destination"
	elif [[ -n "$origin" ]]; then
		response="org: #$origin"
	elif [[ -n "$destination" ]]; then
		response="dest: #$destination"
	fi

	# print the result - this will be captured by the caller
	echo "$response"
}

GET_PS_PHOTO () {
	# Function to get a photo from PlaneSpotters.net
	# Usage: GET_PS_PHOTO ICAO
	# Returns: link to photo page (and a cached image should become available)
	# First, let's see if we have a cache file for the photos

	local link
	local json
	local starttime

	starttime="$(date +%s)"

	if chk_disabled "$SHOWIMAGES"; then return 0; fi

	if [[ -f "/usr/share/planefence/persist/planepix/cache/$1.notavailable" ]]; then
		echo "pfn - $(date) - $(( $(date +%s) - starttime )) secs - $1 - no picture available (checked previously)" >> /tmp/getpi.log
		return 0
	fi

	if [[ -f "/usr/share/planefence/persist/planepix/cache/$1.jpg" ]] && \
		 [[ -f "/usr/share/planefence/persist/planepix/cache/$1.link" ]] && \
		 [[ -f "/usr/share/planefence/persist/planepix/cache/$1.thumb.link" ]]; then
		echo "$(<"/usr/share/planefence/persist/planepix/cache/$1.link")"
		echo "pfn - $(date) - $(( $(date +%s) - starttime )) secs - $1 - picture was in cache" >> /tmp/getpi.log
		return 0
	fi
	# If we don't have a cache file, let's see if we can get one from PlaneSpotters.net
	if json="$(curl -ssL --fail "https://api.planespotters.net/pub/photos/hex/$1")" && \
					link="$(jq -r 'try .photos[].link | select( . != null )' <<< "$json")" && \
          thumb="$(jq -r 'try .photos[].thumbnail_large.src | select( . != null )' <<< "$json")" && \
				  [[ -n "$link" ]] && [[ -n "$thumb" ]]; then
		# If we have a link, let's download the photo
		curl -ssL --fail --clobber "$thumb" -o "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		echo "$link" > "/usr/share/planefence/persist/planepix/cache/$1.link"
		echo "$thumb" > "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
		echo "$link"
		echo "pfn - $(date) - $(( $(date +%s) - starttime )) secs - $1 - picture retrieved from planespotters.net" >> /tmp/getpi.log
	else
		# If we don't have a link, let's clear the cache and return an empty string
		rm -f "/usr/share/planefence/persist/planepix/cache/$1.*"
		touch "/usr/share/planefence/persist/planepix/cache/$1.notavailable"
		echo "pfn - $(date) - $(( $(date +%s) - starttime )) secs - $1 - no picture available (new)" >> /tmp/getpi.log
	fi
}

if [ "$1" != "" ] && [ "$1" != "reset" ]; then # $1 contains the date for which we want to run Planefence
	TWEETDATE=$(date --date="$1" '+%y%m%d')
else
	TWEETDATE=$(date --date="today" '+%y%m%d')
fi

[[ ! -f "$AIRLINECODES" ]] && AIRLINECODES=""

CSVFILE=$CSVNAMEBASE$TWEETDATE$CSVNAMEEXT
#CSVFILE=/tmp/planefence-200526.csv
# make sure there's no stray TMP file around, so we can directly append
[ -f "$CSVTMP" ] && rm "$CSVTMP"

#Now iterate through the CSVFILE:
LOG "------------------------------"
LOG "Starting PLANEFENCE_NOTIFY"
LOG "CSVFILE=$CSVFILE"

# Get the hashtaggable headers, and figure out of there is a field with a
# custom "$tag" header

[[ -f "$PLANEFILE" ]] && IFS="," read -ra hashtag <$PLANEFILE || unset hashtag
tagfield=""
for ((i = 0; i < ${#hashtag[@]}; i++)); do
	if [[ "${hashtag[i],,}" == "\$tag" ]] || [[ "${hashtag[i],,}" == "#\$tag" ]]; then
		tagfield=$((i + 1)) # number tagfield from 1 instead of 0 as we will use AWK to get it
		break
	fi
done

if [ -f "$CSVFILE" ]; then
	while read -r CSVLINE; do
		XX=$(echo -n "$CSVLINE" | tr -d '[:cntrl:]')
		CSVLINE=$XX
		unset RECORD
		# Read the line, but first clean it up as it appears to have a newline in it
		IFS="," read -ra RECORD <<<"$CSVLINE"
		# LOG "${#RECORD[*]} records in the current line: (${RECORD[*]})"
		# $TIMEDIFF contains the difference in seconds between the current record and "now".
		# We want this to be at least $MINDIFF to avoid tweeting before all noise data is captured
		# $TWEET_BEHAVIOR determines if we are looking at the end time (POST -> RECORD[3]) or at the
		# start time (not POST -> RECORD[2]) of the observation time
		[[ "$TWEET_BEHAVIOR" == "POST" ]] && TIMEDIFF=$(($(date +%s) - $(date -d "${RECORD[3]}" +%s))) || TIMEDIFF=$(($(date +%s) - $(date -d "${RECORD[2]}" +%s)))

		# shellcheck disable=SC2126
		# shellcheck disable=SC2094
		if [[ "${RECORD[1]:0:1}" != "@" ]] && [[ $TIMEDIFF -gt $MINTIME ]] && [[ ("$(grep "${RECORD[0]},@${RECORD[1]}" "$CSVFILE" | wc -l)" == "0") || "$TWEETEVERY" == "true" ]]; then #   ^not tweeted before^                 ^older than $MINTIME^             ^No previous occurrence that was tweeted^ ...or...                     ^$TWEETEVERY is true^

			AIRLINE=$(/usr/share/planefence/airlinename.sh "${RECORD[1]#@}" "${RECORD[0]}")
			AIRLINETAG="#"
			if [[ "${RECORD[1]}" != "" ]]; then
				AIRLINETAG+="$(echo "$AIRLINE" | tr -d '[:space:]-')"
				ROUTE="$(getRoute "${RECORD[1]}")"
			fi

			# Create a Tweet with the first 6 fields, each of them followed by a Newline character
			[[ "${hashtag[0]:0:1}" == "$" ]] && TWEET="${HEADR[0]}: #${RECORD[0]}%0A" || TWEET="${HEADR[0]}: ${RECORD[0]}%0A" # ICAO
			if [[ "${RECORD[1]}" != "" ]]; then
				[[ "${hashtag[1]:0:1}" == "$" ]] && TWEET+="${HEADR[1]}: #${RECORD[1]//-/}" || TWEET+="${HEADR[1]}: ${RECORD[1]}" # Flight
			fi
			[[ "$AIRLINETAG" != "#" ]] && TWEET+=" ${AIRLINETAG//[&\'-]/_}" || true
			[[ -n "$ROUTE" ]] && TWEET+=" $ROUTE" || true
			TWEET+="%0A${HEADR[3]}: $(date -d "${RECORD[2]}" +"${NOTIF_DATEFORMAT:-%F %T %Z}")%0A"
			TWEET+="${HEADR[5]}: ${RECORD[4]} $ALTUNIT $ALTPARAM%0A"
			TWEET+="${HEADR[6]}: ${RECORD[5]} $DISTUNIT%0A"

			# If there is sound level data, then add a Loudness factor (peak RMS - 1 hr avg) to the tweet.
			# There is more data we could tweet, but we're a bit restricted in real estate on twitter.
			((RECORD[7] < 0)) && TWEET+="${HEADR[9]}: ${RECORD[7]} dBFS%0A${HEADR[8]}: $((RECORD[7] - RECORD[11])) dB%0A"

			# figure out of there are custom tags that apply to this ICAO:
			[[ "$tagfield" != "" ]] && customtag="$(awk -F "," -v field="$tagfield" -v icao="${RECORD[0]}" '$1 == icao {print $field; exit;}' "$PLANEFILE")" || customtag=""
			[[ "$customtag" != "" ]] && TWEET+="#$customtag "

			TWEET+="%0A${RECORD[6]}"
			# Add attribution to the tweet:
			TWEET+="%0A$ATTRIB"

			# swap adsbexchange for the $TRACKSERVICE:
			TWEET="${TWEET//globe.adsbexchange.com/"$TRACKSERVICE"}"

			LOG "Assessing ${RECORD[0]}: ${RECORD[1]:0:1}; diff=$TIMEDIFF secs; Tweeting... msg body: $TWEET" 1

			# Before anything else, let's add the "tweeted" flag to the flight number:
			XX="@${RECORD[1]}"
			RECORD[1]=$XX

			# First, let's get a screenshot if there's one available!
			rm -f /tmp/snapshot.png
			GOTSNAP=false
			GOTIMG=false
			snapfile="/tmp/snapshot.png"

			# img will contain the path to an image file:
			# - first prio is one that is stored in the planepix directory
			# - second prio is one that is stored in the planepix/cache directory

			imgfile="$(find /usr/share/planefence/persist/planepix -iname "${RECORD[0]}.jpg" -print -quit 2>/dev/null || true)"
			# echo "-0- in planetweet: newsnap=\"$newsnap\" (find /usr/share/planefence/persist/planepix -iname ${RECORD[0]}.jpg -print -quit)"
			if [[ -n "$imgfile" ]]; then
				GOTIMG=true
				"${s6wrap[@]}" echo "Using picture from $imgfile"
			else
				imglink=$(awk -F "," -v icao="${RECORD[0],,}" 'tolower($1) ==  icao { print $2 ; exit }' /usr/share/planefence/persist/planepix.txt 2>/dev/null || true)
				if [[ -n "$imglink" ]] && curl -A "Mozilla/5.0 (X11; Linux x86_64; rv:97.0) Gecko/20100101 Firefox/97.0" -s -L --fail "$imglink" --clobber  -o $snapfile 2>/dev/stdout; then
					"${s6wrap[@]}" echo "Got picture from $link"
					GOTIMG=true
					cp -n "$snapfile" "/usr/share/planefence/persist/planepix/cache/${RECORD[0]}.jpg"
					rm -f "$snapfile"
					imgfile="/usr/share/planefence/persist/planepix/cache/${RECORD[0]}.jpg"
				elif [[ -n "$imglink" ]]; then
					"${s6wrap[@]}" echo "Failed attempt to get picture from planepix.txt link $link"
				fi
			fi

			# If there's no image, let's see if we can get one from planespotters.net
			if ! $GOTIMG && [[ -n "$(GET_PS_PHOTO "${RECORD[0]}")" ]]; then
				imgfile="/usr/share/planefence/persist/planepix/cache/${RECORD[0]}.jpg"
				GOTIMG=true
				"${s6wrap[@]}" echo "Got picture from PlaneSpotters.net"
			fi

			"${s6wrap[@]}" echo "Getting screenshot for ${RECORD[0]}..."
			if curl -s -L --fail --max-time "$SCREENSHOT_TIMEOUT" "$SCREENSHOTURL/snap/${RECORD[0]#\#}" --clobber  -o "/tmp/snapshot.png"; then
				GOTSNAP=true
				"${s6wrap[@]}" echo "Screenshot successfully retrieved at $SCREENSHOTURL for ${RECORD[0]}"
			fi
			if ! $GOTSNAP; then "${s6wrap[@]}" echo "Screenshot retrieval unsuccessful at $SCREENSHOTURL for ${RECORD[0]}"; fi

			# Inject the Discord integration in here so it doesn't have to worry about state management
			if [[ "${PF_DISCORD,,}" == "on" || "${PF_DISCORD,,}" == "true" ]] && [[ "x$PF_DISCORD_WEBHOOKS" != "x" ]] && [[ "x$DISCORD_FEEDER_NAME" != "x" ]]; then
				LOG "Planefence sending Discord notification"
				timeout 120 python3 "$PLANEFENCEDIR"/send-discord-alert.py "$CSVLINE" "$AIRLINE"
			fi

			# log the message we will try to tweet or toot:
			if [[ -n "$MASTODON_SERVER" ]]; then
				"${s6wrap[@]}" echo "Attempting to tweet or toot: $(sed -e 's|\\/|/|g' -e 's|\\n| |g' -e 's|%0A| |g' <<<"${TWEET}")"
			fi

			# Inject Mastodon integration here:
			if [[ -n "$MASTODON_SERVER" ]]; then
				mast_id=()
				MASTTEXT="$(sed -e 's|\\/|/|g' -e 's|\\n|\n|g' -e 's|%0A|\n|g' <<<"${TWEET}")"

				if $GOTSNAP && response="$(curl -sS --fail -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "https://${MASTODON_SERVER}/api/v1/media" --form file="@${snapfile}")"; then
					# we upload an screenshot
					mast_id+=("$(jq '.id' <<<"$response" | xargs)")
				fi

				if $GOTIMG && response="$(curl -sS -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "https://${MASTODON_SERVER}/api/v1/media" --form file="@${imgfile}")"; then
					# we upload an image file
						mast_id+=("$(jq '.id' <<<"$response" | xargs)")
				fi

				# now send the message. API is different if text-only vs text+image:
				if [[ -z "${mast_id[*]}" ]]; then
					# send without image(s)
					response="$(curl -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -sS "https://${MASTODON_SERVER}/api/v1/statuses" -X POST -F "status=${MASTTEXT}" -F "language=eng" -F "visibility=${MASTODON_VISIBILITY}")"
				else
					# send with image(s)
					# shellcheck disable=SC2068
					printf -v media_ids -- '-F media_ids[]=%s ' ${mast_id[@]}
					# shellcheck disable=SC2086
					response="$(curl -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -s "https://${MASTODON_SERVER}/api/v1/statuses" -X POST $media_ids -F "status=${MASTTEXT}" -F "language=eng" -F "visibility=${MASTODON_VISIBILITY}")"
				fi

				# check if there was an error
				if [[ "$(jq '.error' <<<"$response" | xargs)" == "null" ]]; then
					"${s6wrap[@]}" echo "Planefence post to Mastodon generated successfully with visibility=${MASTODON_VISIBILITY}. Mastodon post available at: $(jq '.url' <<<"$response" | xargs)"
					LINK="$(jq '.url' <<<"${response}" | xargs)"
				else
					"${s6wrap[@]}" echo "Mastodon post error. Mastodon returned this error: $(jq '.url' <<<"$response" | xargs)"
				fi
			fi

			# Inject MQTT notification here:
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

				# convert $msg_array[@] into a JSON object:
				MQTT_JSON="$(for i in "${!msg_array[@]}"; do printf '{"%s":"%s"}\n' "$i" "${msg_array[$i]}"; done | jq -sc add)"

				# prep the MQTT host, port, etc
				unset MQTT_TOPIC MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_HOST
				MQTT_HOST="${MQTT_URL,,}"
				MQTT_HOST="${MQTT_HOST##*:\/\/}"                                                    # strip protocol header (mqtt:// etc)
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

			# Insert Telegram notifications here:
			if chk_enabled "$TELEGRAM_ENABLED"; then
				/scripts/post2telegram.sh PF "#Planefence $(sed -e 's|\\/|/|g' -e 's|\\n|\n|g' -e 's|%0A|\n|g' <<<"${TWEET}")" "$(if $GOTSNAP; then echo "$snapfile"; fi)" "$(if $GOTIMG; then echo "$imgfile"; fi)" || true
				if [[ -f /tmp/telegram.link ]]; then
					LINK="$(</tmp/telegram.link)"
					rm -f /tmp/telegram.link
				fi
			fi
			# Insert BlueSky notifications here:
			if [[ -n "$BLUESKY_HANDLE" ]] && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then
				/scripts/post2bsky.sh "#Planefence $(sed -e 's|\\/|/|g' -e 's|\\n|\n|g' -e 's|%0A|\n|g' <<<"${TWEET}")" "$(if $GOTSNAP; then echo "$snapfile"; fi)" "$(if $GOTIMG; then echo "$imgfile"; fi)" || true
				if [[ -f /tmp/bsky.link ]]; then
					LINK="$(</tmp/bsky.link)"
					rm -f /tmp/bsky.link
				fi
			fi

			# And now, let's tweet!
			if [ "$TWEETON" == "yes" ]; then
				TWIMG="false"
				if [[ "$GOTSNAP" == "true" ]]; then
					# If the curl call succeeded, we have a snapshot.png file saved!
					TW_MEDIA_ID=$(twurl -X POST -H upload.twitter.com "/1.1/media/upload.json" -f $snapfile -F media | sed -n 's/.*\"media_id\":\([0-9]*\).*/\1/p')
					((TW_MEDIA_ID > 0)) && TWIMG="true" || TW_MEDIA_ID=""
				fi

				[[ "$TWIMG" == "true" ]] && "${s6wrap[@]}" echo "Twitter Media ID=$TW_MEDIA_ID" || "${s6wrap[@]}" echo "Twitter screenshot upload unsuccessful for ${RECORD[0]}"

				# send a tweet and read the link to the tweet into ${LINK[1]}
				if [[ "$TWIMG" == "true" ]]; then
					LINK="$(echo "$(twurl -r "status=$TWEET&media_ids=$TW_MEDIA_ID" /1.1/statuses/update.json)" | tee -a /tmp/tweets.log | jq '.entities."urls" | .[] | .url' | tr -d '\"')"
				else
					LINK="$(echo "$(twurl -r "status=$TWEET" /1.1/statuses/update.json)" | tee -a /tmp/tweets.log | jq '.entities."urls" | .[] | .url' | tr -d '\"')"
				fi

				# shellcheck disable=SC2028
				[[ "${LINK:0:12}" == "https://t.co" ]] && "${s6wrap[@]}" echo "Planefence post to Twitter generated successfully. Tweet available at: $LINK" || "${s6wrap[@]}" echo "Planefence Tweet error. Twitter returned:\n$(tail -1 /tmp/tweets.log)"
				rm -f $snapfile

			else
				LOG "(A tweet would have been sent but \$TWEETON=\"$TWEETON\")"
			fi

			# Add a reference to the tweet to RECORD[7] (if no audio is available) or RECORD[11] (if audio is available)
			if [[ -n "$LINK" ]]; then 
				if [[ -n "${RECORD[7]}" ]]; then 
					RECORD[12]="$LINK"
				else 
					RECORD[7]="$LINK"
				fi
			fi
			# LOG "Tweet sent!"
			LOG "TWURL results: $LINK"
		else
			LOG "Assessing ${RECORD[0]}: ${RECORD[1]:0:1}; diff=$TIMEDIFF secs; Skipping: either already tweeted, or within $MINTIME secs."
		fi

		# Now write everything back to $CSVTMP
		(
			IFS=','
			echo "${RECORD[*]}" >>"$CSVTMP"
		)
		LOG "The record now contains $(
			IFS=','
			echo "${RECORD[*]}"
		)"

	done <"$CSVFILE"
	# last, copy the TMP file back to the CSV file
	[ -f "$CSVTMP" ] && mv -f "$CSVTMP" "$CSVFILE"
else
	LOG "$CSVFILE doesn't exist. Nothing to do..."
fi

LOG "Done!"
LOG "------------------------------"
