#!/bin/bash
# PLANETWEET - a Bash shell script to render heatmaps from modified sock30003
# heatmap data
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
        HEADR=("Transponder ID" "Flight" "Time in range" "Time out of range" "Min. Alt. (ft)" "Min. Dist. (miles)" "Link" "Loudness" "Peak Audio Level")
# CSVFILE termines which file name we need to look in. We're using the 'date' command to
# get a filename in the form of 'planefence-200504.csv' where 200504 is yymmdd
        TODAYCSV=$(date -d today +"planefence-%y%m%d.csv")
        YSTRDAYCSV=$(date -d yesterday +"planefence-%y%m%d.csv")
# TWURLPATH is where we can find TWURL. This only needs to be filled in if you can't get it
# as part of the default PATH:
        [ ! `which twurl` ] && TWURLPATH="/root/.rbenv/shims/"
# SLEEPTIME determine how long (in seconds) we wait after checking and (potentially) tweeting
# before we check again:
        SLEEPTIME=60
# If the VERBOSE variable is set to "1", then we'll write logs to LOGFILE.
# If you don't want logging, simply set  the VERBOSE=1 line below to VERBOSE=0
        VERBOSE=1
        LOGFILE=/tmp/planetweet.log
        TMPFILE=/tmp/planetweet.tmp
        TWEETON=yes

	CSVDIR=$OUTFILEDIR
        CSVNAMEBASE=$CSVDIR/planefence-
	CSVNAMEEXT=".csv"
	VERBOSE=1
	CSVTMP=/tmp/planetweet2-tmp.csv
# MINTIME is the minimum time we wait before sending a tweet
# to ensure that at least $MINTIME of audio collection (actually limited to the Planefence update runs in this period) to get a more accurste Loudness.
	MINTIME=200
# $ATTRIB contains the attribution line at the bottom of the tweet
        [[ "x$ATTRIB" == "x" ]] && ATTRIB="(C) 2021 KX1T - docker:kx1t/planefence"
# -----------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------
# Additional variables:
	CURRENT_PID=$$
	PROCESS_NAME=$(basename $0)
	VERSION=3.0_docker-planefence
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

CSVFILE=$CSVNAMEBASE$TWEETDATE$CSVNAMEEXT
#CSVFILE=/tmp/planefence-200526.csv
# make sure there's no stray TMP file around, so we can directly append
[ -f "$CSVTMP" ] && rm "$CSVTMP"

#Now iterate through the CSVFILE:
LOG "------------------------------"
LOG "Starting PLANETWEET"
LOG "CSVFILE=$CSVFILE"
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
		TIMEDIFF=$(( $(date +%s) - $(date -d "${RECORD[3]}" +%s) ))
		# Entries that are previously tweeted have "@" in front of the flight number
		# We will process those
		if [ "${RECORD[1]:0:1}" != "@" ] && [ $TIMEDIFF -gt $MINTIME ]
		then
			# Go get the data for the record:
			# Figure out the start and end time of the record, in seconds since epoch
                        # Create a Tweet with the first 6 fields, each of them followed by a Newline character
                        TWEET="${HEADR[0]}: ${RECORD[0]}%0A"
                        for i in {1..5}
                        do
                                TWEET+="${HEADR[i]}: ${RECORD[i]}%0A"
                        done

                        # If there is sound level data, then add a Loudness factor (peak RMS - 1 hr avg) to the tweet.
                        # There is more data we could tweet, but we're a bit restricted in real estate on twitter.
                        (( RECORD[7] < 0 )) && TWEET+="${HEADR[8]}: ${RECORD[7]} dBFS%0A${HEADR[7]}: $(( RECORD[7] - RECORD[11] )) dB%0A"


                        # Add attribution to the tweet:
                        TWEET+="%0A$ATTRIB%0A"

                        # Now add the last field without title or training Newline
                        # Reason: this is a URL that Twitter reinterprets and previews on the web
                        # Also, the Newline at the end tends to mess with Twurl

                        TWEET+="${RECORD[6]}"

			LOG "Assessing ${RECORD[0]}: ${RECORD[1]:0:1}; diff=$TIMEDIFF secs; Tweeting... msg body: $TWEET" 1

			# Before anything else, let's add the "tweeted" flag to the flight number:
			XX="@${RECORD[1]}"
			RECORD[1]=$XX


			# And now, let's tweet!
                        if [ "$TWEETON" == "yes" ]
                        then
				# send a tweet and read the link to the tweet into ${LINK[1]}
				LINK=$(echo `twurl -r "status=$TWEET" /1.1/statuses/update.json` | tee -a /tmp/tweets.log | jq '.entities."urls" | .[] | .url' | tr -d '\"')
                                LOG "LINK=$LINK"
                                echo "TWEET TEXT=$TWEET"
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
