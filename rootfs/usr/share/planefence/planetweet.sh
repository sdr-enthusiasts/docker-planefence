#!/bin/bash
# PLANETWEET - a Bash shell script to send a Tweet when a plane is detected in the
# user-defined fence area.
#
# Usage: ./planetweet.sh
#
# Note: this script is meant to be run as a daemon using SYSTEMD
# If run manually, it will continuously loop to listen for new planes
#
# This script is distributed as part of the PlaneFence package and is dependent
# on that package for its execution.
#
# Copyright 2020 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence
#
# The package contains parts of, and modifications or derivatives to the following:
# - Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# - Twurl by Twitter: https://github.com/twitter/twurl and https://developer.twitter.com
# These packages may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
# Feel free to make changes to the variables between these two lines. However, it is
# STRONGLY RECOMMENDED to RTFM! See README.md for explanation of what these do.
#
# Let's see if there is a CONF file that overwrites some of the parameters already defined
[[ "x$PLANEFENCEDIR" == "x" ]] && PLANEFENCEDIR=/usr/share/planefence
[[ -f "$PLANEFENCEDIR/planefence.conf" ]] && source "$PLANEFENCEDIR/planefence.conf"
#
# These are the input and output directories and file names
# HEADR determines the tags for each of the fields in the Tweet:
HEADR=("ICAO" "Flt" "Airline" "First seen" "End Time" "Min Alt" "Min Dist" "Link" "Loudness" "Peak Audio")
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
CSVTMP=/tmp/planetweet2-tmp.csv
PLANEFILE=/usr/share/planefence/persist/plane-alert-db.txt
# MINTIME is the minimum time we wait before sending a tweet
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

if [ "$1" != "" ] && [ "$1" != "reset" ]
then # $1 contains the date for which we want to run PlaneFence
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
LOG "Starting PLANETWEET"
LOG "CSVFILE=$CSVFILE"

# Get the hashtaggable headers, and figure out of there is a field with a
# custom "$tag" header

[[ -f "$PLANEFILE" ]] && IFS="," read -ra hashtag < $PLANEFILE || unset hashtag
tagfield=""
for ((i = 0 ; i < ${#hashtag[@]} ; i++))
do
	if [[ "${hashtag[i],,}" == "$tag" ]] || [[ "${hashtag[i],,}" == "#$tag" ]]
	then
		tagfield=$((i+1)) # number tagfield from 1 instead of 0 as we will use AWK to get it
		break;
	fi
done

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
		#   ^not tweeted before^                 ^older than $MINTIME^             ^No previous occurrence that was tweeter^ ...or...                     ^$TWEETEVERY is true^
		then

			AIRLINE=$(/usr/share/planefence/airlinename.sh ${RECORD[1]#@} ${RECORD[0]} )
			AIRLINETAG="#"
			[[ "${RECORD[1]#@}" != "" ]] && AIRLINETAG+="$(echo $AIRLINE | tr -d '[:space:]-')"

			# Create a Tweet with the first 6 fields, each of them followed by a Newline character
			[[ "${hashtag[0]:0:1}" == "$" ]] && TWEET="${HEADR[0]}: #${RECORD[0]}%0A" || TWEET="${HEADR[0]}: ${RECORD[0]}%0A" # ICAO
			if [[ "${RECORD[1]}" != "" ]]
			then
				[[ "${hashtag[1]:0:1}" == "$" ]] && TWEET+="${HEADR[1]}: #${RECORD[1]//-/}" || TWEET+="${HEADR[1]}: ${RECORD[1]}" # Flight
			fi
			[[ "$AIRLINETAG" != "#" ]] && TWEET+=" ${AIRLINETAG//[&\'-]/_}"
			TWEET+="%0A${HEADR[3]}: ${RECORD[2]}%0A"
			TWEET+="${HEADR[5]}: ${RECORD[4]} $ALTUNIT $ALTPARAM%0A"
			TWEET+="${HEADR[6]}: ${RECORD[5]} $DISTUNIT%0A"

			# If there is sound level data, then add a Loudness factor (peak RMS - 1 hr avg) to the tweet.
			# There is more data we could tweet, but we're a bit restricted in real estate on twitter.
			(( RECORD[7] < 0 )) && TWEET+="${HEADR[9]}: ${RECORD[7]} dBFS%0A${HEADR[8]}: $(( RECORD[7] - RECORD[11] )) dB%0A"

			# figure out of there are custom tags that apply to this ICAO:
			[[ "$tagfield" != "" ]] && customtag="$(awk -F "," -v field="$tagfield" -v icao="${RECORD[0]}" '$1 == icao {print $field; exit;}' "$PLANEFILE")" || customtag=""
			[[ "$customtag" != "" ]] && TWEET+="#$customtag "

			# Add attribution to the tweet:
			TWEET+="%0A$ATTRIB%0A"

			# let's do some calcs on the actual tweet length, so we strip the minimum:
			teststring="${TWEET//%0A/ }" # replace newlines with a single character
			teststring="$(sed 's/https\?:\/\/[^ ]*\s/12345678901234567890123 /g' <<< "$teststring ")" # replace all URLS with 23 spaces - note the extra space after the string
			tweetlength=$(( ${#teststring} - 1 ))
			(( tweetlength > 280 )) && echo "Warning: PF tweet length is $tweetlength > 280: tweet will be truncated!"
			(( tweetlength > 280 )) && maxlength=$(( ${#TWEET} + 280 - tweetlength )) || maxlength=280

			TWEET="${TWEET:0:$maxlength}"

			# Now add the last field (attribution) without title or training Newline
			# Reason: this is a URL that Twitter reinterprets and previews on the web
			# Also, the Newline at the end tends to mess with Twurl
			TWEET+="${RECORD[6]}"

			LOG "Assessing ${RECORD[0]}: ${RECORD[1]:0:1}; diff=$TIMEDIFF secs; Tweeting... msg body: $TWEET" 1

			# Before anything else, let's add the "tweeted" flag to the flight number:
			XX="@${RECORD[1]}"
			RECORD[1]=$XX

			# First, let's get a screenshot if there's one available!
			rm -f /tmp/snapshot.png
			GOTSNAP="false"
			if curl -s -L --fail --max-time $SCREENSHOT_TIMEOUT $SCREENSHOTURL/snap/${RECORD[0]#\#} -o "/tmp/snapshot.png"
			then
				GOTSNAP="true"
			fi

			# LOG "PF_DISCORD: $PF_DISCORD"
			# LOG "PF_DISCORD_WEBHOOKS: $PF_DISCORD_WEBHOOKS"
			# LOG "DISCORD_FEEDER_NAME: $DISCORD_FEEDER_NAME"
      # Inject the Discord integration in here so it doesn't have to worry about state management
			if [[ "$PF_DISCORD" == "ON" || "$PF_DISCORD" == "true" ]] && [[ "x$PF_DISCORD_WEBHOOKS" != "x" ]] && [[ "x$DISCORD_FEEDER_NAME" != "x" ]]
			then
				LOG "Planefence sending Discord notification"
      	python3 $PLANEFENCEDIR/send-discord-alert.py "$CSVLINE" "$AIRLINE"
      fi

			# And now, let's tweet!
			if [ "$TWEETON" == "yes" ]
			then
				# First, let's get a screenshot if there's one available!
				rm -f /tmp/snapshot.png
				TWIMG="false"
				if [[ "$GOTSNAP" == "true" ]]
				then
					# If the curl call succeeded, we have a snapshot.png file saved!
					TW_MEDIA_ID=$(twurl -X POST -H upload.twitter.com "/1.1/media/upload.json" -f /tmp/snapshot.png -F media | sed -n 's/.*\"media_id\":\([0-9]*\).*/\1/p')
					[[ "$TW_MEDIA_ID" > 0 ]] && TWIMG="true" || TW_MEDIA_ID=""
				fi

				[[ "$TWIMG" == "true" ]] && echo "Screenshot successfully retrieved at $SCREENSHOTURL for ${RECORD[0]}; Twitter Media ID=$TW_MEDIA_ID" || echo "Screenshot retrieval unsuccessful at $SCREENSHOTURL for ${RECORD[0]}"

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
