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
# Exit if there is no input file defined. The input file contains the socket30003 logs that we are searching in
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
	rm -f /tmp/pa-diff.csv /tmp/pa-old.csv /tmp/pa-new.csv
	[ "$TESTING" == "true" ] && echo 11. Finished.
	if [[ "$TESTING" == "true" ]] && [[ "$hextext" != "" ]]
	then
		head -n -1 "$PLANEFILE" > /tmp/plf.tmp && mv -f /tmp/plf.tmp "$PLANEFILE"
	fi
}
#
# Now make sure we call 'cleanup' upon exit:
trap cleanup EXIT
#
#
# -----------------------------------------------------------------------------------
# Let's see if there is a CONF file that defines some of the parameters
[ -f "$PLANEALERTDIR/plane-alert.conf" ] && source "$PLANEALERTDIR/plane-alert.conf" || echo "Warning - cannot stat $PLANEALERTDIR/plane-alert.conf"
# -----------------------------------------------------------------------------------
#
# -----------------------------------------------------------------------------------
# Some testing code -- if $TESTING="true" then it's executed
# Mainly - add a random search item to the plane-alert db and add a plane into the CSV with the same hex ID we just added
if [[ "$TESTING" == "true" ]]
then
	# testhex is the letter "X" followed by the number of seconds since midnight
	# since we're filtering by day and hex ID, this combo is pretty much unique
	texthex="X"$(date -d "1970-01-01 UTC `date +%T`" +%s)
	echo $texthex,N0000,Plane Alert Test,SomePlane >> "$PLANEFILE"
	echo " Plane-alert testing under way..."
#else
#	echo " Plane-alert - not testing. \$TESTING=\"$TESTING\""
fi
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
# We need to write this to a grep input file that consists simply of lines with "^icao"

sed -n '/^[\^#]/!p' $PLANEFILE `# ignore any lines that start with "#"` \
| awk 'BEGIN { FS = "," } ; { print "^", $1 }' `# add "^" to the beginning of each line and only print ICAO` \
| tr -d '[:blank:]' > $TMPDIR/plalertgrep.tmp `# strip any blank characters and write to file`

[ "$TESTING" == "true" ] && echo 1. $TMPDIR/plalertgrep.tmp contains $(cat $TMPDIR/plalertgrep.tmp|wc -l) lines

# Now grep through the input file to see if we detect any planes

grep -f $TMPDIR/plalertgrep.tmp "$INFILE"		`# Go through the input file and grep it agains plalertgrep.tmp` \
| sort -t',' -k1,1 -k5,5  -u		`# Filter out only the unique combinations of fields 1 (ICAO) and 5 (date)` \
> $TMPDIR/plalert.out.tmp			`# write the result to a tmp file`
[ "$TESTING" == "true" ] && echo 2. $TMPDIR/plalert.out.tmp contains $(cat $TMPDIR/plalert.out.tmp | wc -l) lines


# Create a backup of $OUTFILE so we can compare later on.
touch "$OUTFILE" # ensure it always exists, even is there's no $OUTFILE
cp -f "$OUTFILE" /tmp/pa-old.csv

# Process the intermediate file:
while IFS= read -r line
do
	[ "$TESTING" == "true" ] && echo 3. Parsing line $line
	IFS=',' read -ra pa_record <<< "$line"		# load a single line into an array called $pa_record

	# Parse this into a single line with syntax ICAO,TailNr,Owner,PlaneDescription,date,time,lat,lon,callsign,adsbx_url
	printf "%s,%s,%s,%s,%s,%s,https://globe.adsbexchange.com/?icao=%s&showTrace=%s&zoom=%s\n" \
	"$(grep "^${pa_record[0]}" $PLANEFILE | head -1 | tr -d '[:cntrl:]')" `# First instance of the entire string from the template` \
	"${pa_record[4]}"	`# Date first heard` \
	"${pa_record[5]:0:8}"	`# Time first heard` \
	"${pa_record[2]}"	`# Latitude` \
	"${pa_record[3]}"	`# Longitude` \
	"${pa_record[11]}"	`# callsign` \
	"${pa_record[0]}"	`# ICAO for insertion into ADSBExchange link`\
	"$(date -d "${pa_record[4]}" +%Y-%m-%d)"	`# reformatted date for insertion into ADSBExchange link`\
	"$MAPZOOM"					  `# zoom factor of the map`\
	>> "$OUTFILE"			`# Append this line to $OUTWRITEFILE`

done < $TMPDIR/plalert.out.tmp
sort -t',' -k5,5  -k1,1 -u -o /tmp/pa-new.csv "$OUTFILE" 	# sort by field 5=date and only keep unique entries. Use an intermediate file so we dont overwrite the file we are reading from
mv -f /tmp/pa-new.csv "$OUTFILE"
# the log files are now done, but we want to figure out what is new
# so create some diff files
rm -f /tmp/pa-diff.csv
touch /tmp/pa-diff.csv
#  compare the new csv file ...to the old one...     only look at lines with '>' and then strip off '> ' from them
diff "$OUTFILE" /tmp/pa-old.csv 2>/dev/null  | grep '^[>]' | sed -e 's/^[> ]*//' >/tmp/pa-diff.csv

# if testing, insert the test item into the diff to trigger tweeting
if [[ "$TESTING" == "true" ]]
then
	echo $texthex,N0000,Plane Alert Test,SomePlane,$(date +"%Y/%m/%d"),$(date +"%H:%M:%S"),42.46458,-71.31513,,https://globe.adsbexchange.com/?icao="$texthex"\&zoom=13 >> /tmp/pa-diff.csv
	echo /tmp/pa-diff.csv:
	cat /tmp/pa-diff.csv
	echo var TWITTER: $TWITTER
	[[ -f "$TWIDFILE" ]] && echo var TWIDFILE $TWIDFILE exists || echo var TWIDFILE $TWIDFILE does not exist
fi
# -----------------------------------------------------------------------------------
# Next, let's do some stuff with the newly acquired aircraft of interest
# but only if there are actually newly acquired records
#
# Let's tweet them, if there are any, and if twitter is enabled and set up:
if [[ "$(cat /tmp/pa-diff.csv | wc -l)" != "0" ]] && [[ "$TWITTER" == "true" ]] && [[ -f "$TWIDFILE" ]]
then

	# First, loop through the new planes and tweet them. Initialize $ERRORCOUNT to capture the number of Tweet failures:
	ERRORCOUNT=0
	while IFS= read -r line
	do
		XX=$(echo -n $line | tr -d '[:cntrl:]')
		line=$XX
		unset pa_record

		IFS=',' read -ra pa_record <<< "$line"
		# First build the text of the tweet: reminder:
		# 0-ICAO,1-TailNr,2-Owner,3-PlaneDescription,4-date,5-time,6-lat,7-lon
		# 8-callsign,9-adsbx_url
		TWITTEXT="Aircraft of interest detected:\n"
		TWITTEXT+="ICAO: ${pa_record[0]} Tail: ${pa_record[1]} Flight: ${pa_record[8]}\n"
		TWITTEXT+="Owner: ${pa_record[2]}\n"
		TWITTEXT+="Aircraft: ${pa_record[3]}\n"
		TWITTEXT+="First heard: ${pa_record[4]} ${pa_record[5]}\n"
		TWITTEXT+="$(sed 's|/|\\/|g' <<< "${pa_record[9]}")"

		[ "$TESTING" == "true" ] && ( echo 6. TWITTEXT contains this: ; echo $TWITTEXT )
		[ "$TESTING" == "true" ] && ( echo 7. Twitter IDs from $TWIDFILE )

		# Now loop through the Twitter IDs in $TWIDFILE and tweet the message:
		while IFS= read -r twitterid
		do
			# tweet and add the processed output to $result:
			[[ "$TESTING" == "true" ]] && echo
			echo Tweeting with the following data: recipient = \"$twitterid\" Tweet DM = \"$TWITTEXT\"
			[[ "$twitterid" == "" ]] && continue
			rawresult=$($TWURL -A 'Content-type: application/json' -X POST /1.1/direct_messages/events/new.json -d '{"event": {"type": "message_create", "message_create": {"target": {"recipient_id": "'"$twitterid"'"}, "message_data": {"text": "'"$TWITTEXT"'"}}}}')
			processedresult=$(echo "$rawresult" | jq '.errors[].message' 2>/dev/null) # parse the output through JQ and if there's an error, provide the text to $result
			if [[ "$processedresult" != "" ]]
			then
				echo "9. Tweet error: $rawresult"
				echo "Diagnostics:"
				echo "Error: $processedresult"
				echo "Twitter ID: $twitterid"
				echo "Text: $TWITTEXT"
				(( ERRORCOUNT++ ))
			else
				echo "Plane-alert tweet for ${pa_record[0]} sent successfully to $twitterid"
			fi
		done < "$TWIDFILE"
	done < /tmp/pa-diff.csv
fi

(( ERRORCOUNT > 0 )) && echo There were $ERRORCOUNT tweet errors.

# Now everything is in place, let's update the website

cp -f $PLANEALERTDIR/plane-alert.header.html $TMPDIR/plalert-index.tmp
#cat ${OUTFILE%.*}*.csv | tac > $WEBDIR/$CONCATLIST

COUNTER=1
while read -r line
do
	IFS=',' read -ra pa_record <<< "$line"
	if [[ "${pa_record[0]}" != "" ]] && [[ "$(date -d "${pa_record[4]} ${pa_record[5]}" +%s)" -gt "$(date -d "$HISTTIME days ago" +%s)" ]]
	then
		printf "%s\n" "<tr>" >> $TMPDIR/plalert-index.tmp
		printf "    %s%s%s\n" "<td>" "$((COUNTER++))" "</td>" >> $TMPDIR/plalert-index.tmp # column: Number
		printf "    %s%s%s\n" "<td>" "${pa_record[0]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: ICAO
		printf "    %s%s%s\n" "<td>" "${pa_record[1]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Tail
		printf "    %s%s%s\n" "<td>" "${pa_record[2]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Owner
		printf "    %s%s%s\n" "<td>" "${pa_record[3]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Plane Type
		printf "    %s%s%s\n" "<td>" "${pa_record[4]} ${pa_record[5]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Date Time
		printf "    %s%s%s\n" "<td>" "<a href=\"http://www.openstreetmap.org/?mlat=${pa_record[6]}&mlon=${pa_record[7]}&zoom=$MAPZOOM\" target=\"_blank\">${pa_record[6]}N, ${pa_record[7]}E</a>" "</td>" >> $TMPDIR/plalert-index.tmp # column: LatN, LonE
		printf "    %s%s%s\n" "<td>" "${pa_record[8]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Flight No
		printf "    %s%s%s\n" "<td>" "<a href=\"${pa_record[9]}\" target=\"_blank\">ADSBExchange link</a>" "</td>" >> $TMPDIR/plalert-index.tmp # column: ADSBX link
		printf "%s\n" "</tr>" >> $TMPDIR/plalert-index.tmp
	fi
done < "$OUTFILE"
cat $PLANEALERTDIR/plane-alert.footer.html >> $TMPDIR/plalert-index.tmp

# Now the basics have been written, we need to replace some of the variables in the template with real data:
sed -i "s/##NAME##/$NAME/g" $TMPDIR/plalert-index.tmp
sed -i "s|##ADSBLINK##|$ADSBLINK|g" $TMPDIR/plalert-index.tmp
sed -i "s/##LASTUPDATE##/$LASTUPDATE/g" $TMPDIR/plalert-index.tmp
sed -i "s/##ALERTLIST##/$ALERTLIST/g" $TMPDIR/plalert-index.tmp
sed -i "s/##CONCATLIST##/$CONCATLIST/g" $TMPDIR/plalert-index.tmp
sed -i "s/##HISTTIME##/$HISTTIME/g" $TMPDIR/plalert-index.tmp
sed -i "s/##VERSION##/$(if [[ -f /root/.buildtime ]]; then printf "Build: "; cat /root/.buildtime; fi)/g" $TMPDIR/plalert-index.tmp

#Finally, put the temp index into its place:
mv -f $TMPDIR/plalert-index.tmp $WEBDIR/index.html
