#!/bin/bash
# NOISE2FENCE -- a script for extracting recorded noise values from NOISECAPT
# and adding them to CSV files that have been created by Planefence
#
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
#
# -----------------------------------------------------------------------------------
# Feel free to make changes to the variables between these two lines. However, it is
# STRONGLY RECOMMENDED to RTFM! See README.md for explanation of what these do.
#
# shellcheck disable=SC1091
[[ -f "/usr/share/planefence/planefence.conf" ]] && source /usr/share/planefence/planefence.conf

CSVDIR=/usr/share/planefence/html
CSVNAMEBASE=$CSVDIR/planefence-
CSVNAMEEXT=".csv"
LOGNAMEBASE=/usr/share/planefence/persist/.internal/noisecapt-
LOGNAMEEXT=".log"
CSVTMP=/usr/share/planefence/persist/.internal/pf-noise-csv.tmp
NOISETMP=/usr/share/planefence/persist/.internal/pf-noise-data.tmp
LOGFILE=/tmp/noise2fence.log
VERBOSE=
VERSION=0.3-docker
# -----------------------------------------------------------------------------------
# Figure out if NOISECAPT is active or not. REMOTENOISE contains the URL of the NoiseCapt container/server
# and is configured via the $PF_NOISECAPT variable in the .env file.
# Only if REMOTENOISE contains a URL and this URL is reachable, we collect noise data
# Note that this doesn't check for the validity of the actual URL, just that we can reach it.
#replace wget with curl to save disk space --was [[ "x$REMOTENOISE" != "x" ]] && [[ "$(wget -q -O /dev/null $REMOTENOISE ; echo $?)" == "0" ]] && NOISECAPT=1 || NOISECAPT=0
if [[ -n "$REMOTENOISE" ]] && curl  --fail -s -o /dev/null "$REMOTENOISE"; then NOISECAPT=1; else NOISECAPT=0; fi

if [ "$NOISECAPT" != "1" ]
then
		echo "NoiseCapt exited prematurely because \$REMOTENOISE was not defined or we couldn't reach that URL. \$REMOTENOISE is set to \"$REMOTENOISE\"."
		exit 1
fi

# First create an function to write to the log
LOG ()
{	if [ "$VERBOSE" != "" ]
	then
		printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$1" >> $LOGFILE
	fi

}

if [ "$1" != "" ] && [ "$1" != "reset" ]
then # $1 contains the date for which we want to run Planefence
	NOISEDATE=$(date --date="$1" '+%y%m%d')
else
	NOISEDATE=$(date --date="today" '+%y%m%d')
fi

CSVFILE=$CSVNAMEBASE$NOISEDATE$CSVNAMEEXT
# CSVFILE=/tmp/noise.csv



# replace wget by curl to save disk space. was: if [ "$(wget -q -O - $REMOTENOISE/${LOGNAMEBASE##*/}$NOISEDATE$LOGNAMEEXT > $LOGNAMEBASE$NOISEDATE$LOGNAMEEXT.tmp ; echo $?)" != "0" ]
if ! curl --fail -s "$REMOTENOISE/${LOGNAMEBASE##*/}$NOISEDATE$LOGNAMEEXT" > "$LOGNAMEBASE$NOISEDATE$LOGNAMEEXT.tmp"
then
	echo "Can't reach $REMOTENOISE/${LOGNAMEBASE##*/}$NOISEDATE$LOGNAMEEXT ... exiting"
	exit 1
fi

mv -f "$LOGNAMEBASE$NOISEDATE$LOGNAMEEXT.tmp" "$LOGNAMEBASE$NOISEDATE$LOGNAMEEXT"
LOG "Got $LOGNAMEBASE$NOISEDATE$LOGNAMEEXT from $REMOTELOG"

NOISEFILE="$LOGNAMEBASE$NOISEDATE$LOGNAMEEXT"

# make sure there's no stray TMP file around, so we can directly append
rm -f "$CSVTMP" "$NOISETMP"

#Now iterate through the CSVFILE:
LOG "------------------------------"
LOG "Starting NOISE2FENCE"
LOG "CSVFILE=$CSVFILE"
LOG "NOISEFILE=$NOISEFILE"
if [ -f "$CSVFILE" ]
then
	# Clean the  $CSVFILE first
#	cat "$CSVFILE" | tr -d '\r' >/tmp/noisetmp.tmp
#	mv /tmp/noisetmp.tmp "$CSVFILE"
	while read -r CSVLINE
	do
		XX=$(echo -n "$CSVLINE" | tr -d '[:cntrl:]')
		CSVLINE=$XX
		unset RECORD
		# Read the line, but first clean it up as it appears to have a newline in it
		IFS="," read -ra RECORD <<< "$CSVLINE"
		LOG "${#RECORD[*]} records in the current line: (${RECORD[*]})"
		# if there's no audio stored in the record
		if [ "${#RECORD[*]}" -le "7" ]
		then
			LOG "No audio yet for ${RECORD[0]}. Collecting it now..."
			# Go get the data for the record:
			# Figure out the start and end time of the record, in seconds since epoch
			STARTTIME=$(date -d "${RECORD[2]}" +%s)
			ENDTIME=$(date -d "${RECORD[3]}" +%s)
			# We could have done the following in a (long) oneliner, but breaking it out in multiple lines is clearer.
			# Use AWK to get the position of the last noisecapt record before STARTTIME
			# and the number of positions between STARTTIME and ENDTIME
			# Hint: it's not very safe to use variable substitution in AWK. Rather than relying on hardcoded substitution inside
			# the AWK program, it's safer to define the variables with the -v parameter. the -F parameter defines the field separator
			STARTPOS=$(awk -vS="$STARTTIME" -F, '{if($1<S) print $1}' < "$NOISEFILE" | wc -l)
			NUMPOS=$(awk -vS="$STARTTIME" -vE="$ENDTIME" -F, '{if($1>=S && $1<=E) print $1}' < "$NOISEFILE" | wc -l)
			# Make sure the sample after leaving the coverage area is also included:
			(( NUMPOS=NUMPOS+1 ))
			LOG "Start Position: $STARTPOS, Number of samples: $NUMPOS"
			# Then put the corresponding noisecapt records into $NOISETMP.
			tail --lines=+"$STARTPOS" "$NOISEFILE" | head --lines="$NUMPOS" > $NOISETMP
			#RECORD[6]="${RECORD[6]//[$'\t\r\n']}"
			# Next is to figure out the data that we want to add to the PLANEFENCE record.
			# $NOISEFILE and $NOISECAPT have the following format, with all audio values in dBFS:
			# secs_since_epoch,5_sec_RMS,1_min_avg,5_min_avg,10_min_avg,1_hr_avg
			# Since the PLANEFENCE record spans some period of time, we want to write the peak values
			# throughout the timespan.
			# These maximums for each column are again retrieved using AWK:
			RECORD+=("$(awk -F, 'BEGIN{a=-999}{if ($2>0+a) a=$2} END{print a}' "$NOISETMP")" \
				 "$(awk -F, 'BEGIN{a=-999}{if ($3>0+a) a=$3} END{print a}' "$NOISETMP")" \
				 "$(awk -F, 'BEGIN{a=-999}{if ($4>0+a) a=$4} END{print a}' "$NOISETMP")" \
				 "$(awk -F, 'BEGIN{a=-999}{if ($5>0+a) a=$5} END{print a}' "$NOISETMP")" \
				 "$(awk -F, 'BEGIN{a=-999}{if ($6>0+a) a=$6} END{print a}' "$NOISETMP")" )
		else
			LOG "Skipping:audio was already added to CSVLINE"
		fi
		# Now write everything back to $CSVTMP, which we will then copy back over the old CSV file
		( IFS=','; echo "${RECORD[*]}" >> "$CSVTMP" )
		LOG "The record now contains ${RECORD[*]}"
	done < "$CSVFILE"

	# Now, if there is a $CSVTMP file, we will overwrite $CSVFILE with it.
	LOG "Writing to $CSVFILE ..."
	[ -f "$CSVTMP" ] && mv -f "$CSVTMP" "$CSVFILE"
else
	LOG "$CSVFILE doesn't exist. Nothing to do..."
fi

LOG "Done!"
LOG "------------------------------"
