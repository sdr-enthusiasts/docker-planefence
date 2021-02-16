#!/bin/bash
# NOISE2FENCE -- a script for extracting recorded noise values from NOISECAPT
# and adding them to CSV files that have been created by PlaneFence
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
# -----------------------------------------------------------------------------------
# Feel free to make changes to the variables between these two lines. However, it is
# STRONGLY RECOMMENDED to RTFM! See README.md for explanation of what these do.
#
CSVDIR=/usr/share/planefence/html
CSVNAMEBASE=$CSVDIR/planefence-
CSVNAMEEXT=".csv"
LOGNAMEBASE=/tmp/noisecapt-
LOGNAMEEXT=".log"
CSVTMP=/tmp/pf-noise-csv.tmp
NOISETMP=/tmp/pf-noise-data.tmp
LOGFILE=/tmp/noise2fence.log
VERBOSE=1
# -----------------------------------------------------------------------------------
# Additional variables:
CURRENT_PID=$$
PROCESS_NAME=$(basename $0)
VERSION=0.1-docker
# -----------------------------------------------------------------------------------
#
# If you want to read a remote file, please do the following:
# ON THIS MACHINE, as user 'pi':
# - if it doesn't already exist, create ~/.ssh and cd into that directory
# - if ~/.ssh/id_rsa.pub doesn't already exist, then type this command: ssh-keygen -t rsa -C "pi@PIAWARE"
# - Copy ~/.ssh/id_rsa.pub to the remote machine (replace 10.0.0.161 with the IP or DNS of the remote machine): scp ~/.ssh/id_rsa.pub pi@10.0.0.161:/tmp/id_rsa.pub
# ON THE REMOTE MACHINE, as user 'pi':
# - if it doesn't already exist, create ~/.ssh and cd into that directory
# - Add the file you copied to your authorized keys: cp /tmp/id_rsa.pub >> ~/.ssh/authorized_keys ; rm /tmp/id_rsa.pub
# - make sure you set the right permissions:
#   chmod 0700 ~/.ssh
#   chmod 0600 ~/.ssh/authorized_keys
# Last, configure the REMOTELOG parameter with the username and IP address of the remote account:
#
# If you do NOT want remote access, simply comment out the REMOTELOG line below.
# REMOTELOG=pi@10.0.0.161


# First create an function to write to the log
LOG ()
{	if [ "$VERBOSE" != "" ]
	then
		printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$1" >> $LOGFILE
	fi

}

if [ "$1" != "" ] && [ "$1" != "reset" ]
then # $1 contains the date for which we want to run PlaneFence
	NOISEDATE=$(date --date="$1" '+%y%m%d')
else
	NOISEDATE=$(date --date="today" '+%y%m%d')
fi

CSVFILE=$CSVNAMEBASE$NOISEDATE$CSVNAMEEXT
# CSVFILE=/tmp/noise.csv

if [ "$REMOTELOG" != "" ]
then
	scp $REMOTELOG:$LOGNAMEBASE$NOISEDATE$LOGNAMEEXT $LOGNAMEBASE$NOISEDATE$LOGNAMEEXT.tmp
	mv -f $LOGNAMEBASE$NOISEDATE$LOGNAMEEXT.tmp $LOGNAMEBASE$NOISEDATE$LOGNAMEEXT
	LOG "Got $LOGNAMEBASE$NOISEDATE$LOGNAMEEXT from $REMOTELOG"
fi

NOISEFILE=$LOGNAMEBASE$NOISEDATE$LOGNAMEEXT


# make sure there's no stray TMP file around, so we can directly append
[ -f "$CSVTMP" ] && rm "$CSVTMP"
[ -f "$NOISETMP" ] && rm "$NOISETMP"

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
	while read CSVLINE
	do
		XX=$(echo -n $CSVLINE | tr -d '[:cntrl:]')
		CSVLINE=$XX
		unset RECORD
		# Read the line, but first clean it up as it appears to have a newline in it
		IFS="," read -aRECORD <<< "$CSVLINE"
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
			tail --lines=+"$STARTPOS" $NOISEFILE | head --lines="$NUMPOS" > $NOISETMP
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
		LOG "The record now contains $(IFS=','; echo ${RECORD[*]})"
		#for i in {0..10}
		#do
		#	printf "%s," "${RECORD[i]}" >> "$CSVTMP"
		#done
		# printf "%s\n" "${RECORD[11]}" >> "$CSVTMP"
	done < "$CSVFILE"

	# Now, if there is a $CSVTMP file, we will overwrite $CSVFILE with it.
	LOG "Writing to $CSVFILE ..."
	[ -f "$CSVTMP" ] && mv -f "$CSVTMP" "$CSVFILE"
else
	LOG "$CSVFILE doesn't exist. Nothing to do..."
fi

LOG "Done!"
LOG "------------------------------"
