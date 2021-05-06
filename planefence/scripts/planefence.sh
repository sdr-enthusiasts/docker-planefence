#!/bin/bash
#set -x
# PLANEFENCE - a Bash shell script to render a HTML and CSV table with nearby aircraft
# based on socket30003
#
# Usage: ./planefence.sh
#
# Copyright 2020 Ramon F. Kolb - licensed under the terms and conditions
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
# Only change the variables below if you know what you are doing.

# We need to define the directory where the config file is located:

PLANEFENCEDIR=/usr/share/planefence

# Let's see if we must reload the parameters
if [[ -f "/run/planefence/last-config-change" ]] && [[ -f "/usr/share/planefence/persist/planefence.config" ]]
then
	# if... the date-last-changed of config file on the exposed volume ... is newer than the last time we read it ... then ... rerun the prep routine (which will update the last-config-change)
	[[ "$(stat -c %Y /usr/share/planefence/persist/planefence.config)" -gt "$(</run/planefence/last-config-change)" ]] && /usr/share/planefence/prep-planefence.sh
fi
# FENCEDATE will be the date [yymmdd] that we want to process PlaneFence for.
# The default value is 'today'.

if [ "$1" != "" ] && [ "$1" != "reset" ]
then # $1 contains the date for which we want to run PlaneFence
FENCEDATE=$(date --date="$1" '+%y%m%d')
else
	FENCEDATE=$(date --date="today" '+%y%m%d')
fi

[ "$TRACKSERVICE" != "flightaware" ] && TRACKSERVICE="flightaware"

# -----------------------------------------------------------------------------------
# Compare the original config file with the one in use, and call
#
#
# -----------------------------------------------------------------------------------
# Read the parameters from the config file
if [ -f "$PLANEFENCEDIR/planefence.conf" ]
then
	source "$PLANEFENCEDIR/planefence.conf"
else
	echo $PLANEFENCEDIR/planefence.conf is missing. We need it to run PlaneFence!
	exit 2
fi

# first get DISTANCE unit:
DISTUNIT="mi"
DISTCONV=1
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

# Figure out if NOISECAPT is active or not. REMOTENOISE contains the URL of the NoiseCapt container/server
# and is configured via the $PF_NOISECAPT variable in the .env file.
# Only if REMOTENOISE contains a URL and we can get the noise log file, we collect noise data
# replace wget by curl to save memory space. Was: [[ "x$REMOTENOISE" != "x" ]] && [[ "$(wget -q -O /tmp/noisecapt-$FENCEDATE.log $REMOTENOISE/noisecapt-$FENCEDATE.log ; echo $?)" == "0" ]] && NOISECAPT=1 || NOISECAPT=0
if [[ "x$REMOTENOISE" != "x" ]]
then
	if [[ "$(curl --fail -s $REMOTENOISE/noisecapt-$FENCEDATE.log > /tmp/noisecapt-$FENCEDATE.log; echo $?)" == "0" ]]
	then
		NOISECAPT=1
	else
		NOISECAPT=0
	fi
fi
#
#
# Determine the user visible longitude and latitude based on the "fudge" factor we need to add:
if [[ "$FUDGELOC" != "" ]]
then
	if [[ "$FUDGELOC" == "2" ]]
	then
		printf -v LON_VIS "%.2f" $LON
		printf -v LAT_VIS "%.2f" $LAT
	else
		# If $FUDGELOC != "" but also != "2", then assume it is "3"
		printf -v LON_VIS "%.3f" $LON
		printf -v LAT_VIS "%.3f" $LAT
	fi
	# clean up the strings:
else
	# let's not print more than 5 digits
	printf -v LON_VIS "%.5f" $LON
	printf -v LAT_VIS "%.5f" $LAT
fi
LON_VIS="$(sed 's/^00*\|00*$//g' <<< $LON_VIS)"	# strip any trailing zeros - "41.10" -> "41.1", or "41.00" -> "41."
LON_VIS="${LON_VIS%.}"		# If the last character is a ".", strip it - "41.1" -> "41.1" but "41." -> "41"
LAT_VIS="$(sed 's/^00*\|00*$//g' <<< $LAT_VIS)" 	# strip any trailing zeros - "41.10" -> "41.1", or "41.00" -> "41."
LAT_VIS="${LAT_VIS%.}" 		# If the last character is a ".", strip it - "41.1" -> "41.1" but "41." -> "41"

#
#
# Functions
#
# Function to write to the log
LOG ()
{
	if [ -n "$1" ]
	then
		IN="$1"
	else
		read IN # This reads a string from stdin and stores it in a variable called IN. This enables things like 'echo hello world > LOG'
	fi

	if [ "$VERBOSE" != "" ]
	then
		if [ "$LOGFILE" == "logger" ]
		then
			printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$IN" | logger
		else
			printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$IN" >> $LOGFILE
		fi
	fi
}
LOG "-----------------------------------------------------"
# Function to write an HTML table from a CSV file
LOG "Defining WRITEHTMLTABLE"
WRITEHTMLTABLE () {
	# -----------------------------------------
	# Next create an HTML table from the CSV file
	# Usage: WRITEHTMLTABLE INPUTFILE OUTPUTFILE
	LOG "WRITEHTMLTABLE $1 $2"

	# First, let's figure out if there are *any* Tweets or noise data
	# If so, we need to include those columns. If not, we can leave them out

	export HASTWEET="false"
	export HASNOISE="false"
	if [ -f "$1" ]
	then
		while read -r NEWLINE
		do
			IFS=, read -ra RECORD <<< "$NEWLINE"
			[[ "${RECORD[1]::1}" == "@" ]] && HASTWEET="true"
			[[ "${RECORD[8]}" != "" ]] && HASNOISE="true"
		done < "$1"
	else
		# Return silently without writing the table as there's no data to be written
		return 1
	fi

	# debug code: echo HASTWEET=$HASTWEET and HASNOISE=$HASNOISE

	# see if there is an airlinecodes.txt database

	[[ ! -f "$AIRLINECODES" ]] && AIRLINECODES=""

	# Now write the HTML table header

	cat <<EOF >>"$2"
	<!-- table border="1" class="planetable" -->
	<table border="1" class="js-sort-table">
	<tr>
	<th class="js-sort-number">No.</th>
	<th>Transponder ID</th>
	<th>Flight</th>
	$([[ "$AIRLINECODES" != "" ]] && echo "<th>Airline or Owner</th>")
	<th class="js-sort-date">Time First Seen</th>
	<th class="js-sort-date">Time Last Seen</th>
	<th class="js-sort-number">Min. Altitude</th>
	<th class="js-sort-number">Min. Distance</th>
EOF

	if [[ "$HASNOISE" == "true" ]]
	then
		# print the headers for the standard noise columns
		cat <<EOF >>"$2"
		<th class="js-sort-number">Loudness</th>
		<th class="js-sort-number">Peak RMS sound</th>
		<th class="js-sort-number">1 min avg</th>
		<th class="js-sort-number">5 min avg</th>
		<th class="js-sort-number">10 min avg</th>
		<th class="js-sort-number">1 hr avg</th>
EOF
		# If there are spectrograms for today, then also make a column for these:
		if (( $(ls -1 $OUTFILEDIR/noisecapt-spectro-$FENCEDATE*.png 2>/dev/null |wc -l) > 0 ))
		then
			printf "<th>Spectrogram</th>\n" >> "$2"
			SPECTROPRINT="true"
		else
			SPECTROPRINT="false"
		fi
	fi

	if [[ "$HASTWEET" == "true" ]]
	then
		# print a header for the Tweeted column
		printf "	<th>Tweeted</th>\n" >> "$2"
	fi
	printf "</tr>\n" >>"$2"

	# Now write the table
	COUNTER=1
	while read -r NEWLINE
	do
		[[ "$NEWLINE" == "" ]] && continue # skip empty lines
		[[ "${NEWVALUES::1}" == "#" ]] && continue #skip lines that start with a "#"

		IFS=, read -ra NEWVALUES <<< "$NEWLINE"

		# Do some prep work:
		# --------------------------------------------------------------
		# Step 1/5. Replace the map zoom by whatever $HEATMAPZOOM contains
		[[ -z "$HEATMAPZOOM" ]] && NEWVALUES[6]=$(sed 's|\(^.*&zoom=\)[0-9]*\(.*\)|\1'"$HEATMAPZOOM"'\2|' <<< "${NEWVALUES[6]}")

		# Step 2/5. If there is no flight number, insert the word "link"
		[[ "${NEWVALUES[1]#@}" == "" ]] && NEWVALUES[1]+="link"

		# Step 3/5. If there's noise data, get a background color:
		# (only when we are printing noise data, and there's actual data in this record)
		LOUDNESS=""
		if [[ "$HASNOISE" == "true" ]] && [[ "${NEWVALUES[9]}" != "" ]]
		then
			(( LOUDNESS = NEWVALUES[7] - NEWVALUES[11] ))
			BGCOLOR="$RED"
			((  LOUDNESS <= YELLOWLIMIT )) && BGCOLOR="$YELLOW"
			((  LOUDNESS <= GREENLIMIT )) && BGCOLOR="$GREEN"
		fi

		# Step 4/5. Get a noise graph
		# (only when we are printing noise data, and there's actual data in this record)
		if [[ "$HASNOISE" == "true" ]] && [[ "${NEWVALUES[7]}" != "" ]]
		then
			# First, the noise graph:
			# $NOISEGRAPHFILE is the full file path, NOISEGRAPHLINK is the subset with the filename only
			NOISEGRAPHFILE="$OUTFILEDIR"/"noisegraph-$(date -d "${NEWVALUES[2]}" +"%y%m%d-%H%M%S")-"${NEWVALUES[0]}".png"
			NOISEGRAPHLINK=${NOISEGRAPHFILE##*/}

			# If no graph already exists, create one:
			if [[ ! -f "$NOISEGRAPHFILE" ]]
			then
				# set some parameters for the graph:
				TITLE="Noise plot for ${NEWVALUES[1]#@} at ${NEWVALUES[3]}"
				STARTTIME=$(date -d "${NEWVALUES[2]}" +%s)
				ENDTIME=$(date -d "${NEWVALUES[3]}" +%s)
				# if the timeframe is less than 30 seconds, extend the ENDTIME to 30 seconds
				(( ENDTIME - STARTTIME < 30 )) && ENDTIME=$(( STARTTIME + 15 )) && STARTTIME=$(( STARTTIME - 15))
				NOWTIME=$(date +%s)
				# check if there are any noise samples
				if (( (NOWTIME - ENDTIME) > (ENDTIME - STARTTIME) )) && [[ -f "/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log" ]] && [[ "$(awk -v s=$STARTTIME -v e=$$ENDTIME '$1>=s && $1<=e' /usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log | wc -l)" -gt "0" ]]
				then
					#echo debug gnuplot start=$STARTTIME end=$ENDTIME infile=/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log outfile=$NOISEGRAPHFILE
					gnuplot -e "offset=$(echo "`date +%z` * 36" | bc); start="$STARTTIME"; end="$ENDTIME"; infile='/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log'; outfile='"$NOISEGRAPHFILE"'; plottitle='$TITLE'; margin=60" $PLANEFENCEDIR/noiseplot.gnuplot
				else
					NOISEGRAPHLINK=""
				fi
			fi
		fi

		# Step 5/5. Get a spectrogram
		# (only when we are printing noise data, and there's actual data in this record)
		if [[ "$HASNOISE" == "true" ]] && [[ "${NEWVALUES[7]}" != "" ]]
		then
			STARTTIME=$(date +%s -d "${NEWVALUES[2]}")
			ENDTIME=$(date +%s -d "${NEWVALUES[3]}")
			(( ENDTIME - STARTTIME < 30 )) && ENDTIME=$(( STARTTIME + 30 ))
			[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log" ]] && SPECTROFILE=noisecapt-spectro-$(date -d @`awk -F, -v a=$STARTTIME -v b=$ENDTIME 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log` +%y%m%d-%H%M%S).png || SPECTROFILE=""
			# if it has a weird date, discard it because it wont exist.
			# otherwise, go get it from the remote server:
			# debug code: echo $REMOTENOISE/$SPECTROFILE to $OUTFILEDIR/$SPECTROFILE
			[[ "$SPECTROFILE" == "noisecapt-spectro-691231-190000.png" ]] && SPECTROFILE="" || curl --fail -s $REMOTENOISE/$SPECTROFILE > $OUTFILEDIR/$SPECTROFILE
		else
			SPECTROFILE=""
		fi

		# --------------------------------------------------------------
		# Now, we're ready to start putting things in the table:

		printf "<tr>\n" >>"$2"
		printf "   <td>%s</td>\n" "$((COUNTER++))" >>"$2" # table index number
		printf "   <td>%s</td>\n" "${NEWVALUES[0]}" >>"$2" # ICAO
		printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td>\n" "$(tr -dc '[[:print:]]' <<< "${NEWVALUES[6]}")" "${NEWVALUES[1]#@}" >>"$2" # Flight number; strip "@" if there is any at the beginning of the record
		if [[ "$AIRLINECODES" != "" ]]
		then
			 [[ "${NEWVALUES[1]#@}" != "" ]] && [[ "${NEWVALUES[1]#@}" != "link" ]] && printf "   <td>%s</td>\n" "$(/usr/share/planefence/airlinename.sh ${NEWVALUES[1]#@} ${NEWVALUES[0]})" >>"$2" || printf "   <td></td>\n" >>"$2"
		fi
		printf "   <td>%s</td>\n" "${NEWVALUES[2]}" >>"$2" # time first seen
		printf "   <td>%s</td>\n" "${NEWVALUES[3]}" >>"$2" # time last seen
		printf "   <td>%s %s</td>\n" "${NEWVALUES[4]}" "$ALTUNIT" >>"$2" # min altitude
		printf "   <td>%s %s</td>\n" "${NEWVALUES[5]}" "$DISTUNIT" >>"$2" # min distance

		# Print the noise values if we have determined that there is data
		if [[ "$HASNOISE" == "true" ]]
		then
			# First the loudness field, which needs a color and a link to a noise graph:
			if [[ "$LOUDNESS" != "" ]]
			then
				if [[ "$NOISEGRAPHLINK" != "" ]]
				then
					printf "   <td style=\"background-color: %s\"><a href=\"%s\" target=\"_blank\">%s dB</a></td>\n" "$BGCOLOR" "$NOISEGRAPHLINK" "$LOUDNESS" >>"$2"
				else
					printf "   <td style=\"background-color: %s\">%s dB</td>\n" "$BGCOLOR" "$LOUDNESS" >>"$2"
				fi
			else
				printf "   <td></td>\n" >>"$2" # print an empty field
			fi

			for i in {7..11}
			do
				if [[ "${NEWVALUES[i]}" != "" ]]
				then
					printf "   <td>%s dBFS</td>\n" "${NEWVALUES[i]}" >>"$2" # print actual value with "dBFS" unit
				else
					printf "   <td></td>\n" >>"$2" # print an empty field
				fi
			done

			# print SpectroFile:
			if [[ "$SPECTROPRINT" == "true" ]]
			then
				if [[ -f "$OUTFILEDIR/$SPECTROFILE" ]]
				then
					printf "   <td><a href=\"%s\" target=\"_blank\">Spectrogram</a></td>\n" "$SPECTROFILE" >>"$2"
				else
					printf "   <td></td>\n" >>"$2"
				fi
			fi
		fi

		# If there is a tweet value, then provide info and link as available
		if [[ "$HASTWEET" == "true" ]]
		then
			# Was there a tweet?
			if [[ "${NEWVALUES[1]::1}" == "@" ]]
			then
				# Print "yes" and add a link if available
				if [[ "${NEWVALUES[-1]::13}" == "https://t.co/" ]]
				then
					printf "   <td><a href=\"%s\" target=\"_blank\">yes</a></td>\n" "$(tr -dc '[[:print:]]' <<< "${NEWVALUES[-1]}")"  >>"$2"
				else
					printf "   <td>yes</td>\n" >>"$2"
				fi
			else
				# If there were tweet, but not for this record, then print "no"
				printf "   <td>no</td>\n" >>"$2"
			fi
			# There were no tweets at all, so don't even print a field
		fi

		printf "</tr>\n" >>"$2"

	done < "$1"
	printf "</table>\n" >>"$2"
}

# Function to write the PlaneFence history file
LOG "Defining WRITEHTMLHISTORY"
WRITEHTMLHISTORY () {
	# -----------------------------------------
	# Write history file from directory
	# Usage: WRITEHTMLTABLE PLANEFENCEDIRECTORY OUTPUTFILE [standalone]
	LOG "WRITEHTMLHISTORY $1 $2 $3"
	if [ "$3" == "standalone" ]
	then
		printf "<html>\n<body>\n" >>"$2"
	fi

	cat <<EOF >>"$2"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details open>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Historical Data</summary>
	<p>Today: <a href="index.html" target="_top">html</a> - <a href="planefence-$FENCEDATE.csv" target="_top">csv</a>
EOF

	# loop through the existing files. Note - if you change the file format, make sure to yodate the arguments in the line
	# right below. Right now, it lists all files that have the planefence-20*.html format (planefence-200504.html, etc.), and then
	# picks the newest 7 (or whatever HISTTIME is set to), reverses the strings to capture the characters 6-11 from the right, which contain the date (200504)
	# and reverses the results back so we get only a list of dates in the format yymmdd.
	for d in $(ls -1 "$1"/planefence-??????.html | tail --lines=$((HISTTIME+1)) | head --lines=$HISTTIME | rev | cut -c6-11 | rev | sort -r)
	do
		printf " | %s" "$(date -d "$d" +%d-%b-%Y): " >> "$2"
		printf "<a href=\"%s\" target=\"_top\">html</a> - " "planefence-$(date -d "$d" +"%y%m%d").html" >> "$2"
		printf "<a href=\"%s\" target=\"_top\">csv</a>" "planefence-$(date -d "$d" +"%y%m%d").csv" >> "$2"
	done
	printf "</p>\n" >> "$2"
	printf "<p>Additional dates may be available by browsing to planefence-yymmdd.html in this directory.</p>" >> "$2"
	printf "</details>\n</article>\n</section>" >> "$2"

	# and print the footer:
	if [ "$3" == "standalone" ]
	then
		printf "</body>\n</html>\n" >>"$2"
	fi
}


# Here we go for real:
LOG "Initiating PlaneFence"
LOG "FENCEDATE=$FENCEDATE"
# First - if there's any command line argument, we need to do a full run discarding all cached items
if [ "$1" != "" ]
then
	rm "$TMPLINES"  2>/dev/null
	rm "$OUTFILEHTML"  2>/dev/null
	rm "$OUTFILECSV"  2>/dev/null
	rm $OUTFILEBASE-"$FENCEDATE"-table.html  2>/dev/null
	rm $OUTFILETMP  2>/dev/null
	rm $TMPDIR/dump1090-pf*  2>/dev/null
	LOG "File cache reset- doing full run for $FENCEDATE"
fi

# find out the number of lines previously read
if [ -f "$TMPLINES" ]
then
	read -r READLINES < "$TMPLINES"
else
	READLINES=0
fi

# delete some of the existing TMP files, so we don't leave any garbage around
# this is less relevant for today's file as it will be overwritten below, but this will
# also delete previous days' files that may have left behind
rm "$TMPLINES" 2>/dev/null
rm "$OUTFILETMP" 2>/dev/null

# before anything else, let's determine our current line count and write it back to the temp file
# We do this using 'wc -l', and then strip off all character starting at the first space
[ -f "$LOGFILEBASE$FENCEDATE.txt" ] && CURRCOUNT=$(wc -l $LOGFILEBASE$FENCEDATE.txt |cut -d ' ' -f 1) || CURRCOUNT=0

# Now write the $CURRCOUNT back to the TMP file for use next time PlaneFence is invoked:
echo "$CURRCOUNT" > "$TMPLINES"

LOG "Current run starts at line $READLINES of $CURRCOUNT"

# Now create a temp file with the latest logs
tail --lines=+$READLINES $LOGFILEBASE"$FENCEDATE".txt > $INFILETMP

# First, run planefence.py to create the CSV file:
LOG "Invoking planefence.py..."
$PLANEFENCEDIR/planefence.py --logfile=$INFILETMP --outfile=$OUTFILETMP --maxalt=$MAXALT --dist=$DIST --distunit=$DISTUNIT --lat=$LAT --lon=$LON $VERBOSE $CALCDIST --trackservice=$TRACKSERVICE 2>&1 | LOG
LOG "Returned from planefence.py..."

# Now we need to combine any double entries. This happens when a plane was in range during two consecutive Planefence runs
# A real simple solution could have been to use the Linux 'uniq' command, but that won't allow us to easily combine them

# Compare the last line of the previous CSV file with the first line of the new CSV file and combine them if needed
# Only do this is there are lines in both the original and the TMP csv files
if [ -f "$OUTFILETMP" ] && [ -f "$OUTFILECSV" ]
then
	while read -r newline
	do
		read -ra newrec <<< "$newline"
		if grep "^${newrec[0]}," "$OUTFILECSV" 2>&1 >/dev/null
		then
			# there's a ICAO match between the new record and the existing file
			# grab the last occurrence of the old record
			oldline="$(grep "^${newrec[0]}," "$OUTFILECSV" 2>/dev/null | tail -1)"
			IFS="," read -ra oldrec <<< "$oldline"
			if (( ${newrec[2]} - ${oldrec[3]} > COLLAPSEWITHIN ))
			then
				# we're outside the collapse window. Write the string to $OUTFILECSV
				echo "$newline" >> "$OUTFILECSV"
			else
				# we are inside the collapse windownand need to collapse the records.
				# Insert newrec's end time into oldrec. Do this ONLY for the line where the ICAO and the start time matches:
				sed -i "s|\(${oldrec[0]}\),\([A-Z0-9@-]*\),\(${oldrec[2]}\),\([0-9 /:]*\),\(.*\)|\1,\2,\3,${newrec[3]},\5|" "$OUTFILECSV"
				#           ^  ICAO    ^     ^ flt/tail ^   ^ starttime  ^   ^ endtime ^  ^rest^
			fi
		else
			# the ICAO fields did not match and we should write it to the database:
			echo "$newline" >> "$OUTFILECSV"
		fi
	done < "$OUTFILETMP"
else
	# there's potentially no OUTFILECSV. Move OUTFILETMP to OUTFILECSV if one exists
	[[ -f "$OUTFILETMP" ]] && mv -f "$OUTFILETMP" "$OUTFILECSV"
fi
rm -f "$OUTFILETMP"

# Now check if we need to add noise data to the csv file
if [[ "$NOISECAPT" == "1" ]]
then
	LOG "Invoking noise2fence!"
	$PLANEFENCEDIR/noise2fence.sh
else
	LOG "Info: Noise2Fence not enabled"
fi

#Dirty fix -- sometimes the CSV file needs fixing
$PLANEFENCEDIR/pf-fix.sh "$OUTFILECSV"


# Ignore list -- first clean up the list to ensure there are no empty lines
sed -i '/^$/d' "$IGNORELIST" 2>/dev/null
# now apply the filter
LINESFILTERED=$(grep -i -f "$IGNORELIST" "$OUTFILECSV" 2>/dev/null | wc -l)
if (( LINESFILTERED > 0 ))
then
	grep -v -i -f "$IGNORELIST" "$OUTFILECSV" > /tmp/pf-out.tmp
	mv -f /tmp/pf-out.tmp "$OUTFILECSV"
fi

# rewrite LINESFILTERED to file
[[ -f /run/planefence/filtered-$FENCEDATE ]] && read -r i < "/run/planefence/filtered-$FENCEDATE" || i=0
echo $((LINESFILTERED + i)) > "/run/planefence/filtered-$FENCEDATE"

# if IGNOREDUPES is not empty then remove duplicates
if [[ "$IGNOREDUPES" != "" ]]
then
	LINESFILTERED=$(awk -F',' 'seen[$1 gsub("/@/","", $2)]++' "$OUTFILECSV" 2>/dev/null | wc -l)
	if (( i>0 ))
	then
		# awk prints only the first instance of lines where fields 1 and 2 are the same
		awk -F',' '!seen[$1 gsub("/@/","", $2)]++' "$OUTFILECSV" > /tmp/pf-out.tmp
		mv -f /tmp/pf-out.tmp "$OUTFILECSV"
	fi
	# rewrite LINESFILTERED to file
	[[ -f /run/planefence/filtered-$FENCEDATE ]] && read -ra i < "/run/planefence/filtered-$FENCEDATE" || i=0
	echo $((LINESFILTERED + i)) > "/run/planefence/filtered-$FENCEDATE"

fi

# Now see is IGNORETIME is set. If so, we need to filter duplicates
# We will do it all in memory - load OUTFILECSV into an array, process the array, and write back to disk:
#if [[ -f "$OUTFILECSV" ]] && [[ "$IGNORETIME" -gt 0 ]]
#then
#
#		# read the entire OUTFILECSV into memory: line by line into 'l[]'
#		unset l
#		i=0
#		while IFS= read -r l[i]
#		do
#			(( i++ ))
#		done < "$OUTFILECSV"
#
#		# if the file was empty, stop processing
#
#		# $l[] contains all the OUTFILECSV lines. $i contains the total line count
#		# Loop through them in reverse order - skip the top one as the 1st entry is always unique
#		# Note - if the file is empty or has only 1 element, then the initial value of j (=i-1) = -1 or 0 and the
#		# loop will be skipped. This is intentional behavior.
#
#		for (( j=i-1; j>0; j-- ))
#		do
#				unset r
#				IFS=, read -ra r <<< "${l[j]}"
#				# $l now contains the entire line, $r contains the line in records. Start time is in r[2]. End time is in r[3]
#				# We now need to filter out any that are too close in time
#				echo r: ${r[@]}
#        echo rst: date -d "${r[2]}" +%s
#				rst=$(date -d "${r[2]}" +%s)	# get the record's start time in seconds (rst= r start time)
#				icao="${r[0]}"								# get the record's icao address
#				for (( k=j-1; k>=0; k-- ))
#				do
#						# if the line is empty, continue, else read in the line
#						[[ -z "${l[k]}" ]] && continue
#						unset s
#						IFS=, read -ra s <<< "${l[k]}"
#
#						# skip/continue if ICAO don't match
#						[[ "${s[0]}" != "$icao" ]] && continue
#
#						# stop processing this loop if the time diff is larger
#						tet=$(date -d "${s[3]}" +%s) 	# (tet= test's end time. Didn't want to use 'set')
#						echo tet: date -d "${s[3]}" +%s
#						(( rst - tet > IGNORETIME )) && break
#
#						# If we're still here, then the ICAO's match and the time is within the IGNORETIME boundaries.
#						# So we take action and empty out the entire string
#						l[k]=""
#				done
#		done
#
#		# Now, the array in memory contains the records, with empty lines for the dupes
#		# Write back all lines except for the empty ones:
#		rm -f /tmp/pf-out.tmp
#		for ((a=0; a<i; a++))
#		do
#		 	 [[ -z "${l[a]}" ]] && echo "${l[a]}" >> /tmp/pf-out.tmp
#		done
#	#	mv /tmp/pf-out.tmp "$OUTFILECSV"
#	mv -f /tmp/pf-out.tmp /usr/share/planefence/persist
#
#		# clean up some memory
#		unset l r s i j k a rst tet icao
#
#fi

#----end implementation of ignore list---#
# And see if we need to invoke PlaneTweet:
if [ ! -z "$PLANETWEET" ] && [ "$1" == "" ]
then
	LOG "Invoking PlaneTweet!"
	$PLANEFENCEDIR/planetweet.sh today "$DISTUNIT" "$ALTUNIT"
else
	[ "$1" != "" ] && LOG "Info: PlaneTweet not called because we're doing a manual full run" || LOG "Info: PlaneTweet not enabled"
fi

# And see if we need to run PLANEHEAT
if [ -f "$PLANEHEATSCRIPT" ] && [ -f "$OUTFILECSV" ]
then
	LOG "Invoking PlaneHeat!"
	$PLANEHEATSCRIPT
	LOG "Returned from PlaneHeat"
else
	LOG "Skipped PlaneHeat"
fi

# Now let's link to the latest Spectrogram, if one was generated for today:

if [ "$NOISECAPT" == "1" ]
then
	# get the latest spectrogram from the remote server
	curl --fail -s $REMOTENOISE/noisecapt-spectro-latest.png >$OUTFILEDIR/noisecapt-spectro-latest.png
	# was - wget now using curl to save disk space wget -q -O $OUTFILEDIR/noisecapt-spectro-latest.png $REMOTENOISE/noisecapt-spectro-latest.png >/dev/null 2>&1
	#scp -q $REMOTENOISE:$TMPDIR/noisecapt-spectro-latest.png $OUTFILEDIR/noisecapt-spectro-latest.png.tmp
	#mv -f $OUTFILEDIR/noisecapt-spectro-latest.png.tmp $OUTFILEDIR/noisecapt-spectro-latest.png

	# also create a noisegraph for the full day:
	rm -f /tmp/noiselog 2>/dev/null
	[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$(date -d "yesterday" +%y%m%d).log" ]] && cp -f /usr/share/planefence/persist/.internal/noisecapt-$(date -d "yesterday" +%y%m%d).log /tmp/noiselog
	[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$(date -d "today" +%y%m%d).log" ]] && cat /usr/share/planefence/persist/.internal/noisecapt-$(date -d "today" +%y%m%d).log >> /tmp/noiselog
	gnuplot -e "offset=$(echo "`date +%z` * 36" | bc); start="$(date -d "yesterday" +%s)"; end="$(date +%s)"; infile='/tmp/noiselog'; outfile='/usr/share/planefence/html/noiseplot-latest.jpg'; plottitle='Noise Plot over Last 24 Hours (End date = "$(date +%Y-%m-%d)")'; margin=60" $PLANEFENCEDIR/noiseplot.gnuplot
	rm -f /tmp/noiselog 2>/dev/null

elif (( $(find $TMPDIR/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | wc -l  ) > 0 ))
then
	ln -sf $(find $TMPDIR/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | tail -1) $OUTFILEDIR/noisecapt-spectro-latest.png
else
	rm -f $OUTFILEDIR/noisecapt-spectro-latest.png 2>/dev/null
fi

# If $PLANEALERT=on then lets call plane-alert to see if the new lines contain any planes of special interest:
[ "$PLANEALERT" == "ON" ] && ( LOG "Calling Plane-Alert as $PLALERTFILE $INFILETMP" ; $PLALERTFILE $INFILETMP )

# Next, we are going to print today's HTML file:
# Note - all text between 'cat' and 'EOF' is HTML code:

cat <<EOF >"$OUTFILEHTMTMP"
<!DOCTYPE html>
<html>
<!--
# You are taking an interest in this code! Great!
# I'm not a professional programmer, and your suggestions and contributions
# are always welcome. Join me at the GitHub link shown below, or via email
# at kx1t (at) amsat (dot) org.
#
# Copyright 2020, 2021 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence4docker/
#
# The package contains parts of, links to, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# OpenStreetMap: https://www.openstreetmap.org
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
-->
<head>
<!-- Global site tag (gtag.js) - Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=UA-171737107-1"></script>
<script>
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());

gtag('config', 'UA-171737107-1');
</script>
<script type="text/javascript" src="sort-table.js"></script>
<title>ADS-B 1090 MHz PlaneFence</title>
EOF

if [ -f "$PLANEHEATHTML" ]
then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<link rel="stylesheet" href="leaflet.css" />
	<script src="leaflet.js"></script>
EOF
fi

cat <<EOF >>"$OUTFILEHTMTMP"
<style>
body { font: 12px/1.4 "Helvetica Neue", Arial, sans-serif;
	   background-image: url('pf_background.jpg');
	   background-repeat: no-repeat;
	   background-attachment: fixed;
  	   background-size: cover;
     }
a { color: #0077ff; }
h1 {text-align: center}
h2 {text-align: center}
.planetable { border: 1; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; text-align: center }
.history { border: none; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; }
.footer{ border: none; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; text-align: center }
</style>
</head>

<body>


<h1>PlaneFence</h1>
<h2>Show aircraft in range of <a href="$MYURL" target="_top">$MY</a> ADS-B PiAware station for a specific day</h2>
<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
<article>
<details open>
<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Executive Summary</summary>
<ul>
<li>Last update: $(date +"%b %d, %Y %R:%S %Z")
<li>Maximum distance from <a href="https://www.openstreetmap.org/?mlat=$LAT_VIS&mlon=$LON_VIS#map=14/$LAT_VIS/$LON_VIS&layers=H" target=_blank>${LAT_VIS}&deg;N, ${LON_VIS}&deg;E</a>: $DIST $DISTUNIT

<li>Only aircraft below $(printf "%'.0d" $MAXALT) $ALTUNIT are reported
<li>Data extracted from $(printf "%'.0d" $CURRCOUNT) <a href="https://en.wikipedia.org/wiki/Automatic_dependent_surveillance_%E2%80%93_broadcast" target="_blank">ADS-B messages</a> received since midnight today

EOF
[[ "$FUDGELOC" != "" ]] && printf "<li> Please note that the reported station coordinates and the center of the circle on the heatmap are rounded for privacy protection. They do not reflect the exact location of the station.\n" >> "$OUTFILEHTMTMP"

[[ -f "/run/planefence/filtered-$FENCEDATE" ]] && [[ -f "$IGNORELIST" ]] && printf "<li> %d entries were filtered out today because of an <a href=\"ignorelist.txt\" target=\"_blank\">ignore list</a>\n" "$(</run/planefence/filtered-$FENCEDATE)" >> "$OUTFILEHTMTMP"

cat <<EOF >>"$OUTFILEHTMTMP"
</ul>
</details>
</article>
</section>

<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
<article>
<details>
<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Click on the triangle next to the header to show/collapse the section </summary>
</details>
</article>
</section>

<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
<article>
<details open>
<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Flights In Range Table</summary>
<ul>
EOF

[ "$TRACKSERVICE" == "flightaware" ] && printf "<li>Click on the flight number to see the full flight information/history (from <a href=http://www.flightaware.com\" target=\"_blank\">FlightAware</a>)" >> "$OUTFILEHTMTMP"
[ "$TRACKSERVICE" == "adsbexchange" ] && printf "<li>Click on the flight number to see the full flight information/history (from <a href=\"https://globe.adsbexchange.com/?lat=$LAT_VIS&lon=$LON_VIS&zoom=11.0\" target=\"_blank\">AdsbExchange</a>)" >> "$OUTFILEHTMTMP"

[ "$PLANETWEET" != "" ] && printf "<li>Click on the word &quot;yes&quot; in the <b>Tweeted</b> column to see the Tweet.\n<li>Note that tweets are issued after a slight delay\n" >> "$OUTFILEHTMTMP"
[ "$PLANETWEET" != "" ] && printf "<li>Get notified instantaneously of aircraft in range by following <a href=\"http://twitter.com/%s\" target=\"_blank\">@%s</a> on Twitter!\n" "$PLANETWEET" "$PLANETWEET" >> "$OUTFILEHTMTMP"
(( $(find $TMPDIR/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | wc -l  ) > 0 )) && printf "<li>Click on the word &quot;Spectrogram&quot; to see the audio spectrogram of the noisiest period while the aircraft was in range\n" >> "$OUTFILEHTMTMP"

printf "<li> Press the header of any of the columns to sort by that column.\n"  >> "$OUTFILEHTMTMP"
printf "</ul>\n"  >> "$OUTFILEHTMTMP"

WRITEHTMLTABLE "$OUTFILECSV" "$OUTFILEHTMTMP"

cat <<EOF >>"$OUTFILEHTMTMP"
</details>
</article>
</section>
EOF

# Write some extra text if NOISE data is present
if [[ "$HASNOISE" != "false" ]]
then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Notes on sound level data</summary>
	<ul>
	<li>This data is for informational purposes only and is of indicative value only. It was collected using a non-calibrated device under uncontrolled circumstances.
	<li>The data unit is &quot;dBFS&quot; (Decibels-Full Scale). 0 dBFS is the loudest sound the device can capture. Lower values, like -99 dBFS, mean very low noise. Higher values, like -10 dBFS, are very loud.
	<li>The system measures the <a href="https://en.wikipedia.org/wiki/Root_mean_square" target="_blank">RMS</a> of the sound level for contiguous periods of 5 seconds.
	<li>'Loudness' is the difference (in dB) between the Peak RMS Sound and the 1 hour average. It provides an indication of how much louder than normal it was when the aircraft flew over.
	<li>Loudness values of greater than $YELLOWLIMIT dB are in red. Values greater than $GREENLIMIT dB are in yellow.
	<li>'Peak RMS Sound' is the highest measured 5-seconds RMS value during the time the aircraft was in the coverage area.
	<li>The subsequent values are 1, 5, 10, and 60 minutes averages of these 5 second RMS measurements for the period leading up to the moment the aircraft left the coverage area.
	<li>One last, but important note: The reported sound levels are general outdoor ambient noise in a suburban environment. The system doesn't just capture airplane noise, but also trucks on a nearby highway, lawnmowers, children playing, people working on their projects, air conditioner noise, etc.
	<ul>
	</details>
	</article>
	</section>
	<hr/>
EOF
fi

# if $PLANEHEATHTML exists, then add the heatmap
if [ -f "$PLANEHEATHTML" ]
then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details open>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Heatmap</summary>
	<ul>
	<li>This heatmap reflects passing frequency and does not indicate perceived noise levels
	<li>The heatmap is limited to the coverage area of PlaneFence, for any aircraft listed in the table above
	$( [ -d "$OUTFILEDIR/../heatmap" ] && printf "<li>For a heatmap of all planes in range of the station, please click <a href=\"../heatmap\" target=\"_blank\">here</a>" )
	</ul>
EOF
	cat "$PLANEHEATHTML" >>"$OUTFILEHTMTMP"
	cat <<EOF >>"$OUTFILEHTMTMP"
	</details>
	</article>
	</section>
	<hr/>
EOF
fi

# If there's a latest spectrogram, show it
if [ -f "$OUTFILEDIR/noisecapt-spectro-latest.png" ]
then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details open>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Latest Spectrogram</summary>
	<ul>
	<li>Latest as of the time of generation of this page
	<li>For spectrograms related to overflying aircraft, see table above
	</ul>
	<a href="noisecapt-spectro-latest.png" target="_blank"><img src="noisecapt-spectro-latest.png"></a>
	$([[ -f "/usr/share/planefence/html/noiseplot-latest.jpg" ]] && echo "<a href=\"noiseplot-latest.jpg\" target=\"_blank\"><img src=\"noiseplot-latest.jpg\"></a>")
	</details>
	</section>
	<hr/>
EOF
fi


WRITEHTMLHISTORY "$OUTFILEDIR" "$OUTFILEHTMTMP"
LOG "Done writing history"

cat <<EOF >>"$OUTFILEHTMTMP"
<div class="footer">
<hr/>PlaneFence $VERSION is part of <a href="https://github.com/kx1t/docker-planefence" target="_blank">KX1T's PlaneFence Open Source Project</a>, available on GitHub. Support is available on the #Planefence channel of the SDR Enthusiasts Discord Server. Click the Discord icon below to join.
$(if [[ -f /root/.buildtime ]]; then printf " Build: %s" "$([[ -f /usr/share/planefence/branch ]] && cat /usr/share/planefence/branch || cat /root/.buildtime)"; fi)
<br/>&copy; Copyright 2020, 2021 by Ram&oacute;n F. Kolb. Please see <a href="attribution.txt" target="_blank">here</a> for attributions to all contributors and open source packages used.
<br/><a href="https://github.com/kx1t/docker-planefence/actions?query=workflow%3A%22Deploy+to+Docker+Hub%22" target="_blank"><img src="https://img.shields.io/github/workflow/status/kx1t/docker-planefence/Deploy%20to%20Docker%20Hub"></a>
<a href="https://hub.docker.com/r/k1xt/planefence" target="_blank"><img src="https://img.shields.io/docker/pulls/kx1t/planefence.svg"></a>
<a href="https://hub.docker.com/r/kx1t/planefence" target="_blank"><img src="https://img.shields.io/docker/image-size/kx1t/planefence/latest"></a>
<a href="https://discord.gg/VDT25xNZzV"><img src="https://img.shields.io/discord/734090820684349521" alt="discord"></a>
</div>
</body>
</html>
EOF

# Last thing we need to do, is repoint INDEX.HTML to today's file
pushd "$OUTFILEDIR" > /dev/null
mv -f "$OUTFILEHTMTMP" "$OUTFILEHTML"
ln -sf "${OUTFILEHTML##*/}" index.html
popd > /dev/null

# VERY last thing... ensure that the log doesn't overflow:
if [ "$VERBOSE" != "" ] && [ "$LOGFILE" != "" ] && [ "$LOGFILE" != "logger" ]
then
	sed -i -e :a -e '$q;N;8000,$D;ba' "$LOGFILE"
fi

# That's all
# This could probably have been done more elegantly. If you have changes to contribute, I'll be happy to consider them for addition
# to the GIT repository! --Ramon
LOG "Finishing PlaneFence... sayonara!"
