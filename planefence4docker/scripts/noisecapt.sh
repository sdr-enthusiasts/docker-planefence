#!/bin/bash
# NOISECAPT - a Bash shell script to continuously capture audio levels from a standard audio device
#
# Note: this script is meant to be run as a daemon using SYSTEMD
# If run manually, it will continuously loop to listen for new planes
#
# This script is distributed as part of the PlaneFence package.
#
# Copyright 2020 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence
#
# The output is written in headerless CSV format to the file defined below.
# The format of the output is:
# secs_since_epoch,capture_absolute_level,capture_dB,avg_dB_5_mins,avg_dB_10_mins, avg_dB_1_hour,avg_dB_midnight_to_now
#
# -----------------------------------------------------------------------------------
# Feel free to make changes to the variables between these two lines. However, it is# STRONGLY RECOMMENDED to RTFM! See README.md for explanation of what these do.
#
# CAPTURETIME is the duration of a single audio capture, in seconds
        CAPTURETIME=5
# OUTFILE contains the base part of the output file for the captured data,
# including the directory. Please make sure that this directory is accessable
# for the script as it won't attempt to create or CHMOD it. If the script
# can't write to the directory, it will silently fail / appear to do nothing
        OUTFILE="/tmp/noisecapt-"
        OUTFILEEXT=".log"
        TEMPFILE="/tmp/noisecapt.tmp"
# If you don't want logging, simply set  the VERBOSE=1 line below to VERBOSE=0
        VERBOSE=0
        LOGFILE=/tmp/noisecapt.log
# The script will attempt to figure out by itself what your audio device is
# However, it may get it wrong, especially if you have more than
# 1 soundcard ,webcam, etc
# in that case, please give this command: 'arecord -l' and fill in the values
# for Card and Devuce here.
# If you uncomment the variables bekow, you MUST provide BOTH the Card and the Device numbers
# CARD=1
# DEVICE=0
# -----------------------------------------------------------------------------------
#
# some global stuff:
# IFS is needed to read data lines into an array
# IFS=','
# Create an function to write to the log:
LOG ()
{
        if [ "$VERBOSE" == "1" ];
        then
                printf "%s: %s\n" "$(date)" "$1" >> $LOGFILE
        fi
}

LOG "-----------------------------------------------------------------------------------"
LOG "Starting NoiseCapt"

# Try to get the card/device for the audio input device
if [ -z "$CARD" ]
then
	CARD=$(arecord -l |grep -oP "card\s+\K\w+")
	DEVICE=$(arecord -l |grep -oP "device\s+\K\w+")
	LOG "Audio device Card,Device auto-set to \"$CARD,$DEVICE\""
else
	LOG "Audio device Card,Device manually set to \"$CARD,$DEVICE\""
fi

# Calc how many records we need from the past logs
(( ONEHOUR="3600 / $CAPTURETIME" ))

LOG "Need $ONEHOUR loglines"

# And here we go, Loop forevah:
while true
do
        # determine which file we need to write to
        LOGTODAY="$OUTFILE$(date +'%y%m%d')$OUTFILEEXT"
        LOGYSTRDAY="$OUTFILE$(date -d yesterday +'%y%m%d')$OUTFILEEXT"
	LOG "Logfiles today=$LOGTODAY yesterday=$LOGYSTRDAY"

        # and determine if yesterday's file exists
        if [ ! -f "$LOGYSTRDAY" ]
        then
                LOGYSTRDAY=""
        	LOG "Yesterday log doesnt exist"
	fi

        # capture audio and put the results in an array
        # All dB levels are dBFS, or dB where the loudest (="full scale") is 0 dB
        # RMSREC="$(arecord -D hw:$CARD,$DEVICE -d $CAPTURETIME --fatal-errors --buffer-size=192000 -f dat -t raw -c 1 --quiet | sox -V -t raw -b 16 -r 48 -c 1 -e signed-integer - -t raw -b 16 -r 48 -c 1 /dev/null stats 2>&1 | grep 'RMS lev dB')"
	RMSREC="$(arecord -D hw:$CARD,$DEVICE -d $CAPTURETIME --fatal-errors --buffer-size=192000 -f dat -t raw -c 1 --quiet | sox -V -t raw -b 16 -r 48000 -c 1 -e signed-integer - -t raw -b 16 -r 48000 -c 1 -e signed-integer - sinc -n 4096 1500-9000 2>/dev/null | sox -V -t raw -b 16 -r 48000 -c 1 -e signed-integer - -t raw -b 16 -r 48000 -c 1 /dev/null stats 2>&1 |grep 'RMS lev dB')"
	IFS=' ' read -a RMS <<< "$RMSREC"

	# put the dB value into LEVEL as an integer. BASH arithmatic doesn't like
	# float values, so we need to do some trickery to convert the number:
	LC_ALL=C printf -v LEVEL '%.0f' "${RMS[3]}"
        AUDIOTIME=$(date +%s)
        # capture and calculate the averages
        # determine the number of records in today's log
        if [ -f "$LOGTODAY" ]
        then
                LOGLINES="$(wc -l "$LOGTODAY")"
                LOGLINES=${LOGLINES% *}
        else
                LOGLINES=0
        fi

        # create a TMP file with the records we need
        if [ "$ONEHOUR" -gt $LOGLINES ]
        then
                # we have too few records in today's log and we need a few from yesterday's log if it exists
                if [ -f "$LOGYSTRDAY" ]
                then
                        (( UNDERFLOW="$ONEHOUR - $LOGLINES" ))
                        tail --lines="$UNDERFLOW" "$LOGYSTRDAY" > $TEMPFILE
                        if [ -f "LOGTODAY" ]
			then
				cat "$LOGTODAY" >> $TEMPFILE
			fi
                elif  [ -f "$LOGTODAY" ]
                then
                        # yesterday's file doesn't exist and we'll have to make do with today's
                        cat "$LOGTODAY" > $TEMPFILE

                fi
        elif [ -f "$LOGTODAY" ]
        then
                # we need $LOGLINES records from the $LOGTODAY
                tail --lines=$LOGLINES "$LOGTODAY" > $TEMPFILE
        fi

	# there is a chance that no $TEMPFILE was created if there was no logfile
	# for either today or yesterday, so let's touch the file so we can be sure
	# it exists
	touch $TEMPFILE

        # Now we can read the TEMPFILE and determine the averages
        (( ONEMINCT = 1 ))
        (( FIVEMINCT = 1 ))
        (( TENMINCT = 1 ))
        (( ONEHRCT = 1 ))

        (( ONEMINTL = LEVEL ))
        (( FIVEMINTL = LEVEL ))
        (( TENMINTL = LEVEL ))
        (( ONEHRTL = LEVEL ))

        if [ -f $TEMPFILE ]
        then
            while IFS= read -r ONELINE
            do
                # split $LINE into an array:
		unset LINE
		IFS=',' read -a LINE <<< "$ONELINE"
                if [ $(( $AUDIOTIME - ${LINE[0]} )) -lt 3600 ]
                then
                        (( "ONEHRCT++" ))
                        (( "ONEHRTL = $ONEHRTL + ${LINE[1]}" ))
                fi

                if [ $(( $AUDIOTIME - ${LINE[0]} )) -lt 600 ]
                then
                        (( "TENMINCT++" ))
                        (( "TENMINTL = $TENMINTL + ${LINE[1]}" ))
                fi

                if [ $(( $AUDIOTIME - ${LINE[0]} )) -lt 300 ]
                then
                        (( "FIVEMINCT++" ))
                        (( "FIVEMINTL = FIVEMINTL + ${LINE[1]}" ))
                fi

                if [ $(( $AUDIOTIME - ${LINE[0]} )) -lt 60 ]
                then
                        (( "ONEMINCT++" ))
                        (( "ONEMINTL = ONEMINTL + ${LINE[1]}" ))
                fi

            done < "$TEMPFILE"
        fi

        (( "ONEMINAVG = $ONEMINTL / $ONEMINCT" ))
        (( "FIVEMINAVG = $FIVEMINTL / $FIVEMINCT" ))
        (( "TENMINAVG = $TENMINTL / $TENMINCT" ))
        (( "ONEHRAVG = $ONEHRTL / $ONEHRCT" ))

        # Now we have all the averages, we can write them to the file
        printf "%s,%s,%s,%s,%s,%s\n" "$AUDIOTIME" "$LEVEL" "$ONEMINAVG" "$FIVEMINAVG" "$TENMINAVG" "$ONEHRAVG" >> $LOGTODAY

done
