#!/bin/bash
# PLANE-ALERT - a Bash shell script to assess aircraft from a socket30003 render a HTML and CSV table with nearby aircraft
# based on socket30003
#
# Usage: ./plane-alert.sh <inputfile>
#
# Copyright 2021 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence/
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
	PLANEALERTDIR=/usr/share/plane-alert # the directory where this file and planefence.py are located
# -----------------------------------------------------------------------------------
#
# PLEASE EDIT PARAMETERS IN 'plane-alert.conf' BEFORE USING PLANE-ALERT !!!
#
# -----------------------------------------------------------------------------------
# Exit if there is no input file defined
	[ "$1" == "" ] && { echo "No inputfile detected. Syntax: $0 <inputfile>"; exit 1; } || INFILE="$1"
#	[ "$TESTING" == "true" ] && echo cmdline arg = \"$1\"
#
#
function cleanup
{
	# do some final clean-up before exiting - this funciton is called by a trap on receiving the EXIT signal
	rm -f ${OUTFILE%.*}*.diff >/dev/null 2>/dev/null
	rm -f ${OUTFILE%.*}*.old >/dev/null 2>/dev/null
	rm -f $TMPDIR/plalert*.tmp >/dev/null 2>/dev/null
	# restart planefence if it was active before we started:
	[ "$PFACTIVE" == "true" ] && sudo /bin/systemctl restart planefence
	[ "$TESTING" == "true" ] && echo 11. Finished.
}
#
# Now make sure we call 'cleanup' upon exit:
trap cleanup EXIT
#
#
# -----------------------------------------------------------------------------------
# Let's see if there is a CONF file that defines some of the parameters
	[ -f "$PLANEALERTDIR/plane-alert.conf" ] && source "$PLANEALERTDIR/plane-alert.conf"
# -----------------------------------------------------------------------------------
# Switch off planefence if it's running, except when plane-alert.sh was called from within PlaneFence
	if [ "$(/bin/systemctl is-active planefence 2>/dev/null)" == "active" ] && [ "$(ps -o comm= $PPID)" != "planefence.sh" ]
	then
		sudo /bin/systemctl stop planefence
		PFACTIVE=true
	else
		PFACTIVE=false
	fi
# -----------------------------------------------------------------------------------
#
# Now let's start
#
# First, let's get the file with planes to monitor.
# The file is in CSV format with this syntax:
# ICAO,TailNr,Owner,PlaneDescription
# for example:
# 42001,3CONM,GovernmentofEquatorialGuinea,DassaultFalcon900B
#
# We need to write this to a grep input file that consists simply of lines with "^icao"

	awk 'BEGIN { FS = "," } ; { print "^", $1 }' $PLANEFILE | tr -d '[:blank:]' > $TMPDIR/plalertgrep.tmp
	[ "$TESTING" == "true" ] && ( echo 1. $TMPDIR/plalertgrep.tmp contains $(cat $TMPDIR/plalertgrep.tmp|wc -l) lines )

# Now grep through the input file to see if we detect any planes

	grep -f $TMPDIR/plalertgrep.tmp "$INFILE"		`# Go through the input file and grep it agains plalertgrep.tmp` \
		| sort -t',' -k1,1 -k5,5  -u		`# Filter out only the unique combinations of fields 1 (ICAO) and 5 (date)` \
		> $TMPDIR/plalert.out.tmp			`# write the result to a tmp file`
	[ "$TESTING" == "true" ] && echo 2. $TMPDIR/plalert.out.tmp contains $(cat $TMPDIR/plalert.out.tmp | wc -l) lines

# If there's nothing in $TMPDIR/plalert.out.tmp then exit as there's nothing to be done...
	[ "$(cat $TMPDIR/plalert.out.tmp | wc -l)" == "0" ] && exit 0

# Create a backup of $OUTFILE so we can compare later on. Ignore any complaints if there's no original $OUTFILE
	for a in ${OUTFILE%.*}*.csv
	do
		cp -f "$a" "$a".old >/dev/null 2>/dev/null
	done

# Process the intermediate file:
	while read -r line
	do
		[ "$TESTING" == "true" ] && echo 3. Parsing line $line
		IFS=',' read -ra plalertplane <<< "$line"		# load a single line into an array called $plalertplane

		# Determine the real name of the output file and write it to $OUTWRITEFILE:
		[ "$OUTAPPDATE" == "true" ] && OUTWRITEFILE="${OUTFILE%.*}"-"$(date -d "${plalertplane[4]}" +%Y-%m-%d)".csv || OUTWRITEFILE="$OUTFILE"

		# Parse this into a single line with syntax ICAO,TailNr,Owner,PlaneDescription,date,time,lat,lon,callsign,adsbx_url
		printf "%s,%s,%s,%s,%s,%s,https://globe.adsbexchange.com/?icao=%s&showTrace=%s\n" \
				"$(grep "^${plalertplane[0]}" $PLANEFILE | head -1 | tr -d '[:cntrl:]')" `# First instance of the entire string from the template` \
				"${plalertplane[4]}"	`# Date first heard` \
				"${plalertplane[5]:0:8}"	`# Time first heard` \
				"${plalertplane[2]}"	`# Latitude` \
				"${plalertplane[3]}"	`# Longitude` \
				"${plalertplane[11]}"	`# callsign` \
				"${plalertplane[0]}"	`# ICAO for insertion into ADSBExchange link`\
				"$(date -d "${plalertplane[4]}" +%Y-%m-%d)"	`# reformatted date for insertion into ADSBExchange link`\
			>> "$OUTWRITEFILE"			`# Append this line to $OUTWRITEFILE`

		[ -f "$OUTWRITEFILE".old ] && cat "$OUTWRITEFILE" "$OUTWRITEFILE".old > $TMPDIR/plalert2.out.tmp || mv -f "$OUTWRITEFILE" $TMPDIR/plalert2.out.tmp
		sort -t',' -k5,5  -k1,1 -u -o "$OUTWRITEFILE" $TMPDIR/plalert2.out.tmp	# sort by field 5=date and only keep unique entries. Use an intermediate file so we dont overwrite the file we are reading from

	        [ "$TESTING" == "true" ] && ( echo 5. $OUTWRITEFILE contains $(wc -l < $OUTWRITEFILE) lines with this: ; cat $OUTWRITEFILE )

	done < $TMPDIR/plalert.out.tmp

# the log files are now done, but we want to figure out what is new
# so create some diff files

	# first remove any left over diff files
	rm -f ${OUTFILE%.*}*.diff >/dev/null 2>/dev/null

	# now create the new diff files:
	for a in ${OUTFILE%.*}*.csv
	do
		if [ -f "$a".old ]
		then
			diff "$a" "$a".old	`# determine the difference between the current and the old $OUTWRITEFILE` \
				| grep '^[<>]' 		`# get only the line that we really want; however, there are still some unwanted characters at the beginning` \
				| sed -e 's/^[< ]*//'   `# strip off the unwanted characters` \
			     >> "$a".diff	`# write to a file with ONLY the new lines added so we can do extra stuff with them`
		else
			cp "$a" "$a".diff
		fi
	done


# -----------------------------------------------------------------------------------
# Next, let's do some stuff with the newly acquired aircraft of interest
# First, loop through the new planes and tweet them. Initialize $ERRORCOUNT to capture the number of Tweet failures:
		ERRORCOUNT=0

		while read -r line
		do
			IFS=',' read -ra plalertplane <<< "$line"
			# check if we want to tweet them:
			if [ "$TWITTER" == "true" ] && [ -f "$TWURL" ] && [ -f "$TWIDFILE" ]
			then
				# First build the text of the tweet: reminder:
				# 0-ICAO,1-TailNr,2-Owner,3-PlaneDescription,4-date,5-time,6-lat,7-lon
				# 8-callsign,9-adsbx_url
				TWITTEXT="Plane of interest detected:\n"
				TWITTEXT+="ICAO: ${plalertplane[0]} Tail: ${plalertplane[1]} Flight: ${plalertplane[8]}\n"
	        	        TWITTEXT+="Owner: ${plalertplane[2]}\n"
                        	TWITTEXT+="Aircraft: ${plalertplane[3]}\n"
	                        TWITTEXT+="First heard: ${plalertplane[4]} ${plalertplane[5]}\n"
        	                TWITTEXT+="${plalertplane[9]}"

		        [ "$TESTING" == "true" ] && ( echo 6. TWITTEXT contains this: ; echo $TWITTEXT )
                        [ "$TESTING" == "true" ] && ( echo 7. Twitter IDs from $TWIDFILE )

			# Now loop through the Twitter IDs in $TWIDFILE and tweet the message:
			while IFS= read -r twitterid
			do
				# tweet and add the processed output to $result:
				if [ "$TESTING" == "true" ]
				then
					echo 8. Tweeting with the following data: recipient = \"$twitterid\" Tweet DM = \"$TWITTEXT\"
				else
					result=$(\
						$TWURL -A 'Content-type: application/json' -X POST /1.1/direct_messages/events/new.json -d '{"event": {"type": "message_create", "message_create": {"target": {"recipient_id": "'"$twitterid"'"}, "message_data": {"text": "'"$TWITTEXT"'"}}}}'\
 						        | jq '.errors[].message' 2>/dev/null) # parse the output through JQ and if there's an error, provide the text to $result
					[ "$result" != "" ] && ( echo "9. Tweet error: $result" ; echo Diagnostics: ; echo Twitter ID: $twitterid ; echo Text: $TWITTEXT ; (( ERRORCOUNT += 1 )) )
				fi
			done < "$TWIDFILE"
		else
			if [ "$TESTING" == "true" ]
			then
				echo 10. Skipped tweeting.
				echo \$TWITTER is $TWITTER and must be \"true\"
				[ -f "$TWURL" ] && echo $TWURL exists || echo $TWURL doesnt exist! Error!
				[ -f "$TWIDFILE" ] && echo $TWIDFILE exists || echo $TWIDFILE doesnt exist! Error!
			fi
		fi

	done < <(cat ${OUTFILE%.*}*.diff)
	(( ERRORCOUNT > 0 )) && echo There were $ERRORCOUNT tweet errors.

# Now everything is in place, let's update the website

	cp $PLANEALERTDIR/plane-alert.header.html $TMPDIR/plalert-index.tmp
	cat ${OUTFILE%.*}*.csv | tac > $WEBDIR/$CONCATLIST
	(( COUNTER = 1 ))
	while read -r line
	do
		IFS=',' read -ra plalertplane <<< "$line"
		if [ "${plalertplane[0]}" != "" ]
		then
			printf "%s\n" "<tr>" >> $TMPDIR/plalert-index.tmp
			printf "    %s%s%s\n" "<td>" "$((COUNTER++))" "</td>" >> $TMPDIR/plalert-index.tmp # column: Number
			printf "    %s%s%s\n" "<td>" "${plalertplane[0]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: ICAO
			printf "    %s%s%s\n" "<td>" "${plalertplane[1]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Tail
			printf "    %s%s%s\n" "<td>" "${plalertplane[2]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Owner
			printf "    %s%s%s\n" "<td>" "${plalertplane[3]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Plane Type
			printf "    %s%s%s\n" "<td>" "${plalertplane[4]} ${plalertplane[5]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Date Time
			printf "    %s%s%s\n" "<td>" "<a href=\"http://www.openstreetmap.org/?mlat=${plalertplane[6]}&mlon=${plalertplane[7]}&zoom=8\" target=\"_blank\">${plalertplane[6]}N, ${plalertplane[7]}E</a>" "</td>" >> $TMPDIR/plalert-index.tmp # column: LatN, LonE
			printf "    %s%s%s\n" "<td>" "${plalertplane[8]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Flight No
			printf "    %s%s%s\n" "<td>" "<a href=\"${plalertplane[9]}\" target=\"_blank\">ADSBExchange link</a>" "</td>" >> $TMPDIR/plalert-index.tmp # column: ADSBX link
			printf "%s\n" "</tr>" >> $TMPDIR/plalert-index.tmp
		fi
	done < $WEBDIR/$CONCATLIST
	cat $PLANEALERTDIR/plane-alert.footer.html >> $TMPDIR/plalert-index.tmp

	#Now the basics have been written, we need to replace some of the variables in the template with real data:
	sed -i "s/##NAME##/$NAME/g" $TMPDIR/plalert-index.tmp
	sed -i "s/##ADSBLINK##/$ADSBLINK/g" $TMPDIR/plalert-index.tmp
	sed -i "s/##LASTUPDATE##/$LASTUPDATE/g" $TMPDIR/plalert-index.tmp
	sed -i "s/##ALERTLIST##/$ALERTLIST/g" $TMPDIR/plalert-index.tmp
	sed -i "s/##CONCATLIST##/$CONCATLIST/g" $TMPDIR/plalert-index.tmp

	#Finally, put the temp index into its place:
	mv -f $TMPDIR/plalert-index.tmp $WEBDIR/index.html

