#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034
###shellcheck disable=SC2001,SC2015,SC1091,SC2129,SC2154,SC2155
#
# PLANEFENCE - a Bash shell script to render a HTML and CSV table with nearby aircraft
#
# Usage: ./planefence.sh
#
# Copyright 2020-2025 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
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
set -eo pipefail

## DEBUG temp stuff to satisfy set -u which is included for debugging:
FENCEDATE=""
execstarttime="$(date +%s.%3N)"
execlaststeptime="$execstarttime"

##
source /scripts/common
source /usr/share/planefence/planefence.conf

# ==========================
# Config
# ==========================
HTMLDIR="/tmp"
#HTMLDIR="${OUTFILEDIR:-/usr/share/planefence/html}"
mkdir -p "$HTMLDIR"

TODAY="$(date +%y%m%d)"
YESTERDAY="$(date -d "yesterday" +%y%m%d)"

TODAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${TODAY}.txt" -print0 | xargs -0 ls -t | head -n 1)"
YESTERDAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${YESTERDAY}.txt" -print0 | xargs -0 ls -t | head -n 1)"

RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"
YESTERDAYRECORDSFILE="$HTMLDIR/.planefence-records-${YESTERDAY}"

CSVOUT="$HTMLDIR/planefence-${TODAY}.csv"
JSONOUT="$HTMLDIR/planefence-${TODAY}.json"

STATE_LASTREC="/usr/share/planefence/persist/.planefence-state-lastrec"

if [[ -f "$RECORDSFILE" ]]; then
    source "$RECORDSFILE"
else
    declare -A records
    records[maxindex]=-1
fi

# ==========================
# Functions
# ==========================

debug_time() {
    local currenttime
    currenttime="$(date +%s.%3N)"
    echo "DEBUG: Step $1 ($2) took $(bc -l <<< "$currenttime - $execlaststeptime") seconds. Total elapsed time: $(bc -l <<< "$currenttime - $execstarttime") seconds" >&2
    execlaststeptime="$currenttime"
}

ICAO2TAIL() {
  local icao="$1"
  local tail=""

	# See if we have it somewhere in the socket30003 file:
  tail="$(awk -F "," -v icao="$icao" '($1 == icao && $12 != "") {print $12;exit;}' "$RECORDSFILE" 2>/dev/null)"
  if [[ -n "$tail" ]]; then debug_time "ICAO2TAIL" "icao=$icao tail=$tail from socket30003 file"; fi
	if [[ -n "$tail" ]]; then echo "${tail// /}"; exit; fi

  # Look up the ICAO in the mictronics database (local copy) if we have it downloaded:
	if [[ -f /run/planefence/icao2plane.txt ]]; then
		tail="$(grep -i -w "$icao" /run/planefence/icao2plane.txt 2>/dev/null | head -1 | awk -F "," '{print $2}')"
	fi
  if [[ -n "$tail" ]]; then debug_time "ICAO2TAIL" "icao=$icao tail=$tail from mictronics database"; fi
	if [[ -n "$tail" ]]; then echo "${tail// /}"; exit; fi

	# If the ICAO starts with "A" and there is no flight or tail number, let's algorithmically determine the tail number
	if [[ "${icao:0:1}" == "A" ]]; then
		tail="$(/usr/share/planefence/icao2tail.py "$icao")"
	fi
  if [[ -n "$tail" ]]; then debug_time "ICAO2TAIL" "icao=$icao tail=$tail from N-number calc"; fi
	if [[ -n "$tail" ]]; then echo "${tail// /}"; exit; fi
}

GET_ROUTE () {
		# function to get a route by callsign. Must have a callsign - ICAO won't work
		# Usage: GET_ROUTE <callsign>
		# Uses the adsb.lol API to retrieve the route

		local route
		
		# first let's see if it's in the cache
		if [[ -f /usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt ]]; then
			route="$(awk -F, -v callsign="${1^^}" '$1 == callsign {print $2; exit}' "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt")"
			if [[ -n "$route" ]]; then
				if  [[ "$route" != "unknown" ]]; then echo "$route"; fi
				return
			fi
		fi

		if route="$(curl -sSL -X 'POST' 'https://api.adsb.lol/api/0/routeset' \
		                      -H 'accept: application/json' \
													-H 'Content-Type: application/json' \
													-d '{"planes": [{"callsign": "'"${1^^}"'","lat": '"$LAT"',"lng": '"$LON"'}] }' \
								| jq -r '.[]._airport_codes_iata')" \
				&& [[ -n "$route" ]] && [[ "$route" != "unknown" ]] && [[ "$route" != "null" ]]
		then
			echo "${1^^},$route" >> "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt"
			echo "$route"
		elif [[ "${route,,}" == "unknown" ]] || [[ "${route,,}" == "null" ]]; then
			echo "${1^^},unknown" >> "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt"
		fi
}

GET_PS_PHOTO () {
	# Function to get a photo from PlaneSpotters.net
	# Usage: GET_PS_PHOTO ICAO [image|link|thumblink]
	# if [image|link|thumblink] is omitted, "link" is assumed
	# image: the path to the thumbnail image on disk
	# link: a link to the planespotters.net image page (not the image itself!)
	# thumblink: a link to the thumbnail image at planespotters.net's CDN

	local link
	local json
	local returntype
	local thumb

	returntype="${2:-link}"
	returntype="${returntype,,}"

	# shellcheck disable=SC2076
	if [[ ! " image link thumblink " =~ " $returntype " ]]; then
		return 1
	fi

	if ! $SHOWIMAGES; then return 0; fi

	if [[ -f "/usr/share/planefence/persist/planepix/cache/$1.notavailable" ]]; then
		return 0
	fi
	
	if [[ "$returntype" == "image" ]] && [[ -f "/usr/share/planefence/persist/planepix/cache/$1.jpg" ]]; then
		#echo in cache
		echo "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		return 0
	elif [[ "$returntype" == "link" ]] && [[ -f "/usr/share/planefence/persist/planepix/cache/$1.link" ]]; then
		#echo in cache
		echo "$(<"/usr/share/planefence/persist/planepix/cache/$1.link")"
		return 0
	elif [[ "$returntype" == "thumblink" ]] && [[ -f "/usr/share/planefence/persist/planepix/cache/$1.thumb.link" ]]; then
		#echo in cache
		echo "$(<"/usr/share/planefence/persist/planepix/cache/$1.thumb.link")"
		return 0
	fi

	# If we don't have a cached file, let's see if we can get one from PlaneSpotters.net
	if json="$(curl -ssL --fail "https://api.planespotters.net/pub/photos/hex/$1")" && \
					link="$(jq -r 'try .photos[].link | select( . != null )' <<< "$json")" && \
          thumb="$(jq -r 'try .photos[].thumbnail_large.src | select( . != null )' <<< "$json")" && \
				  [[ -n "$link" ]] && [[ -n "$thumb" ]]; then
		# If we have a link, let's download the photo
		curl -ssL --fail --clobber "$thumb" -o "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		echo "$link" > "/usr/share/planefence/persist/planepix/cache/$1.link"
		echo "$thumb" > "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
		touch -d "+$((HISTTIME+1)) days" "/usr/share/planefence/persist/planepix/cache/$1.link" "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
		#echo newly obtained
		if returntype="image"; then echo "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		elif returntype="link"; then echo "$link"
		elif returntype="thumblink"; then echo "$thumb"
		fi
		return 0
	else
		# If we don't have a link, let's clear the cache and return an empty string
		rm -f "/usr/share/planefence/persist/planepix/cache/$1.*"
		touch "/usr/share/planefence/persist/planepix/cache/$1.notavailable"
	fi
}

CREATE_NOISEPLOT () {
	# usage: CREATE_NOISEPLOT <callsign> <starttime> <endtime> <icao>
  
  if [[ -z "$REMOTENOISE" ]]; then return; fi
  
  local STARTTIME="$2"
	local ENDTIME="$3"
	local TITLE="Noise plot for $1 at $(date -d "@$2" +"%y%m%d-%H%M%S")"
	local NOWTIME="$(date +%s)"
	local NOISEGRAPHFILE="$OUTFILEDIR"/"noisegraph-$(date -d "@${STARTTIME}" +"%y%m%d-%H%M%S")-$4.png"
	# if the timeframe is less than 30 seconds, extend the ENDTIME to 30 seconds
	if (( ENDTIME - STARTTIME < 15 )); then ENDTIME=$(( STARTTIME + 15 )); fi
	STARTTIME=$(( STARTTIME - 15))
	# check if there are any noise samples
	if (( (NOWTIME - ENDTIME) > (ENDTIME - STARTTIME) )) && \
			[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log" ]] && \
			[[ "$(awk -v s="$STARTTIME" -v e="$ENDTIME" '$1>=s && $1<=e' /usr/share/planefence/persist/.internal/noisecapt-"$FENCEDATE".log | wc -l)" -gt "0" ]]
	then
		gnuplot -e "offset=$(echo "$(date +%z) * 36" | sed 's/+[0]\?//g' | bc); start=$STARTTIME; end=$ENDTIME; infile='/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log'; outfile='$NOISEGRAPHFILE'; plottitle='$TITLE'; margin=60" $PLANEFENCEDIR/noiseplot.gnuplot
	fi
}

CREATE_SPECTROGRAM () {
	# usage: CREATE_SPECTROGRAM <starttime> <endtime>
	# returns the file name of the spectrogram it got

  if [[ -z "$REMOTENOISE" ]]; then return; fi
  
	local STARTTIME="$1"
	local ENDTIME="$2"
	local sf spectrotime
	if (( ENDTIME - STARTTIME < 30 )); then ENDTIME=$(( STARTTIME + 30 )); fi

	# get the measurement from noisecapt-"$FENCEDATE".log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	spectrotime="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /usr/share/planefence/persist/.internal/noisecapt-"$FENCEDATE".log)"
	sf="noisecapt-spectro-$(date -d "@${spectrotime}" +"%y%m%d-%H%M%S").png"

	if [[ ! -s "$OUTFILEDIR/$sf" ]]; then
		# we don't have $sf locally, or if it's an empty file, we get it:
		curl -sSL "$REMOTENOISE/$sf" > "$OUTFILEDIR/$sf"
	fi
	# shellcheck disable=SC2012
	if [[ ! -s "$OUTFILEDIR/$sf" ]] || (( $(ls -s1 "$OUTFILEDIR/$sf" | awk '{print $1}') < 10 )); then
		# we don't have $sf (or it's an empty file) and we can't get it; so let's erase it in case it's an empty file:
		rm -f "$OUTFILEDIR/$sf"
	else
		echo "$sf"
	fi
}

CREATE_MP3 () {
	# usage: CREATE_MP3 <starttime> <endtime>
	# returns the file name of the MP3 file it got

  if [[ -z "$REMOTENOISE" ]]; then return; fi

	local STARTTIME="$1"
	local ENDTIME="$2"
	local mp3time mp3f
	(( ENDTIME - STARTTIME < 30 )) && ENDTIME=$(( STARTTIME + 30 ))

	# get the measurement from noisecapt-"$FENCEDATE".log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	mp3time="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /usr/share/planefence/persist/.internal/noisecapt-"$FENCEDATE".log)"
	mp3f="noisecapt-recording-$(date -d "@${mp3time}" +"%y%m%d-%H%M%S").mp3"

	if [[ ! -s "$OUTFILEDIR/$mp3f" ]]; then
		# we don't have $sf locally, or if it's an empty file, we get it:
		curl -sSL "$REMOTENOISE/$mp3f" > "$OUTFILEDIR/$mp3f"
	fi 
	# shellcheck disable=SC2012
	if [[ ! -s "$OUTFILEDIR/$mp3f" ]] || (( $(ls -s1 "$OUTFILEDIR/$mp3f" | awk '{print $1}') < 4 )); then
		# we don't have $mp3f (or it's an empty file) and we can't get it; so let's erase it in case it's an empty file:
		rm -f "$OUTFILEDIR/$mp3f"
	else
		echo "$mp3f"
	fi
}

# ==========================
# Just for debugging purposes:
# ==========================

if [[ "$1" == "reset" ]]; then
  rm -f "$STATE_LASTREC" "$RECORDSFILE"
  declare -A records
  records[maxindex]=-1
fi

# ==========================
# Collect new lines
# ==========================
readarray -t socketrecords <<< "$(
    { if [[ -f $STATE_LASTREC ]]; then
        read -r LASTPROCESSEDLINE < "$STATE_LASTREC"
        lastdate="$(awk -F, '{print $5}' <<< "$LASTPROCESSEDLINE")"

        # Check if last run was yesterday
        if [[ "$(date -d "$lastdate" +%y%m%d)" == "$YESTERDAY" ]]; then
            # Grab remainder of yesterday + all of today
            { grep -A999999 -F "$LASTPROCESSEDLINE" "$YESTERDAYFILE" 2>/dev/null || true; \
              cat "$TODAYFILE"; }
        else            # Just grab remainder of today
            grep -A999999 -F "$LASTPROCESSEDLINE" "$TODAYFILE" 2>/dev/null || true
        fi
    else
        # First run: all of today’s file
        cat "$TODAYFILE"
    fi; } \
      | awk -F, -v dist=$DIST -v maxalt=$MAXALT '$8 <= dist && $2 <= maxalt { print }' # filter by distance and altitude
)"
debug_time 1 "Getting socket records complete. Got ${#socketrecords[@]} records that are within $DIST distance and $MAXALT altitude"

# ==========================
# Process lines
# ==========================
if (( ${#socketrecords[@]} > 0 )); then
  for line in "${socketrecords[@]}"; do
    if [[ -z "$line" ]]; then continue; fi
    IFS=',' read -r hex_ident altitude lat lon date time angle distance squawk gs track callsign <<< "$line"

    # check if the item is in range

    # Check if the ICAO is already in the records and we are within COLLAPSEWITHIN
    # In the end, $idx will hold the index to the record that we need to fill or update
    idx=""
    if (( records[maxindex] >= 0 )); then
      for ((i=0; i<=${records[maxindex]}; i++)); do
        if [[ "${records[$i:icao]}" == "$hex_ident" ]] && (( $(date -d "$date $time" +%s) - ${records[$i:lastseen]:-0} <= COLLAPSEWITHIN )); then
          idx=$i
          break
        fi
      done
    fi
    if [[ -z "$idx" ]]; then
      # New record
      idx=$(( records[maxindex] + 1 ))
      records[maxindex]="$idx"
    fi

    # Minimum required fields
    if [[ -z "${records["$idx":icao]}" ]]; then records["$idx":icao]="$hex_ident"; fi
    if [[ -z "${records["$idx":callsign]}" ]]; then
      if [[ -n "$callsign" ]]; then
        records["$idx":callsign]="${callsign// /}";
      else
        records["$idx":callsign]="$(ICAO2TAIL $hex_ident)"
      fi
      if [[ -n "${records["$idx":callsign]}" ]]; then
        records["$idx":map_link]="https://globe.adsbexchange.com/?icao=$hex_ident&lat=$lat&lon=$lon&showTrace=$TODAY"
        records["$idx":fa_link]="https://flightaware.com/live/modes/${records[$index:icao]}/ident/${records[$index:callsign]}/redirect"
      fi
    fi
    if [[ -z "${records["$idx":firstseen]}" ]]; then records["$idx":firstseen]="$(date -d "$date $time" +%s)"; fi
    records["$idx":lastseen]="$(date -d "$date $time" +%s)"
    if [[ -n "$altitude" ]] && (( $(bc -l <<< "${altitude} < ${records["$idx":altitude]:-999999}") )); then records["$idx":altitude]="${altitude}"; fi
    if [[ -n "$distance" ]] && (( $(bc -l <<< "${distance} < ${records["$idx":distance]:-999999}") )); then records["$idx":distance]="${distance}"; fi

    if ! chk_disabled "$CHECKROUTE" && [[ -z ${records["$idx":route]} ]] && [[ -n "${records["$idx":callsign]}" ]]; then
      records["$idx":route]="$(GET_ROUTE "${records["$idx":callsign]}")"
      if [[ -n "${records["$idx":route]}" ]]; then records[HASROUTE]=true; fi
    fi
#echo "DEBUG: icao:${records["$idx":icao]} call:${records["$idx":callsign]} alt:${records["$idx":altitude]} dist:${records["$idx":distance]}"
    if [[ -z "${records["$idx":owner]}" ]]; then records["$idx":owner]="$(/usr/share/planefence/airlinename.sh "${records["$idx":callsign]}" "${records["$idx":icao]}")"; fi

    # Placeholders for later enrichment
    # records["$idx":notif_discord]=""
    # records["$idx":notif_mastodon]=""
    # records["$idx":notif_telegram]=""
    # records["$idx":notif_bluesky]=""
    # records["$idx":notif_mqtt]=""
    # records["$idx":image_thumblink]=""
    # records["$idx":image_weblink]=""
    # records["$idx":sound_peak]=""
    # records["$idx":sound_1min]=""
    # records["$idx":sound_5min]=""
    # records["$idx":sound_10min]=""
    # records["$idx":sound_1hour]=""
    # records["$idx":sound_loudness]=""
    # records["$idx":sound_color]=""
    # records["$idx":noisegraph_file]=""
    # records["$idx":noisegraph_link]=""
    # records["$idx":spectro_file]=""
    # records["$idx":spectro_link]=""
    # records["$idx":mp3_file]=""
    # records["$idx":mp3_link]=""
  #debug_time 2.1 "parsing socket30003 line $idx/${records["$idx":icao]}/${records["$idx":callsign]}"
  done

  debug_time 2 "parsing all socket30003 lines complete. Last record processed: ${records[${records[maxindex]}:icao]}/${records[${records[maxindex]}:callsign]}"

  # ==========================
  # Save state
  # ==========================
  debug_time 3 "saving state. STATE_LASTREC: $STATE_LASTREC, RECORDS_FILE: $RECORDSFILE"
  echo "${socketrecords[-1]}" > "$STATE_LASTREC"
  declare -p records > "$RECORDSFILE"

  # ==========================
  # Emit CSV snapshot
  # ==========================
  {
      echo "index,icao,callsign,firstseen,lastseen,altitude,distance,route,notified,map_link,fa_link,owner,notif_link,notif_service,image_thumblink,image_weblink,sound_peak,sound_1min,sound_5min,sound_10min,sound_1hour,sound_loudness,sound_color,noisegraph_file,noisegraph_link,spectro_file,spectro_link,mp3_file,mp3_link"
      for ((i=0; i<maxindex; i++)); do
          idx=$(printf "%02d" "$i")
          echo "$idx,${records["$idx":icao]},${records["$idx":callsign]},${records["$idx":firstseen]},${records["$idx":lastseen]},${records["$idx":altitude]},${records["$idx":distance]},${records["$idx":route]},${records["$idx":notified]},${records["$idx":map_link]},${records["$idx":fa_link]},${records["$idx":owner]},${records["$idx":notif_link]},${records["$idx":notif_service]},${records["$idx":image_thumblink]},${records["$idx":image_weblink]},${records["$idx":sound_peak]},${records["$idx":sound_1min]},${records["$idx":sound_5min]},${records["$idx":sound_10min]},${records["$idx":sound_1hour]},${records["$idx":sound_loudness]},${records["$idx":sound_color]},${records["$idx":noisegraph_file]},${records["$idx":noisegraph_link]},${records["$idx":spectro_file]},${records["$idx":spectro_link]},${records["$idx":mp3_file]},${records["$idx":mp3_link]}"
      done
  } > "$CSVOUT"

  # ==========================
  # Emit JSON snapshot
  # ==========================
  {
      echo "["
      first=true
      for ((i=0; i<maxindex; i++)); do
          idx=$(printf "%02d" "$i")
          $first || echo ","
          first=false
          cat <<EOF
{
  "index": "$idx",
  "icao": "${records["$idx":icao]}",
  "callsign": "${records["$idx":callsign]}",
  "firstseen": "${records["$idx":firstseen]}",
  "lastseen": "${records["$idx":lastseen]}",
  "altitude": "${records["$idx":altitude]}",
  "distance": "${records["$idx":distance]}",
  "route": "${records["$idx":route]}",
  "notified": "${records["$idx":notified]}",
  "map_link": "${records["$idx":map_link]}",
  "fa_link": "${records["$idx":fa_link]}",
  "owner": "${records["$idx":owner]}",
  "notif_link": "${records["$idx":notif_link]}",
  "notif_service": "${records["$idx":notif_service]}",
  "image_thumblink": "${records["$idx":image_thumblink]}",
  "image_weblink": "${records["$idx":image_weblink]}",
  "sound_peak": "${records["$idx":sound_peak]}",
  "sound_1min": "${records["$idx":sound_1min]}",
  "sound_5min": "${records["$idx":sound_5min]}",
  "sound_10min": "${records["$idx":sound_10min]}",
  "sound_1hour": "${records["$idx":sound_1hour]}",
  "sound_loudness": "${records["$idx":sound_loudness]}",
  "sound_color": "${records["$idx":sound_color]}",
  "noisegraph_file": "${records["$idx":noisegraph_file]}",
  "noisegraph_link": "${records["$idx":noisegraph_link]}",
  "spectro_file": "${records["$idx":spectro_file]}",
  "spectro_link": "${records["$idx":spectro_link]}",
  "mp3_file": "${records["$idx":mp3_file]}",
  "mp3_link": "${records["$idx":mp3_link]}"
}
EOF
      done
      echo "]"
  } > "$JSONOUT"

fi
