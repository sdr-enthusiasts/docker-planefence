#!/bin/bash
# PF_ALERT - a Bash shell script to send a notification to the Notification Server when a plane is detected in the
# user-defined fence area.
#
# This script is distributed as part of the PlaneFence package and is dependent
# on that package for its execution.
#
# Copyright 2020-2024 by Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#
# The package contains parts of, and modifications or derivatives to the following:
# - Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# - Twurl by Twitter: https://github.com/twitter/twurl and https://developer.twitter.com
# These packages may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
# Let's see if there is a CONF file that overwrites some of the parameters already defined
[[ "$PLANEFENCEDIR" == "" ]] && PLANEFENCEDIR=/usr/share/planefence
[[ -f "$PLANEFENCEDIR/planefence.conf" ]] && source "$PLANEFENCEDIR/planefence.conf"
#
# These are the input and output directories and file names
# HEADR determines the tags for each of the fields in the Tweet:
HEADR=("icao")
HEADR+=("callsign")
HEADR+=("starttime")
HEADR+=("endtime")
HEADR+=("minalt")
HEADR+=("mindist")
HEADR+=("adsbxlink")
HEADR+=("audioloudness")
HEADR+=("audiopeak")
HEADR+=("audio1min")
HEADR+=("audio5min")
HEADR+=("audio10min")
HEADR+=("audio60min")

# the htmlsafe function converts text into html safe text by replacing certain characters by their unicode equivalent
HTMLSAFE () { sed 's/&/%26/g; s/</%3C/g; s/>/%3E/g; s/\s/%20/g; s/"/%22/g; s/'"'"'/%27/g' <<< "$1"; }

# CSVFILE termines which file name we need to look in. We're using the 'date' command to
# get a filename in the form of 'planefence-200504.csv' where 200504 is yymmdd
TODAYCSV=$(date -d today +"planefence-%y%m%d.csv")
YSTRDAYCSV=$(date -d yesterday +"planefence-%y%m%d.csv")
# TWURLPATH is where we can find TWURL. This only needs to be filled in if you can't get it
# as part of the default PATH:
#[ ! `which twurl` ] && TWURLPATH="/root/.rbenv/shims/"

# If the VERBOSE variable is set to "1", then we'll write logs to LOGFILE.
# If you don't want logging, simply set  the VERBOSE=1 line below to VERBOSE=0
LOGFILE=/tmp/planetweet.log
TMPFILE=/tmp/planetweet.tmp
[[ "$PLANETWEET" != "" ]] && TWEETON=yes || TWEETON=no

CSVDIR=$OUTFILEDIR
CSVNAMEBASE=$CSVDIR/planefence-
CSVNAMEEXT=".csv"
VERBOSE=1
CSVTMP=/tmp/pf_notify-tmp.csv

# MINTIME is the minimum time (secs) we wait before sending a notification
# to ensure that at least $MINTIME of audio collection (actually limited to the Planefence update runs in this period) to get a more accurste Loudness.

[[ "$TWEET_MINTIME" > 0 ]] && MINTIME=$TWEET_MINTIME || MINTIME=100

# $ATTRIB contains the attribution line at the bottom of the tweet
[[ "x$ATTRIB" == "x" ]] && ATTRIB="#Planefence by kx1t - docker:kx1t/planefence"

if [ "$SOCKETCONFIG" != "" ]
then
	case "$(grep "^distanceunit=" $SOCKETCONFIG |sed "s/distanceunit=//g")" in
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
	esac
fi

# get ALTITUDE unit:
ALTUNIT="ft"
if [ "$SOCKETCONFIG" != "" ]
then
	case "$(grep "^altitudeunit=" $SOCKETCONFIG |sed "s/altitudeunit=//g")" in
		feet)
		ALTUNIT="ft"
		;;
		meter)
		ALTUNIT="m"
	esac
fi

# determine if altitude is ASL or AGL
(( ALTCORR > 0 )) && ALTPARAM="AGL" || ALTPARAM="MSL"


# -----------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------
#
# First create an function to write to the log
LOG ()
{	if [ "$VERBOSE" != "" ]
then
	printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$1" >> $LOGFILE
fi

}

TWEETDATE=$(date --date="today" '+%y%m%d')

[[ ! -f "$AIRLINECODES" ]] && AIRLINECODES=""

CSVFILE=$CSVNAMEBASE$TWEETDATE$CSVNAMEEXT
#CSVFILE=/tmp/planefence-200526.csv
# make sure there's no stray TMP file around, so we can directly append
[ -f "$CSVTMP" ] && rm "$CSVTMP"

#Now iterate through the CSVFILE:
LOG "------------------------------"
LOG "Starting PF_NOTIFY"
LOG "CSVFILE=$CSVFILE"

# Get the hashtaggable headers, and figure out of there is a field with a
# custom "$tag" header

if [ -f "$CSVFILE" ]
then
	while read CSVLINE
	do
		XX=$(echo -n $CSVLINE | tr -d '[:cntrl:]')
		CSVLINE=$XX
		unset RECORD
		# Read the line, but first clean it up as it appears to have a newline in it
		IFS="," read -aRECORD <<< "$CSVLINE"
		# LOG "${#RECORD[*]} records in the current line: (${RECORD[*]})"
		# $TIMEDIFF contains the difference in seconds between the current record and "now".
		# We want this to be at least $MINDIFF to avoid tweeting before all noise data is captured
		# $TWEET_BEHAVIOR determines if we are looking at the end time (POST -> RECORD[3]) or at the
		# start time (not POST -> RECORD[2]) of the observation time
		[[ "$TWEET_BEHAVIOR" == "POST" ]] && TIMEDIFF=$(( $(date +%s) - $(date -d "${RECORD[3]}" +%s) )) || TIMEDIFF=$(( $(date +%s) - $(date -d "${RECORD[2]}" +%s) ))

		if [[ "${RECORD[1]:0:1}" != "@" ]] && [[ $TIMEDIFF -gt $MINTIME ]] && [[ ( "$(grep "${RECORD[0]},@${RECORD[1]}" "$CSVFILE" | wc -l)" == "0" ) || "$TWEETEVERY" == "true" ]]
		#   ^not tweeted before^                 ^older than $MINTIME^             ^No previous occurrence that was notified^ ...or...                     ^$TWEETEVERY is true^
		then

			AIRLINE=$(/usr/share/planefence/airlinename.sh ${RECORD[1]#@} ${RECORD[0]} )


			# Create a Notification string that can be patched at the end of a URL:
			NOTIF_STRING=""
			for i in {0..12}
			do
				if [[ "${RECORD[i]}" != "" ]]
				then
					# only consider non-empty fields
					if (( i >= 7 )) && [[ "${RECORD[i]:0:4}" != "http" ]]
					then
						# add them if the field# >=7 and it's not a (twitter) link
						NOTIF_STRING+="${HEADR[i]}=${RECORD[i]}&"
					elif (( i < 7 ))
					then
						# also add them if the field is in the first 7 (0 through 6)
						NOTIF_STRING+="${HEADR[i]}=${RECORD[i]}&"
					fi
				fi
			done
			# strip any trailing "&" from the string:
			NOTIF_STRING="${NOTIF_STRING%%&}"

			# Before anything else, let's add the "tweeted" flag to the flight number:
			XX="@${RECORD[1]}"
			RECORD[1]=$XX

      # notify when enabled:
			if [[ "$NOTIFICATION_SERVER" != "" ]]
			then
				LOG "Planefence sending to Notification Server with \"$CSVLINE\" \"$AIRLINE\""
				[[ "${NOTIFICATION_SERVER:0:4}" != "http" ]] && NOTIFICATION_SERVER="http://${NOTIFICATION_SERVER}"
      	curl_result="$(curl -d "$NOTIF_STRING" -X POST "${NOTIFICATION_SERVER}")"
      fi

			# And now, let's tweet!
			if [ "$TWEETON" == "yes" ]
			then
				TWIMG="false"
				if [[ "$GOTSNAP" == "true" ]]
				then
					# If the curl call succeeded, we have a snapshot.png file saved!
					TW_MEDIA_ID=$(twurl -X POST -H upload.twitter.com "/1.1/media/upload.json" -f /tmp/snapshot.png -F media | sed -n 's/.*\"media_id\":\([0-9]*\).*/\1/p')
					[[ "$TW_MEDIA_ID" > 0 ]] && TWIMG="true" || TW_MEDIA_ID=""
				fi

				[[ "$TWIMG" == "true" ]] && echo "Twitter Media ID=$TW_MEDIA_ID" || echo "Twitter screenshot upload unsuccessful for ${RECORD[0]}"

				# send a tweet and read the link to the tweet into ${LINK[1]}
				if [[ "$TWIMG" == "true" ]]
				then
					LINK=$(echo `twurl -r "status=$TWEET&media_ids=$TW_MEDIA_ID" /1.1/statuses/update.json` | tee -a /tmp/tweets.log | jq '.entities."urls" | .[] | .url' | tr -d '\"')
				else
					LINK=$(echo `twurl -r "status=$TWEET" /1.1/statuses/update.json` | tee -a /tmp/tweets.log | jq '.entities."urls" | .[] | .url' | tr -d '\"')
				fi

				[[ "${LINK:0:12}" == "https://t.co" ]] && echo "PlaneFence Tweet generated successfully with content: $TWEET" || echo "PlaneFence Tweet error. Twitter returned:\n$(tail -1 /tmp/tweets.log)"
			else
				LOG "(A tweet would have been sent but \$TWEETON=\"$TWEETON\")"
			fi

			# Add a reference to the tweet to RECORD[7] (if no audio is available) or RECORD[11] (if audio is available)
			(( RECORD[7] < 0 )) && RECORD[12]="$LINK" || RECORD[7]="$LINK"
			# LOG "Tweet sent!"
			LOG "TWURL results: $LINK"
		else
			LOG "Assessing ${RECORD[0]}: ${RECORD[1]:0:1}; diff=$TIMEDIFF secs; Skipping: either already tweeted, or within $MINTIME secs."
		fi

		# Now write everything back to $CSVTMP
		( IFS=','; echo "${RECORD[*]}" >> "$CSVTMP" )
		LOG "The record now contains $(IFS=','; echo ${RECORD[*]})"

	done < "$CSVFILE"
	# last, copy the TMP file back to the CSV file
	[ -f "$CSVTMP" ] && mv -f "$CSVTMP" "$CSVFILE"
else
	LOG "$CSVFILE doesn't exist. Nothing to do..."
fi

LOG "Done!"
LOG "------------------------------"
