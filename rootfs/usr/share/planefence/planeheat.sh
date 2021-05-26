#!/bin/bash
# PLANEHEAT - a Bash shell script to render a heatmap based on Planefence CSV entries
# Only to be used in the context of PlaneFence -- the code to create whole websites was removed from this version of the file
#
# Usage: ./planeheat.sh [date]
#
# Copyright 2020,2021 Ramon F. Kolb - licensed under the terms and conditions
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
# Feel free to make changes to the variables between these two lines. However, it is
# STRONGLY RECOMMENDED to RTFM! See README.md for explanation of what these do.
# These are the input and output directories and file names:
  PLANEFENCEDIR=/usr/share/planefence # the directory where this file and planefence.py are located
  GRIDSIZE=100

# -----------------------------------------------------------------------------------
# Only change the variables below if you know what you are doing.
        if [ "$1" != "" ] && [ "$1" != "reset" ]
        then # $1 contains the date for which we want to run PlaneFence
                FENCEDATE=$(date --date="$1" '+%y%m%d')
        else
                FENCEDATE=$(date --date=today '+%y%m%d')
        fi
        # Let's see if there is a CONF file that overwrites some of the parameters already defined
        [[ -f "$PLANEFENCEDIR/planefence.conf" ]] && source "$PLANEFENCEDIR/planefence.conf"
        #
        # Override $TMPDIR -- the reason is that we want the temp files of planeheat
        # to be in persistent memory so they will survive docker updates
        TMPDIR=/usr/share/planefence/persist/.internal
        #
        INFILECSV=$OUTFILEBASE-$FENCEDATE.csv
        PH_LINESBASE=dump1090-ph-temp.tmp
        PH_LINES=$TMPDIR/$PH_LINESBASE
        INFILESOCK=$LOGFILEBASE$FENCEDATE.txt
        TMPVARS=$TMPDIR/planeheat-$FENCEDATE.tmp
        TMPVARSTEMPLATE="$TMPDIR/planeheat-*.tmp"
        MINTIME=60
#       VERBOSE="--verbose"
        VERBOSE=""
        VERSION=0.3
        LOGFILE=/tmp/planefence.log
#       LOGFILE=logger # if $LOGFILE is set to "logger", then the logs are written to /var/log/syslog. This is good for debugging purposes.
#	LOGFILE=/dev/stdout
        CURRENT_PID=$$
        PROCESS_NAME=$(basename "$0")
        TIMELOG=$(date +%s)

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
            LON_VIS="$(sed 's/^00*\|00*$//g' <<< $LON_VIS)"	# strip any trailing zeros - "41.10" -> "41.1", or "41.00" -> "41."
            LON_VIS="${LON_VIS%.}"		# If the last character is a ".", strip it - "41.1" -> "41.1" but "41." -> "41"
            LAT_VIS="$(sed 's/^00*\|00*$//g' <<< $LAT_VIS)" 	# strip any trailing zeros - "41.10" -> "41.1", or "41.00" -> "41."
            LAT_VIS="${LAT_VIS%.}" 		# If the last character is a ".", strip it - "41.1" -> "41.1" but "41." -> "41"
        else
            LON_VIS="$LON"
            LAT_VIS="$LAT"
        fi

        # Now determine the conversion factor for the circle on the map
        # The leaflet parameter wants input in meters
        if [ "$SOCKETCONFIG" != "" ]
        then
        	case "$(grep "^distanceunit=" $SOCKETCONFIG |sed "s/distanceunit=//g")" in
        		nauticalmile)
                # 1 NM is 1852 meters
        		TO_METER=1852
        		;;
        		kilometer)
                # 1 km is 1000 meters
        		TO_METER=1000
        		;;
        		mile)
                # 1 mi is 1609 meters
        		TO_METER=1609
        		;;
        		meter)
        		# 1 meter is 1 meters
        		TO_METER=1
        	esac
        fi

# -----------------------------------------------------------------------------------
#

# Functions
#
# First create an function to write to the log
LOG ()
{
        if [ -n "$1" ]
        then
              IN="$1"
        else
              read -r IN # This reads a string from stdin and stores it in a variable called IN. This enables things like 'echo hello world > LOG'
        fi

        if [ "$VERBOSE" != "" ]
        then
                # set the color scheme in accordance to the log level urgency
                if [ "$2" == "1" ]; then
                        COLOR="\e[34m"
                elif [ "$2" == "2" ]; then
                        COLOR="\e[31m"
                else
                        COLOR=""
                fi
                if [ "$LOGFILE" == "logger" ]
                then
                        printf "%s-%s[%s]v%s: %s%s\e[39m\n" "$(date +'%Y%m%d-%H%M%S')" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$COLOR" "$IN"  | logger
                else
                        printf "%s-%s[%s]v%s: %s%s\e[39m\n" "$(date +'%Y%m%d-%H%M%S')" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$COLOR" "$IN" >> $LOGFILE
                fi
        fi
}
# -----------------------------

# check if the CSV file exists, if not, exit
[ ! -f "$INFILECSV" ] && INFILE=true || INFILE=false

#  Define some vars:
LASTFENCE=0
LASTLINE=0
COUNTER=0

# Clear out $PH_LINES if it exists:
if [ -f "$PH_LINES" ] && [ ! -f "$TMPVARS" ]
then
	 rm -f $PH_LINES
fi

# delete the history if the command line arg is "reset"
if [ "$1" == "reset" ]
then
	rm -f $PH_LINES 2>/dev/null
	rm -f $TMPVARS 2>/dev/null
fi

# get some variables from the previous run(s):
if [ -f "$TMPVARS" ]
then
        IFS="," read -raVARS < "$TMPVARS"
	LASTFENCE=${VARS[0]}
	LASTLINE=${VARS[1]}
fi

LOG "Starting: Previously processed planes=$LASTFENCE and last line processed=$LASTLINE"

# split the $INFILESOCK if needed
tail --lines=+"$((LASTLINE + 1))" "$INFILESOCK" > "$INFILESOCK".tmp

# Now let's iterate through the entries in the file
if [[ -f "$INFILECSV" ]]
then
    while read -r CSVLINE
    do
        # Now clean the line from any control characters (like stray \r's) and read the line into an array:
        IFS="," read -r -aRECORD <<< "$(echo -n $CSVLINE | tr -d '[:cntrl:]')"
        (( COUNTER++ ))
        LOG "Processing ${RECORD[0]} (${RECORD[2]:11:8} - ${RECORD[3]:11:8}) with COUNTER=$COUNTER, NUMRECORD=${#RECORD[@]}, LASTFENCE=$LASTFENCE"

        # changed the IF statement below. Skipping over already processed entities doesn't really slow down the script too much
        # if it is executed every, say hour or so, and this will enable collecting more data if the log rolled over just when we did the
        # last iteration.
        #       if (( ${#RECORD[@]} != 0 )) && (( $COUNTER > $LASTFENCE ))
        if (( ${#RECORD[@]} != 0 ))
        then
            # first make sure there are at least $MINTIME samples that are being considered
            if (( $(date -d ${RECORD[3]:11:8} +%s) - $(date -d ${RECORD[2]:11:8} +%s) < MINTIME ))
            then
                ENDTIME=$(date -d @$(( $(date -d ${RECORD[2]:11:8} +%s) + MINTIME)) +%T)
                LOG "(Corrected ENDTIME to $ENDTIME)"
            else
                ENDTIME="${RECORD[3]:11:8}"
            fi
            awk -v starttime="${RECORD[2]:11:8}" -v endtime="$ENDTIME" -v icao="${RECORD[0]}" -v maxalt="$MAXALT" 'BEGIN { FS="," } { if ($1 == icao && $6 >= starttime && $6 <= endtime && $2 <= maxalt) print $0; }' "$INFILESOCK.tmp" >> "$PH_LINES"
            LOG "Now $(wc -l $PH_LINES) positions in $PH_LINES"
        else
            LOG "(${RECORD[0]} was previously processed.)"
        fi
    done < "$INFILECSV"
fi

# rewrite the latest to $TMPVARS
rm -f "$TMPVARSTEMPLATE" 2>/dev/null
((  LASTLINE = LASTLINE + $(wc -l < "$INFILESOCK".tmp) ))
printf "%s,%s\n" "$COUNTER" "$LASTLINE" > "$TMPVARS"
rm -f "$INFILESOCK".tmp

LOG "Creating Heatmap Data"

# Now we need to "box" the parameters
# Let's first figure out the min/max latitude of the map.
# $DIST contains the radius of the map, and $LON/$LAT contain the coordinates of the map's center
#

# Determine the distance in degrees for a square box around the center point

DEGDIST=$(awk 'BEGIN { FS=","; minlat=180; maxlat=-180; minlon=180; maxlon=-180 } { minlat=(minlat<$3)?minlat:$3; maxlat=(maxlat>$3)?maxlat:$3; minlon=(minlon<$4)?minlon:$4; maxlon=(maxlon>$4)?maxlon:$4 } END {dist=(maxlat-minlat)>(maxlon-minlon)?(maxlat-minlat)/2:(maxlon-minlon)/2; print dist}' "$PH_LINES")
 LOG "Dist=$DEGDIST"

# determine start time and end time
read -raREC <<< $(awk 'BEGIN { FS=","; maxtime="00:00:00.000"; mintime="23:59:59.999"} { mintime=(mintime<$6)?mintime:$6; maxtime=(maxtime>$6)?maxtime:$6 } END {print mintime,maxtime}' "$PH_LINES")
 LOG "Start time=${REC[0]}, End time=${REC[1]}"

# Now call the Heatmap Generator
if [[ -f "$INFILECSV" ]]
then
    $PLANEFENCEDIR/planeheat.pl -silent -lon $LON -lat $LAT -data $TMPDIR -output $OUTFILEDIR -degrees $DEGDIST -maxpositions 200000 -resolution 100 -override -file planeheatdata-$(date -d $FENCEDATE +"%y%m%d").js  -filemask "${PH_LINESBASE::-1}""*"
    #echo $PLANEFENCEDIR/planeheat.pl -lon $LON -lat $LAT -data $TMPDIR -output $OUTFILEDIR -degrees $DEGDIST -maxpositions 200000 -resolution 100 -override -file planeheatdata-$(date -d $FENCEDATE +"%y%m%d").js  -filemask "${PH_LINESBASE::-1}""*"
    LOG "Returned from planeheat.pl"
else
    echo "var addressPoints = [ ];" >$OUTFILEDIR/planeheatdata-$(date -d $FENCEDATE +"%y%m%d").js
fi


DISTMTS=$(bc <<< "$DIST * $TO_METER")

# Now build the HTML file of the day:

cat <<EOF >"$PLANEHEATHTML"

<div id="map" style="width: $HEATMAPWIDTH; height: $HEATMAPHEIGHT"></div>

<script src="HeatLayer.js"></script>
<script src="leaflet-heat.js"></script>
<script src="planeheatdata-$(date -d $FENCEDATE +"%y%m%d").js"></script>
<script>
	var map = L.map('map').setView([parseFloat("$LAT_VIS"), parseFloat("$LON_VIS")], parseInt("$HEATMAPZOOM"));
	var tiles = L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', {
	    attribution: '<a href="https://github.com/Leaflet/Leaflet.heat">Leaflet.heat</a> , &copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors',
	    }).addTo(map);

    addressPoints = addressPoints.map(function (p) { return [p[0], p[1]]; });
    var heat = L.heatLayer(addressPoints, {
        minOpacity: 1,
        radius: 7,
        maxZoom: 14,
        blur: 11,
        attribution: "<a href=https://github.com/kx1t/docker-planefence target=_blank>docker:kx1t/planefence</a>"
        }).addTo(map);
    var circle = L.circle([ parseFloat("$LAT_VIS"), parseFloat("$LON_VIS")], {
        color: 'blue',
        fillColor: '#f03',
        fillOpacity: 0.1,
        radius: $DISTMTS
    	}).addTo(map);

EOF

if [[ "$OPENAIP_LAYER" == "ON" ]]
then
	cat <<EOF >>"$PLANEHEATHTML"
    var openaip_cached_basemap = new L.TileLayer("http://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_basemap@EPSG%3A900913@png/{z}/{x}/{y}.png", {
         maxZoom: 16,
         minZoom: 2,
         tms: true,
         subdomains: '12',
         format: 'image/png',
         transparent: true,
         attribution: "<a href=http://www.openaip.net>OpenAIP.net</a>"
         }).addTo(map);

EOF
fi
cat <<EOF >>"$PLANEHEATHTML"

</script>

EOF
