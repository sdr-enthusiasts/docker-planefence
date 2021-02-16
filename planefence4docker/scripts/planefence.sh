#!/bin/bash
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
#
# The variables and program parameters have been moved to 'planefence.conf'. Please
# make changes there.
# -----------------------------------------------------------------------------------
# Only change the variables below if you know what you are doing.

# We need to define the directory where the config file is located:

PLANEFENCEDIR=/usr/share/planefence

# FENCEDATE will be the date [yymmdd] that we want to process PlaneFence for.
# The default value is 'today'.

if [ "$1" != "" ] && [ "$1" != "reset" ]
then # $1 contains the date for which we want to run PlaneFence
	FENCEDATE=$(date --date="$1" '+%y%m%d')
else
	FENCEDATE=$(date --date="today" '+%y%m%d')
fi

	[ "$TRACKSERVICE" == "" ] && TRACKSERVICE="flightaware"

CURRENT_PID=$$
PROCESS_NAME=$(basename $0)
# need to fix this --> systemctl is-active --quiet noisecapt && NOISECAPT=1 || NOISECAPT=0
NOISECAPT=0
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
	IFS=" =#" read -raa <<< $(grep -P '^(?=[\s]*+[^#])[^#]*(distanceunit)' $SOCKETCONFIG)
	case "${a[1]}" in
		nauticalmile)
			DISTUNIT="nm"
			[ "$DISPLAYUNIT" == "mi" ] && DISTCONV=0.868976
			[ "$DISPLAYUNIT" == "km" ] && DISTCONV=0.539957
			;;
		kilometer)
			DISTUNIT="km"
			[ "$DISPLAYUNIT" == "mi" ] && DISTCONV=0.621371
			;;
		mile)
			DISTUNIT="mi"
			[ "$DISPLAYUNIT" == "km" ] && DISTCONV=1.60934
			;;
		meter)
			DISTUNIT="m"
			[ "$DISPLAYUNIT" == "km" ] && DISTCONV=0.001000
			[ "$DISPLAYUNIT" == "mi" ] && DISTCONV=0.000621371
	esac
fi

# get ALTITUDE unit:
ALTUNIT="feet"
if [ "$SOCKETCONFIG" != "" ]
then
        IFS=" =#" read -raa <<< $(grep -P '^(?=[\s]*+[^#])[^#]*(altitudeunit)' $SOCKETCONFIG)
        case "${a[1]}" in
                feet)
                        ALTUNIT="ft"
                        ;;
                meter)
                        ALTUNIT="m"
        esac
fi

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
	# Usage: WRITEHTMLTABLE INPUTFILE OUTPUTFILE [standalone]
	LOG "WRITEHTMLTABLE $1 $2 $3"

	# figure out if there is NOISE data in the CSV file.
        MAXFIELDS=0
        TWEETCOL=1 # remember, in BASH, "0" is "true" and "!0" is "false"
        NOISECOL=1

	if [ -f "$1" ]
	then
		while read -r NEWLINE
		do
			IFS=, read -ra RECORD <<< "$NEWLINE"
			if (( ${#RECORD[*]} > MAXFIELDS ))
			then
				MAXFIELDS=${#RECORD[*]}
				(( MAXFIELDS > 10 )) && NOISECOL=0
			fi

			# check if there is tweeted data in the CSV file
			[ "${RECORD[1]:0:1}" == "@" ] && TWEETCOL=0

		done < "$1"
	fi

	if [ "$3" == "standalone" ]
	then
		printf "<html>\n<body>\n" >>"$2"
	fi

	cat <<EOF >>"$2"
	<!-- table border="1" class="planetable" -->
	<table border="1" class="js-sort-table">
	<tr>
	<th class="js-sort-number">No.</th>
	<th>Transponder ID</th>
	<th>Flight</th>
	<th class="js-sort-date">Time First Seen</th>
	<th class="js-sort-date">Time Last Seen</th>
	<th class="js-sort-number">Min. Altitude</th>
	<th class="js-sort-number">Min. Distance</th>
EOF
	if (( NOISECOL == true ))
	then
		cat <<EOF >>"$2"
		<th class="js-sort-number">Loudness</th>
		<th class="js-sort-number">Peak RMS sound</th>
		<th class="js-sort-number">1 min avg</th>
		<th class="js-sort-number">5 min avg</th>
		<th class="js-sort-number">10 min avg</th>
		<th class="js-sort-number">1 hr avg</th>
EOF
		if (( TWEETCOL == true ))
		then
			# there's Twitter info in field 12
			printf "<th>Tweeted</th>" >> "$2"
			LOG "Number of fields in CSV is $MAXFIELDS. Adding NoiseCapt and Tweeted table headers..."
		else
			LOG "Number of fields in CSV is $MAXFIELDS. Adding NoiseCapt table headers..."
		fi

		if (( $(ls -1 $OUTFILEDIR/noisecapt-spectro-$FENCEDATE*.png 2>/dev/null |wc -l) > 0 ))
		then
			printf "<th>Spectrogram</th>" >> "$2"
		fi

	else
		LOG "Number of fields in CSV is $MAXFIELDS. Not adding NoiseCapt table headers!"
	fi

	printf "</tr>\n" >>"$2"

	# Now write the table
	COUNTER=0
	if [ -f "$1" ]
	then
	  while read -r NEWLINE
	  do
	    if [ "$NEWLINE" != "" ]
	    then
		(( COUNTER = COUNTER + 1 ))
		IFS=, read -ra NEWVALUES <<< "$NEWLINE"
		# only write the row if the first field contains 6 characters (otherwise treat it as a header, and skip)
		if [ "${#NEWVALUES[0]}" == "6" ]
		then
			printf "<tr>\n" >>"$2"
			printf "<td>%s</td>" "$COUNTER" >>"$2" # table index number
			printf "<td>%s</td>\n" "${NEWVALUES[0]}" >>"$2" # ICAO Hex ID

			# if the flight number start with \@ then strip that in the HTML representation
			# (\@ is written as the first character of the flight number by PlaneTweet if it has already tweeted the record)
                        # Also, if the flight number is absent but $TRACKSERVICE==adsbexchange then insert a link after all
                        
			if  { [ "${NEWVALUES[1]}" == "@" ] || [ "${NEWVALUES[1]}" == "" ]; } && [ "$TRACKSERVICE" == "adsbexchange" ]
			then     date -u -d @$(date  -d "2021/02/14 22:01:37" +%s) +%Y-%m-%d
                                # printf "<td><a href=\"http://globe.adsbexchange.com/?icao=%s&showTrace=%s\" target=\"_blank\">link</a></td>\n" "${NEWVALUES[0]}" "$(date -d ${NEWVALUES[2]::10} +%Y-%m-%d)" >> "$2"
                                printf "<td><a href=\"http://globe.adsbexchange.com/?icao=%s&showTrace=%s\" target=\"_blank\">link</a></td>\n" "${NEWVALUES[0]}" "$(date -u -d @`date -d \"${NEWVALUES[2]}\" +%s` +%Y-%m-%d)" >> "$2"
			elif [ "${NEWVALUES[1]:0:1}" == "@" ]
                        then
				printf "<td><a href=\"%s\" target=\"_blank\">%s</a></td>\n" "${NEWVALUES[6]}" "${NEWVALUES[1]:1}" >> "$2"
                        else
				printf "<td><a href=\"%s\" target=\"_blank\">%s</a></td>\n" "${NEWVALUES[6]}" "${NEWVALUES[1]}" >> "$2"
			fi

			printf "<td>%s</td>\n" "${NEWVALUES[2]}" >>"$2" # time first seen
			printf "<td>%s</td>\n" "${NEWVALUES[3]}" >>"$2" # time last seen
			printf "<td>%s %s</td>\n" "${NEWVALUES[4]}" "$ALTUNIT" >>"$2" # min altitude

			if [ "$DISTUNIT" != "$DISPLAYUNIT" ]
			then
				printf "<td>%.2f %s</td>\n" "$(echo "${NEWVALUES[5]} * $DISTCONV" | bc -l)" "$DISPLAYUNIT" >>"$2" # min distance
			else
				printf "<td>%s %s</td>\n" "${NEWVALUES[5]}" "$DISTUNIT" >>"$2" # min distance
			fi

			# If MAXFIELDS>10 then there is definitely audio information.
			if (( NOISECOL == true ))
			then
				# determine cell bgcolor
				(( LOUDNESS = NEWVALUES[7] - NEWVALUES[11] ))
				BGCOLOR="$RED"
				((  LOUDNESS <= YELLOWLIMIT )) && BGCOLOR="$YELLOW"
				((  LOUDNESS <= GREENLIMIT )) && BGCOLOR="$GREEN"

				NOISEGRAPHLINK="$NOISEGRAPHBASE-$(date -d "${NEWVALUES[2]}" +%H%M%S)-"${NEWVALUES[0]}".png"
				NOISEGRAPHFILE="$OUTFILEDIR"/"$NOISEGRAPHLINK"
				[ "${NEWVALUES[1]:0:1}" == "@" ] && TITLE="Noise plot for ${NEWVALUES[1]:1} at ${NEWVALUES[3]}" || TITLE="Noise plot for ${NEWVALUES[1]} at ${NEWVALUES[3]}"

				STARTTIME=$(date +%s -d "${NEWVALUES[2]}")
				ENDTIME=$(date +%s -d "${NEWVALUES[3]}")
				# if the timeframe is less than 15 seconds, extend the ENDTIME to 30 seconds
				(( ENDTIME - STARTTIME < 30 )) && ENDTIME=$(( STARTTIME + 30 ))

				LOG "SpectroFile between $STARTTIME and $ENDTIME"

				# determine the name of a potential spectrogram file
				SPECTROFILE=noisecapt-spectro-$(date -d @`awk -F, -v a=$STARTTIME -v b=$ENDTIME 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /tmp/noisecapt-$FENCEDATE.log` +%y%m%d-%H%M%S).png
				LOG "SPECTROFILE (before copying) is $TMPDIR/$SPECTROFILE"

				if [ "$REMOTENOISE" != "" ]
				then
					# The SpectroFile is located on a remote machine. Go get it there
					scp "$REMOTENOISE:$TMPDIR/$SPECTROFILE" "$OUTFILEDIR/$SPECTROFILE".tmp
					mv -f "$OUTFILEDIR/$SPECTROFILE".tmp "$OUTFILEDIR/$SPECTROFILE"
					LOG "Copied SpectroFile from remote location $REMOTENOISE:$TMPDIR/$SPECTROFILE to $OUTFILEDIR/$SPECTROFILE"
				fi

				if [ -f "$TMPDIR/$SPECTROFILE" ] && [ ! -f "$OUTFILEDIR/$SPECTROFILE" ]
				then
					cp -f "$TMPDIR/$SPECTROFILE" "$OUTFILEDIR/$SPECTROFILE"
					LOG "Copied SpectroFile from $TMPDIR/$SPECTROFILE to $OUTFILEDIR/$SPECTROFILE"

				else
					[ ! -f "$OUTFILEDIR/$SPECTROFILE" ] && LOG "Didnt (local) copy Spectrofile - doesnt exist at origin"
					[ -f "$TMPDIR/$SPECTROFILE" ] && LOG "Didnt (local) copy SpectroFile - already exists at $OUTFILEDIR/$SPECTROFILE"
				fi

				# generate noisegraph if it doesnt already exist
				if [ ! -f "$NOISEGRAPHFILE" ] && [ $(( $(date +%s) - $(date -d "${NEWVALUES[3]}" +%s) )) -gt 300 ]
				then
					LOG "Invoking GnuPlot with START=$STARTTIME END=$ENDTIME"
					gnuplot -e "offset=$(echo "`date +%z` * 36" | bc); start=$STARTTIME; end=$ENDTIME; infile='/tmp/noisecapt-$FENCEDATE.log'; outfile='"$NOISEGRAPHFILE"'; plottitle='$TITLE'; margin=60" $PLANEFENCEDIR/noiseplot.gnuplot
					LOG "SPECTROFILE=$SPECTROFILE"
				else
					LOG "Didnt write graph. Reason:"
					[ -f "$NOISEGRAPHFILE" ] && LOG "$NOISEGRAPHFILE exists" || LOG "$NOISEGRAPHFILE doesn't exist"
					LOG "Timediff is $(( $(date +%s) - $(date -d "${NEWVALUES[3]}" +%s) )) "
				fi


				# print Noise Values
				if [ -f "$NOISEGRAPHFILE" ]
				then
					printf "<td style=\"background-color: %s\"><a href=\"%s\" target=\"_blank\">%s dB</a></td>\n" "$BGCOLOR" "$NOISEGRAPHLINK" "$LOUDNESS" >>"$2"
				else
					printf "<td style=\"background-color: %s\">%s dB</td>\n" "$BGCOLOR" "$LOUDNESS" >>"$2"
				fi

				for i in {7..11}
				do
					printf "<td>%s dBFS</td>\n" "${NEWVALUES[i]}" >>"$2"
				done

				if [ "${NEWVALUES[1]:0:1}" == "@" ]
				then
					# a tweet was sent. If there is info in field 12, then put a link, otherwise simple say "yes"
					if  [ "${NEWVALUES[12]}" != "" ]
					then
						# there's tweet info in this field
						printf "<td><a href=\"%s\" target=\"_new\">yes</a></td>\n" "$(echo ${NEWVALUES[12]} | tr -d '[:cntrl:]')" >> "$2"
					else
						printf "<td>yes</td>\n" >> "$2"
					fi
                                elif (( TWEETCOL == true ))
                                then
                                        printf "<td></td>\n" >> "$2"
				fi
			else
				# else there was no audio information.
				# figure out if there's tweet information:
                                if [ "${NEWVALUES[1]:0:1}" == "@" ]
                                then
                                        # a tweet was sent. If there is info in field 7, then put a link, otherwise simple say "yes"
                                        if  [ "${NEWVALUES[7]}" != "" ]
                                        then
                                                # there's tweet info in this field
						printf "<td><a href=\"%s\" target=\"_new\">yes</a></td>\n" "$(echo ${NEWVALUES[7]} | tr -d '[:cntrl:]')" >> "$2"

                                        else
                                                printf "<td>yes</td>\n" >> "$2"
                                        fi
				elif (( TWEETCOL == true ))
				then
					printf "<td></td>\n" >> "$2"
                                fi
			fi

			if [ -f "$OUTFILEDIR/$SPECTROFILE" ]
			then
				printf "<td><A href=\"%s\" target=\"_new\">Spectrogram</a></td>\n" "$SPECTROFILE" >>"$2"
				LOG "SpectroFile exists, added link to table"
			#else
				#LOG "SpectroFile doesnt exist, no link added to table"
			fi

			printf "</tr>\n" >>"$2"
		fi
	    fi
	  done < "$1" # while read -r NEWLINE
	fi
	printf "</table>\n" >>"$2"
	if [ "$COUNTER" == "0" ]
	then
		printf "<p class=\"history\">No flights in range!</p>" >>"$2"
	fi
        if [ "$3" == "standalone" ]
        then
                printf "</body>\n</html>\n" >>"$2"
        fi
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
	# Read the last line of $OUTFILECSV and compare it to the top line of $OUTFILETMP
	LASTLINE=$(tail -n 1 "$OUTFILECSV")
	FIRSTLINE=$(head -n 1 "$OUTFILETMP")

	[ -f "$OUTFILECSV" ] && LOG "Before: CSV file has $(wc -l "$OUTFILECSV" |cut -d ' ' -f 1) lines" || LOG "Before: CSV file doesn't exist"
	LOG "Before: Last line of CSV file: $LASTLINE"
        LOG "Before: New PlaneFence file has $(wc -l "$OUTFILETMP" |cut -d ' ' -f 1) lines"
        LOG "Before: First line of PF file: $FIRSTLINE"

	# Convert these into arrays so we can compare:
	unset $LASTVALUES
	unset $FIRSTVALUES
	IFS=, read -ra LASTVALUES <<< "$LASTLINE"
	IFS=, read -ra FIRSTVALUES <<< "$FIRSTLINE"

	# Now, if the ICAO of the two lines are the same, then combine and write the files:
	if [ "${LASTVALUES[0]}" == "${FIRSTVALUES[0]}" ]
	then
		LOG "Oldest new plane = newest old plane. Fixing..."
		# remove the first line form the $OUTFILETMP:
		tail --lines=+2 "$OUTFILETMP" > "$TMPDIR/pf-tmpfile" && mv "$TMPDIR/pf-tmpfile" "$OUTFILETMP"
		LOG "Adjusted linecount of New PF file to: $(wc -l $OUTFILETMP |cut -d ' ' -f 1) lines"
		# write all but the last line of $OUTFILECSV:
		head --lines=-1 "$OUTFILECSV" > "$TMPDIR/pf-tmpfile" && mv "$TMPDIR/pf-tmpfile" "$OUTFILECSV"

		# write the updated line:
		printf "%s," "${LASTVALUES[0]}" >> "$OUTFILECSV"
		printf "%s," "${LASTVALUES[1]}" >> "$OUTFILECSV"

		# print the earliest start time:
		if [ "$(date -d "${LASTVALUES[2]}" +"%s")" -lt "$(date -d "${FIRSTVALUES[2]}" +"%s")" ]
		then
			printf "%s," "${LASTVALUES[2]}" >> "$OUTFILECSV"
		else
			printf "%s," "${FIRSTVALUES[2]}" >> "$OUTFILECSV"
		fi

		# print the latest end date:
                if [ "$(date -d "${FIRSTVALUES[3]}" +"%s")" -gt "$(date -d "${LASTVALUES[3]}" +"%s")" ]
                then
                        printf "%s," "${FIRSTVALUES[3]}" >> "$OUTFILECSV"
                else
                        printf "%s," "${LASTVALUES[3]}" >> "$OUTFILECSV"
                fi

                # print the lowest altitude:
                if [ "${LASTVALUES[4]}" -lt "${FIRSTVALUES[4]}" ]
                then
                        printf "%s," "${LASTVALUES[4]}" >> "$OUTFILECSV"
                else
                        printf "%s," "${FIRSTVALUES[4]}" >> "$OUTFILECSV"
                fi

                # print the lowest distance. A bit tricky because altitude isn't an integer:
                if [ "$(bc <<< "${LASTVALUES[5]} < ${FIRSTVALUES[5]}")" -eq 1 ]
                then
                        printf "%s," "${LASTVALUES[5]}" >> "$OUTFILECSV"
                else
                        printf "%s," "${FIRSTVALUES[5]}" >> "$OUTFILECSV"
                fi

		# print the last line (link):
		printf "%s\n" "${LASTVALUES[6]}" >> "$OUTFILECSV"
	else
		LOG "No match, continuing..."
	fi
else
	[ -f "$OUTFILECSV" ] && LOG "Before: CSV file has $(wc -l "$OUTFILECSV" |cut -d ' ' -f 1) lines" || LOG "Before: CSV file doesn't exist"
	LOG "Before: last line of CSV file: $LASTLINE"
	LOG "No new entries to be processed..."
fi

[ -f "$OUTFILECSV" ] && LOG "After: CSV file has $(wc -l "$OUTFILECSV" |cut -d ' ' -f 1) lines"
[ -f "$OUTFILECSV" ] && LOG "After: last line of CSV file: $(tail --lines=1 "$OUTFILECSV")"

# now we can stitching the CSV file together:
if [ -f "$OUTFILETMP" ]
then
	LOG "After: New PlaneFence file has $(wc -l "$OUTFILETMP" |cut -d ' ' -f 1) lines"
	LOG "After: last line of PF file: $LASTLINE"
	cat $OUTFILETMP >> "$OUTFILECSV"
	rm $OUTFILETMP
	LOG "Concatenated $OUTFILETMP to $OUTFILECSV"
else
	LOG "After: No New PlaneFence file as there were no new aircraft in reach"
fi

# Now check if we need to add noise data to the csv file
if [ "$NOISECAPT" == "1" ]
then
	LOG "Invoking noise2fence!"
	$PLANEFENCEDIR/noise2fence.sh
else
	LOG "Info: Noise2Fence not enabled"
fi

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

# Now, let's see if the DISTUNIT and DISPLAYUNIT are the same. If not, we need to convert to DISPLAYUNIT:

if [ "$DISPLAYUNIT" == "" ]
then
	DISPLAYUNIT="$DISTUNIT"
	DISPLAYDIST="$DIST"
fi

if [ "$DISTUNIT" != "$DISPLAYUNIT" ]
then
	printf -v DISPLAYDIST "%.1f" "$(echo "$DIST * $DISTCONV" | bc -l)"
fi

# Now let's link to the latest Spectrogram, if one was generated for today:

if [ "$REMOTENOISE" != "" ]
then
	# get the latest spectrogram from the remote server
	scp -q $REMOTENOISE:$TMPDIR/noisecapt-spectro-latest.png $OUTFILEDIR/noisecapt-spectro-latest.png.tmp
	mv -f $OUTFILEDIR/noisecapt-spectro-latest.png.tmp $OUTFILEDIR/noisecapt-spectro-latest.png

elif (( $(find $TMPDIR/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | wc -l  ) > 0 ))
then
	ln -sf $(find $TMPDIR/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | tail -1) $OUTFILEDIR/noisecapt-spectro-latest.png
else
	rm -f $OUTFILEDIR/noisecapt-spectro-latest.png 2>/dev/null
fi

# If $PLANEALERT=true then lets call dictalert to see if the new lines contain any planes of special interest:
[ "$PLANEALERT" == "true" ] && ( LOG "Calling Plane-Alert as $PLALERTFILE $INFILETMP" ; $PLALERTFILE $INFILETMP )

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
        body { font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; }
        a { color: #0077ff; }
	h1 {text-align: center}
	h2 {text-align: center}
	.planetable { border: 1; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; text-align: center }
	.history { border: none; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; }
	.footer{ border: none; margin: 0; padding: 0; font: 8px/1.4 "Helvetica Neue", Arial, sans-serif; text-align: center }
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
			   <li>Maximum distance from <a href="https://www.openstreetmap.org/?mlat=$LAT&mlon=$LON#map=14/$LAT/$LON&layers=H" target=_blank>${LAT}&deg;N, ${LON}&deg;E</a>: $DISPLAYDIST $DISPLAYUNIT
			   <li>Only aircraft below $(printf "%'.0d" $MAXALT) $ALTUNIT are reported
			   <li>Data extracted from $(printf "%'.0d" $CURRCOUNT) <a href="https://en.wikipedia.org/wiki/Automatic_dependent_surveillance_%E2%80%93_broadcast" target="_blank">ADS-B messages</a> received since midnight today
EOF


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
[ "$TRACKSERVICE" == "adsbexchange" ] && printf "<li>Click on the flight number to see the full flight information/history (from <a href=\"https://globe.adsbexchange.com/?lat=$LAT&lon=$LON&zoom=11.0\" target=\"_blank\">AdsbExchange</a>)" >> "$OUTFILEHTMTMP"

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
if (( MAXFIELDS > 8 ))
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
		   </details>
	</section>
	<hr/>
EOF
fi


WRITEHTMLHISTORY "$OUTFILEDIR" "$OUTFILEHTMTMP"
LOG "Done writing history"

cat <<EOF >>"$OUTFILEHTMTMP"
<div class="footer">
<hr/>PlaneFence $VERSION is part of <a href="https://github.com/kx1t/planefence4docker" target="_blank">KX1T's PlaneFence Open Source Project</a>, available on GitHub.
<br/>&copy; Copyright 2020, 2021 by Ram&oacute;n F. Kolb
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
