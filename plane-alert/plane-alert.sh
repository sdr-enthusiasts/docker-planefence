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

sed -n 's|^\([0-9A-F]\{6\}\),.*|\^\1|p' "$PLANEFILE" > $TMPDIR/plalertgrep.tmp
#sed -n '/^[\^#]/!p' $PLANEFILE `# ignore any lines that start with "#"` \
#| awk 'BEGIN { FS = "," } ; { print "^", $1 }' `# add "^" to the beginning of each line and only print ICAO` \
#| tr -d '[:blank:]' > $TMPDIR/plalertgrep.tmp `# strip any blank characters and write to file`

[ "$TESTING" == "true" ] && echo 1. $TMPDIR/plalertgrep.tmp contains $(cat $TMPDIR/plalertgrep.tmp|wc -l) lines

# Now grep through the input file to see if we detect any planes
# note - we reverse the input file because later items have a higher chance to contain callsign and tail info
# the 'sort' command will put things back in order, but the '-u' option will make sure we keep the LAST item
# rather than the FIRST item
tac "$INFILE" | grep -f $TMPDIR/plalertgrep.tmp		`# Go through the input file and grep it agains plalertgrep.tmp` \
	| sort -t',' -k1,1 -k5,5  -u		`# Filter out only the unique combinations of fields 1 (ICAO) and 5 (date)` \
	> $TMPDIR/plalert.out.tmp			`# write the result to a tmp file`

# remove the SQUAWKS. We're not interested in them if they were picked up because of the list, and having them here
# will cause duplicate entries down the line
if [[ -f "$TMPDIR/plalert.out.tmp" ]]
then
	rm -f $TMPDIR/patmp
	awk -F "," 'OFS="," {$9="";print}' $TMPDIR/plalert.out.tmp > $TMPDIR/patmp
	mv -f $TMPDIR/patmp $TMPDIR/plalert.out.tmp
fi

[ "$TESTING" == "true" ] && echo 2. $TMPDIR/plalert.out.tmp contains $(cat $TMPDIR/plalert.out.tmp | wc -l) lines
# Now plalert.out.tmp contains SBS data


# echo xx1 ; cat $TMPDIR/plalert.out.tmp


# Let's figure out if we also need to find SQUAWKS
rm -f $TMPDIR/patmp
touch $TMPDIR/patmp
if [[ "$SQUAWKS" != "" ]]
then
		IFS="," read -ra sq <<< "$SQUAWKS"
		# add some zeros to the front, in case there are less than 4 chars
		sq=( "${sq[@]/#/0000}" )
		# Now go through $INFILE and look for each of the squawks. Put the SBS data in /tmp/patmp:
		for ((i=0; i<"${#sq[@]}"; i++))
		do
			sq[i]="${sq[i]: -4}"	# get the right-most 4 characters
			sq[i]="${sq[i]/x/.}"	# replace x with dot-wildcard
			awk -F "," "{if(\$9 ~ /${sq[i]}/){print}}" "$INFILE" >>$TMPDIR/patmp
		done

		# clean up /tmp/patmp
# echo xx2 ; cat $TMPDIR/patmp
		tac $TMPDIR/patmp | sort -t',' -k1,1 -k9,9 -u  >> $TMPDIR/plalert.out.tmp # sort this from the reverse of the file
# echo xx3 ; cat $TMPDIR/plalert.out.tmp
		sort -t',' -k5,5 -k6,6 $TMPDIR/plalert.out.tmp > $TMPDIR/patmp
# echo xx4 ; cat $TMPDIR/patmp
		mv -f $TMPDIR/patmp $TMPDIR/plalert.out.tmp
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
while IFS= read -r line
do
	[ "$TESTING" == "true" ] && echo 3. Parsing line $line
	IFS=',' read -ra pa_record <<< "$line"		# load a single line into an array called $pa_record

	# Skip the line if it's out of range
	awk "BEGIN{ exit (${pa_record[7]} < $RANGE) }" && continue

	# "$(grep "^${pa_record[0]}" $PLANEFILE | head -1 | tr -d '[:cntrl:]')" `# First instance of the entire string from the template` \
	# Parse this into a single line with syntax ICAO,TailNr,Owner,PlaneDescription,date,time,lat,lon,callsign,adsbx_url,squawk
    outrec="${pa_record[0]/ */}," # ICAO (stripped spaces)
	outrec+="$(awk -F "," -v a="${pa_record[0]}" '$1 == a {print $2;exit;}' "$PLANEFILE")," # tail
	outrec+="$(awk -F "," -v a="${pa_record[0]}" '$1 == a {print $3;exit;}' "$PLANEFILE")," # owner name
	outrec+="$(awk -F "," -v a="${pa_record[0]}" '$1 == a {print $4;exit;}' "$PLANEFILE")," # equipment
	outrec+="${pa_record[4]},"		# Date first heard
	outrec+="${pa_record[5]:0:8},"	# Time first heard
	outrec+="${pa_record[2]},"		# Latitude
	outrec+="${pa_record[3]},"		# Longitude
	outrec+="${pa_record[11]/ */}," # callsign or flt nr (stripped spaces)
	outrec+="https://globe.adsbexchange.com/?icao=${pa_record[0]}&showTrace=${pa_record[4]//\//-}&zoom=$MAPZOOM,"	# ICAO for insertion into ADSBExchange link

	# only add squawk if its in the list
	x=""
	for ((i=0; i<"${#sq[@]}"; i++))
	do
		x+=$(awk "{if(\$1 ~ /${sq[i]}/){print}}" <<< "${pa_record[8]}")
	done
	[[ "$x" != "" ]] && outrec+="${pa_record[8]}"		# squawk

	#Get a tail number if we don't have one
	if [[ "$(awk -F "," '{print $2'} <<< "$outrec")" == "" ]]
	then
		icao="$(awk -F "," '{print $1'} <<< "$outrec")"
		tail="$(grep -i -w "$icao" /run/planefence/icao2plane.txt 2>/dev/null | head -1 | awk -F "," '{print $2}')"
		[[ "$tail" != "" ]] && outrec="$(awk -F "," -v tail=$tail 'OFS="," {$2=tail;print}' <<< $outrec)"
	fi

	#Get an owner if there's none, we have a tail number and we are in the US
	if [[ "$(awk -F "," '{print $3'} <<< "$outrec")" == "" ]] && [[ "$(awk -F "," '{print $2'} <<< "$outrec")" != "" ]]
	then
		tail="$(awk -F "," '{print $2'} <<< "$outrec")"
		if [[ "${tail:0:1}" == "N" ]]
		then
			owner="$(/usr/share/planefence/airlinename.sh $tail)"
			[[ "$owner" != "" ]] && outrec="$(awk -F "," -v owner="$owner" 'OFS="," {$3=owner;print}' <<< $outrec)"
		fi
	fi

	echo "$outrec" >> "$OUTFILE"	# Append this line to $OUTWRITEFILE

done < $TMPDIR/plalert.out.tmp
# I like this better but the line below sorts nicer: awk -F',' '!seen[$1 $5)]++' "$OUTFILE" > /tmp/pa-new.csv
sort -t',' -k5,5  -k1,1 -k11,11 -u -o /tmp/pa-new.csv "$OUTFILE" 	# sort by field 5=date and only keep unique entries based on ICAO, date, and squawk. Use an intermediate file so we dont overwrite the file we are reading from
sort -t',' -k5,5  -k6,6 -o "$OUTFILE" /tmp/pa-new.csv		# sort once more by date and time but keep all entries
# the log files are now done, but we want to figure out what is new

# if testing, insert the test item into the diff to trigger tweeting
if [[ "$TESTING" == "true" ]]
then
	echo $texthex,N0000,Plane Alert Test,SomePlane,$(date +"%Y/%m/%d"),$(date +"%H:%M:%S"),42.46458,-71.31513,,https://globe.adsbexchange.com/?icao="$texthex"\&zoom=13 >> "$OUTFILE"
	echo /tmp/pa-diff.csv:
	cat /tmp/pa-diff.csv
	echo var TWITTER: $TWITTER
	[[ -f "$TWIDFILE" ]] && echo var TWIDFILE $TWIDFILE exists || echo var TWIDFILE $TWIDFILE does not exist
fi

# create some diff files
rm -f /tmp/pa-diff.csv
touch /tmp/pa-diff.csv
#  compare the new csv file to the old one and only print the added entries
comm -23 <(sort < "$OUTFILE") <(sort < /tmp/pa-old.csv ) >/tmp/pa-diff.csv

[[ "$(cat /tmp/pa-diff.csv | wc -l)" -gt "0" ]] && echo " Plane-Alert DIFF file has $(cat /tmp/pa-diff.csv | wc -l) lines and contains:"
cat /tmp/pa-diff.csv
# -----------------------------------------------------------------------------------
# Next, let's do some stuff with the newly acquired aircraft of interest
# but only if there are actually newly acquired records
#

# Read the header - we will need it a few times later:
IFS="," read -ra header < $PLANEFILE

# Let's tweet them, if there are any, and if twitter is enabled and set up:
if [[ "$(cat /tmp/pa-diff.csv | wc -l)" != "0" ]] && [[ "$TWITTER" == "true" ]] && [[ -f "$TWIDFILE" ]]
then
	# Loop through the new planes and tweet them. Initialize $ERRORCOUNT to capture the number of Tweet failures:
	ERRORCOUNT=0
	while IFS= read -r line
	do
		XX=$(echo -n $line | tr -d '[:cntrl:]')
		line=$XX

		unset pa_record
		IFS=',' read -ra pa_record <<< "$line"

		# add a hashtag to the item if needed:
		[[ "${header[0]:0:1}" == "$" ]] && pa_record[0]="#${pa_record[0]}" 	# ICAO field
		[[ "${header[1]:0:1}" == "$" ]] && [[ "${pa_record[1]}" != "" ]] && pa_record[1]="#${pa_record[1]//[[:space:]]/}" 	# tail field
		[[ "${header[2]:0:1}" == "$" ]] && [[ "${pa_record[2]}" != "" ]] && pa_record[2]="#${pa_record[2]//[[:space:]]/}" 	# owner field, stripped off spaces
		[[ "${header[3]:0:1}" == "$" ]] && [[ "${pa_record[2]}" != "" ]] && pa_record[3]="#${pa_record[3]}" # equipment field
		[[ "${header[1]:0:1}" == "$" ]] && [[ "${pa_record[8]}" != "" ]] && pa_record[8]="#${pa_record[8]//[[:space:]]/}" # flight nr field (connected to tail header)
		[[ "${pa_record[10]}" != "" ]] && pa_record[10]="#${pa_record[10]}" # 	# squawk

		# First build the text of the tweet: reminder:
		# 0-ICAO,1-TailNr,2-Owner,3-PlaneDescription,4-date,5-time,6-lat,7-lon
		# 8-callsign,9-adsbx_url,10-squawk

		TWITTEXT="Aircraft of interest detected:\n"
		TWITTEXT+="ICAO: ${pa_record[0]} "
		[[ "${pa_record[1]}" != "" ]] && TWITTEXT+="Tail: ${pa_record[1]} "
		[[ "${pa_record[8]}" != "" ]] && TWITTEXT+="Flight: ${pa_record[8]} "
		[[ "${pa_record[10]}" != "" ]] && TWITTEXT+="Squawk: ${pa_record[10]}"
		[[ "${pa_record[2]}" != "" ]] && TWITTEXT+="\nOwner: ${pa_record[2]/&/_}"
		TWITTEXT+="\nAircraft: ${pa_record[3]}\n"
		TWITTEXT+="First heard: ${pa_record[4]} ${pa_record[5]}\n"

		# Add any hashtags:
		for i in {4..10}
		do
			(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
			if [[ "${header[i]:0:1}" == "$" ]] || [[ "${header[i]:0:2}" == "#$" ]]
			then
				tag="$(awk -F "," -v a="${pa_record[0]#\#}" -v i="$((i+1))" '$1 == a {print $i;exit;}' "$PLANEFILE" | tr -dc '[:alnum:]')"
				[[ "$tag" != "" ]] && TWITTEXT+="#$tag "
			fi
		done

		TWITTEXT+="\n$(sed 's|/|\\/|g' <<< "${pa_record[9]}")"

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
				echo "Plane-alert Tweet error: $rawresult"
				echo "Diagnostics:"
				echo "Error: $processedresult"
				echo "Twitter ID: $twitterid"
				echo "Text: $TWITTEXT"
				(( ERRORCOUNT++ ))
			else
				echo "Plane-alert Tweet sent successfully to $twitterid for ${pa_record[0]} "
			fi
		done < "$TWIDFILE"
	done < /tmp/pa-diff.csv
fi

(( ERRORCOUNT > 0 )) && echo There were $ERRORCOUNT tweet errors.

# Now everything is in place, let's update the website

cp -f $PLANEALERTDIR/plane-alert.header.html $TMPDIR/plalert-index.tmp
#cat ${OUTFILE%.*}*.csv | tac > $WEBDIR/$CONCATLIST

SB="$(sed -n 's|^\s*SPORTSBADGER=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
if [[ "$SB" != "" ]]
then
	cat <<EOF >> $TMPDIR/plalert-index.tmp
<!-- special feature for @Sportsbadger only -->
<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
        <details>
            <summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Special Feature - only for @SportsBadger</summary>
			<h2>Per special request of @SportsBadger, here's the initial implementation of the "PlaneLatte" feature</h2>
            Unfortunately, the IFTTT integration between the home espresso machine and PlaneLatte is still under development and will probably never be implemented. In the meantime, feel free to
            pre-order your favo(u)rite drink at a Starbucks nearby. Future features will include a choice of Starbucks, Costa, and Pret-a-Manger, as well
            as the local New England favorite: Dunkin' Donuts.
            <ul>
                <li><a href="https://www.starbucks.com/menu/product/407/hot?parent=%2Fdrinks%2Fhot-coffees%2Flattes" target="_blank">Caffe Latte</a>
                <li><a href="https://www.starbucks.com/menu/product/409/hot?parent=%2Fdrinks%2Fhot-coffees%2Fcappuccinos" target="_blank">Cappuccino</a>
				<li><a href="https://www.starbucks.com/menu/product/462/iced?parent=%2Fdrinks%2Ficed-teas%2Ficed-herbal-teas" target="_blank">Iced Passion Tango&reg; Tea Lemonade</a>, handshaken with ice, lemonade and, of course, passion.
				<li>Additional beverages available upon request
			</ul>
		</details>
	</article>
</section>
EOF
fi

IFS="," read -ra header < $PLANEFILE

# figure out if there are squawks:
awk -F "," '$12 != "" {rc = 1} END {exit !rc}' $OUTFILE && sq="true" || sq="false"

# first add the fixed part of the header:
cat <<EOF >> $TMPDIR/plalert-index.tmp
<table border="1" class="js-sort-table">
<tr>
	<th class="js-sort-number">No.</th>
	<th>${header[0]#\#}</th> <!-- ICAO -->
	<th>${header[1]#\#}</th> <!-- tail -->
	<th>${header[2]#\#}</th> <!-- owner -->
	<th>${header[3]#\#}</th> <!-- equipment -->
	<th class="js-sort-date">Date/Time First Seen</th>
	<th class="js-sort-number">Lat/Lon First Seen</th>
	<th>Flight No.</th>
	$([[ "$sq" == "true" ]] && echo "<th>Squawk</th>")
	<!-- th>Flight Map</th -->
EOF

#print the variable headers:
for i in {4..10}
do
	(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
	[[ "${header[i]:0:1}" != "#" ]] && printf '<th>%s</th>  <!-- custom header %d -->\n' "${header[i]#$}" "$i" >> $TMPDIR/plalert-index.tmp
done
echo "</tr>" >> $TMPDIR/plalert-index.tmp


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
		# printf "    %s%s%s\n" "<td>" "<a href=\"http://www.openstreetmap.org/?mlat=${pa_record[6]}&mlon=${pa_record[7]}&zoom=$MAPZOOM\" target=\"_blank\">${pa_record[6]}N, ${pa_record[7]}E</a>" "</td>" >> $TMPDIR/plalert-index.tmp # column: LatN, LonE
		printf "    %s%s%s\n" "<td>" "<a href=\"${pa_record[9]}\" target=\"_blank\">${pa_record[6]}N, ${pa_record[7]}E</a>" "</td>" >> $TMPDIR/plalert-index.tmp # column: LatN, LonE with link to adsbexchange
		printf "    %s%s%s\n" "<td>" "${pa_record[8]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Flight No
		[[ "$sq" == "true" ]] && printf "    %s%s%s\n" "<td>" "${pa_record[10]}" "</td>" >> $TMPDIR/plalert-index.tmp # column: Squawk
		printf "    %s%s%s\n" "<!-- td>" "<a href=\"${pa_record[9]}\" target=\"_blank\">ADSBExchange link</a>" "</td -->" >> $TMPDIR/plalert-index.tmp # column: ADSBX link
		for i in {4..10}
		do
			(( i >= ${#header[@]} )) && break 	# don't print headers if they don't exist
			[[ "${header[i]:0:1}" != "#" ]] && printf '    <td>%s</td>  <!-- custom field %d -->\n' "$( (( j=i+1 )) && awk -F "," -v a="${pa_record[0]}" -v i="$j" '$1 == a {print $i;exit;}' "$PLANEFILE" | tr -dc "[:alnum:][:blank:]")" "$i" >> $TMPDIR/plalert-index.tmp
		done
		printf "%s\n" "</tr>" >> $TMPDIR/plalert-index.tmp
	fi
done < "$OUTFILE"
cat $PLANEALERTDIR/plane-alert.footer.html >> $TMPDIR/plalert-index.tmp

# Now the basics have been written, we need to replace some of the variables in the template with real data:
sed -i "s|##NAME##|$NAME|g" $TMPDIR/plalert-index.tmp
sed -i "s|##ADSBLINK##|$ADSBLINK|g" $TMPDIR/plalert-index.tmp
sed -i "s|##LASTUPDATE##|$LASTUPDATE|g" $TMPDIR/plalert-index.tmp
sed -i "s|##ALERTLIST##|$ALERTLIST|g" $TMPDIR/plalert-index.tmp
sed -i "s|##CONCATLIST##|$CONCATLIST|g" $TMPDIR/plalert-index.tmp
sed -i "s|##HISTTIME##|$HISTTIME|g" $TMPDIR/plalert-index.tmp
sed -i "s|##VERSION##|$(if [[ -f /root/.buildtime ]]; then printf "Build: "; cat /root/.buildtime; fi)|g" $TMPDIR/plalert-index.tmp


echo "<!-- ALERTLIST = $ALERTLIST -->" >> $TMPDIR/plalert-index.tmp

#Finally, put the temp index into its place:
mv -f $TMPDIR/plalert-index.tmp $WEBDIR/index.html
