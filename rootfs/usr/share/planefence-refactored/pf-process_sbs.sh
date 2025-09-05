#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2155
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

## DEBUG stuff:
execstarttime="$(date +%s.%3N)"
execlaststeptime="$execstarttime"
DEBUG=true

##
source /scripts/common
source /usr/share/planefence/planefence.conf

# ==========================
# Config and initialization
# ==========================
HTMLDIR="/tmp"
#HTMLDIR="${OUTFILEDIR:-/usr/share/planefence/html}"
mkdir -p "$HTMLDIR"

TODAY="$(date +%y%m%d)"
YESTERDAY="$(date -d "yesterday" +%y%m%d)"
NOWTIME="$(date +%s)"

TODAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${TODAY}.txt" -print0 | xargs -0 ls -t | head -n 1)"
YESTERDAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${YESTERDAY}.txt" -print0 | xargs -0 ls -t | head -n 1)"

RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"
YESTERDAYRECORDSFILE="$HTMLDIR/.planefence-records-${YESTERDAY}"

CSVOUT="$HTMLDIR/planefence-${TODAY}.csv"
JSONOUT="$HTMLDIR/planefence-${TODAY}.json"

LASTSOCKETRECFILE="/usr/share/planefence/persist/.planefence-state-lastrec"

if [[ -f "$RECORDSFILE" ]]; then
    source "$RECORDSFILE"
else
    declare -A records recidx
    records[maxindex]=-1
fi

if [[ -f "$IGNORELIST" ]]; then
    sed -i '/^$/d' "$IGNORELIST" 2>/dev/null  # clean empty lines from ignorelist
else
    touch "$IGNORELIST"
fi

if [[ -n $REMOTENOISE ]]; then
  noiselist="$(curl -fsSL "$REMOTENOISE" 2>/dev/null)"
fi
# ==========================
# Functions
# ==========================

debug_print() {
    local currenttime
    if [[ -z "$execstarttime" ]]; then
      execstarttime="$(date +%s.%3N)"
      execlaststeptime="$execstarttime"
    fi
    currenttime="$(date +%s.%3N)"
    if chk_enabled "$DEBUG"; then 
      "${s6wrap[@]}" printf "[DEBUG] %s (%s secs, total time elapsed %s secs)\n" "$1" "$(bc -l <<< "$currenttime - $execlaststeptime")" "$(bc -l <<< "$currenttime - $execstarttime")" >&2
    fi
    execlaststeptime="$currenttime"
}

ICAO2TAIL() {
  local icao="$1"
  local tail=""

	# See if we have it somewhere in the socket30003 file:
  tail="$(awk -F "," -v icao="$icao" '($1 == icao && $12 != "") {print $12;exit;}' "$RECORDSFILE" 2>/dev/null)"
	if [[ -n "$tail" ]]; then echo "${tail// /}"; exit; fi

  # Look up the ICAO in the mictronics database (local copy) if we have it downloaded:
	if [[ -f /run/planefence/icao2plane.txt ]]; then
		tail="$(grep -i -w "$icao" /run/planefence/icao2plane.txt 2>/dev/null | head -1 | awk -F "," '{print $2}')"
	fi
	if [[ -n "$tail" ]]; then echo "${tail// /}"; exit; fi

	# If the ICAO starts with "A" and there is no flight or tail number, let's algorithmically determine the tail number
	if [[ "${icao:0:1}" == "A" ]]; then
		tail="$(/usr/share/planefence/icao2tail.py "$icao")"
	fi
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

		if route="$(curl -fsSL -X 'POST' 'https://api.adsb.lol/api/0/routeset' \
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
	if json="$(curl -fsSL --fail "https://api.planespotters.net/pub/photos/hex/$1")" && \
					link="$(jq -r 'try .photos[].link | select( . != null )' <<< "$json")" && \
          thumb="$(jq -r 'try .photos[].thumbnail_large.src | select( . != null )' <<< "$json")" && \
				  [[ -n "$link" ]] && [[ -n "$thumb" ]]; then
		# If we have a link, let's download the photo
		curl -fsSL --fail --clobber "$thumb" -o "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		echo "$link" > "/usr/share/planefence/persist/planepix/cache/$1.link"
		echo "$thumb" > "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
		touch -d "+$((HISTTIME+1)) days" "/usr/share/planefence/persist/planepix/cache/$1.link" "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
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

GET_NOISEDATA () {
  # Get noise data from the remote server
  # It returns the average values over the specified time range
  # Usage: GET_NOISEDATA <firstseen_epoch> [<lastseen_epoch>]
  if [[ -z "$REMOTENOISE" ]] || [[ -z "$1" ]]; then return; fi
  local firstseen lastseen samplescount=0 ts level level_1min level_5min level_10min level_1hr loudness color avglevel avg1min avg5min avg10min avg1hr

  firstseen="$1"
  if [[ -z "$lastseen" ]] || (( lastseen - firstseen < 15 )); then lastseen="$(( firstseen + 15 ))"; fi

  # check if we can get the noisecapt log:
  if [[ -z "$noiselog" ]]; then
    if ! curl -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$1" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
      return
    fi
    noiselog="$(</tmp/noisecapt.log)"
  fi

  while IFS=, read -r ts level level_1min level_5min level_10min level_1hr; do
    if (( ts >= firstseen )) && (( ts <= lastseen )); then
      (( samplescount++ )) || true
      avglevel="$(( avglevel + level ))"
      avg1min="$(( avg1min + level_1min ))"
      avg5min="$(( avg5min + level_5min ))"
      avg10min="$(( avg10min + level_10min ))"
      avg1hr="$(( avg1hr + level_1hr ))"
    elif (( ts > lastseen )); then
      break
    fi
  done <<< "$noiselog"
    if (( samplescount > 0 )); then
      avglevel="$(( avglevel/samplescount ))"
      avg1min="$(( avg1min/samplescount ))"
      avg5min="$(( avg5min/samplescount ))"
      avg10min="$(( avg10min/samplescount ))"
      avg1hr="$(( avg1hr/samplescount ))"

      loudness="$(( avglevel - avg1hr ))"
      if (( loudness > YELLOWLIMIT )); then color="$RED"
      elif (( loudness > GREENLIMIT )); then color="$YELLOW"
      else color="$GREEN"; fi

      echo "$avglevel $avg1min $avg5min $avg10min $avg1hr $loudness $color"
    fi
}

CREATE_NOISEPLOT () {
	# usage: CREATE_NOISEPLOT <callsign> <starttime> <endtime> <icao>
  
  if [[ -z "$REMOTENOISE" ]]; then return; fi
  
  local STARTTIME="$2"
	local ENDTIME="$3"
	local TITLE="Noise plot for $1 at $(date -d "@$2" +"%y%m%d-%H%M%S")"
	local NOISEGRAPHFILE="$OUTFILEDIR"/"noisegraph-$(date -d "@${STARTTIME}" +"%y%m%d-%H%M%S")-$4.png"
  # check if we can get the noisecapt log:
  if [[ -z "$noiselog" ]]; then
    if ! curl -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$1" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
      return
    fi
    noiselog="$(</tmp/noisecapt.log)"
  fi
  
	# if the timeframe is less than 30 seconds, extend the ENDTIME to 30 seconds
	if (( ENDTIME - STARTTIME < 15 )); then ENDTIME=$(( STARTTIME + 15 )); fi
	STARTTIME=$(( STARTTIME - 15))
	# check if there are any noise samples
	if (( (NOWTIME - ENDTIME) > (ENDTIME - STARTTIME) )) && \
			[[ -f "/tmp/noisecapt.log" ]] && \
			[[ "$(awk -v s="$STARTTIME" -v e="$ENDTIME" '$1>=s && $1<=e' "/tmp/noisecapt.log" | wc -l)" -gt "0" ]]
	then
		if gnuplot -e "offset=$(echo "$(date +%z) * 36" | sed 's/+[0]\?//g' | bc); start=$STARTTIME; end=$ENDTIME; infile='/tmp/noisecapt.log'; outfile='$NOISEGRAPHFILE'; plottitle='$TITLE'; margin=60" "$PLANEFENCEDIR/noiseplot.gnuplot"; then
			# Plotting succeeded
      echo "$NOISEGRAPHFILE"
		fi
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

  # check if we can get the noisecapt log:
  if [[ -z "$noiselog" ]]; then
    if ! curl -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$1" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
      return
    fi
    noiselog="$(</tmp/noisecapt.log)"
  fi
  
	# get the measurement from /tmp/noisecapt.log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	spectrotime="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /tmp/noisecapt.log)"
  if [[ "$spectrotime" == "0" ]]; then return; fi
	sf="noisecapt-spectro-${spectrotime}.png"

	if [[ ! -s "$OUTFILEDIR/$sf" ]]; then
		# we don't have $sf locally, or if it's an empty file, we get it:
		# shellcheck disable=SC2076
		if ( [[ $noiselist =~ "$sf" ]] && ! curl -fsSL "$REMOTENOISE/$sf" > "$OUTFILEDIR/$sf" 2>/dev/null ) || (( $(if [[ -f "$sf" ]]; then find "$(dirname "$sf")" -name "$(basename "$sf")" -exec stat -c "%s" {} \;; else echo "0"; fi) < 10 )); then
      rm -f "$OUTFILEDIR/$sf"
      return
    fi
	fi
  
  echo "$OUTFILEDIR/$sf"
}

CREATE_MP3 () {
	# usage: CREATE_MP3 <starttime> <endtime>
	# returns the file name of the MP3 file it got

  if [[ -z "$REMOTENOISE" ]]; then return; fi

	local STARTTIME="$1"
	local ENDTIME="$2"
	local mp3time mp3f
	(( ENDTIME - STARTTIME < 30 )) && ENDTIME=$(( STARTTIME + 30 ))

  # check if we can get the noisecapt log:
  if [[ -z "$noiselog" ]]; then
    if ! curl -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$1" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
      return
    fi
    noiselog="$(</tmp/noisecapt.log)"
  fi

	# get the measurement from noisecapt-"$FENCEDATE".log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	mp3time="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /tmp/noisecapt.log)"
	mp3f="noisecapt-recording-${mp3time}.mp3"

	# shellcheck disable=SC2076
	if [[ ! -s "$OUTFILEDIR/$mp3f" ]] && [[ $noiselist =~ "$mp3f" ]] ; then
		# we don't have $sf locally, or if it's an empty file, we get it:
		curl -fsSL "$REMOTENOISE/$mp3f" > "$OUTFILEDIR/$mp3f" 2>/dev/null
	fi 
	# shellcheck disable=SC2012
	if [[ ! -s "$OUTFILEDIR/$mp3f" ]] || (( $(ls -s1 "$OUTFILEDIR/$mp3f" | awk '{print $1}') < 4 )); then
		# we don't have $mp3f (or it's an empty file) and we can't get it; so let's erase it in case it's an empty file:
		rm -f "$OUTFILEDIR/$mp3f"
	else
		echo "$OUTFILEDIR/$mp3f"
	fi
}

debug_print "Hello. Starting $0"

# ==========================
# Just for debugging purposes:
# ==========================

if [[ "$1" == "reset" ]]; then
  debug_print "Resetting records"
  rm -f "$LASTSOCKETRECFILE" "$RECORDSFILE" "$CSVOUT" "$JSONOUT"
  unset records recidx
  declare -A records 
  declare -A recidx
  records[maxindex]="-1"
fi

debug_print "Collecting new records"
# ==========================
# Collect new lines
# ==========================
readarray -t socketrecords <<< "$(
    { if [[ -f $LASTSOCKETRECFILE ]]; then
        read -r LASTPROCESSEDLINE < "$LASTSOCKETRECFILE"
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
      | tac \
      | grep -v -i -f "$IGNORELIST" 2>/dev/null \
      | awk -F, -v dist="$DIST" -v maxalt="$MAXALT" '$8 <= dist && $2 <= maxalt { print }'
  )"
debug_print "Got ${#socketrecords[@]} records that are within $DIST distance and $MAXALT altitude. Initial processing..."

# ==========================
# Process lines
# ==========================
if (( ${#socketrecords[@]} > 0 )); then
  for line in "${socketrecords[@]}"; do
    if [[ -z "$line" ]]; then continue; fi
    IFS=',' read -r hex_ident altitude lat lon date time angle distance squawk gs track callsign <<< "$line"
    if [[ "$hex_ident" == "hex_ident" ]]; then continue; fi # skip header line
    idx=""
    ignore_this_dupe=false
    seentime="$(date -d "$date ${time%%.*}" +%s)"

    # Check if the ICAO is already in the records and we are within COLLAPSEWITHIN
    if (( records[maxindex] >= 0 )); then
      for ((i=0; i<=records[maxindex]; i++)); do
        if [[ "${records[$i:icao]}" == "$hex_ident" ]]; then
          # we found an existing record for this plane
          if (( ${records["$i":lastseen]} - seentime <= COLLAPSEWITHIN && ${records["$i":lastseen]} - seentime >= 0 )); then
            # We found an existing record and we are within COLLAPSEWITHIN seconds
            idx=$i
            #echo "DEBUG: update record $idx: [$hex_ident] Seentime=$seentime ($(date -d @"$seentime")), lastseen=${records["$i":lastseen]} diff $(( ${records["$i":lastseen]}-seentime )), firstseen=${records["$i":firstseen]} diff $(( ${records["$i":firstseen]}-seentime ))"
            break
          fi
          # If we're make it here, then there is an existing record outside the COLLAPSEWITHIN window
          # Let's make sure that the old record's COMPLETE flag is set.
          records["$i":complete]=true
          if chk_enabled "$IGNOREDUPES"; then
            # We found an existing record outside the COLLAPSEWITHIN window and duplicates are ignored
            # We can't directly break this loop and continue the next loop, so we'll set a flag
            ignore_this_dupe=true
            #echo "DEBUG: dupe ignored record $i: [$hex_ident] Seentime=$seentime ($(date -d @"$seentime")), lastseen=${records["$i":lastseen]} diff $(( ${records["$i":lastseen]}-seentime )), firstseen=${records["$i":firstseen]} diff $(( ${records["$i":firstseen]}-seentime ))"
            break
          fi
          #echo "DEBUG: dupe potential record $i: [$hex_ident] Seentime=$seentime ($(date -d @"$seentime")), lastseen=${records["$i":lastseen]} diff $(( ${records["$i":lastseen]}-seentime )), firstseen=${records["$i":firstseen]} diff $(( ${records["$i":firstseen]}-seentime ))"
        fi
      done
    fi
    if $ignore_this_dupe; then
      # If we found an existing record and duplicates are ignored, we can skip this one
      continue
    fi
    if [[ -z "$idx" ]]; then
      # New record
      idx=$(( records[maxindex] + 1 ))
      records[maxindex]="$idx"
      # echo "DEBUG: new record $idx: [$hex_ident] Seentime=$seentime ($(date -d @"$seentime"))"
    fi
    #echo "DEBUG: processing index $idx..." 

    # Now we know the record index and we can start adding or updating values for it
    if [[ -z "${records["$idx":icao]}" ]]; then records["$idx":icao]="$hex_ident"; fi
    callsign="${callsign//[[:space:]]/}"  # remove spaces from callsign
    if [[ -n "$callsign" ]]; then
        records["$idx":callsign]="$callsign"  
        records["$idx":fa_link]="https://flightaware.com/live/modes/$hex_ident/ident/$callsign/redirect"
    fi

    if [[ -z "${records["$idx":map_link]}" ]]; then records["$idx":map_link]="https://globe.adsbexchange.com/?icao=$hex_ident&lat=$lat&lon=$lon&showTrace=$TODAY"; fi
    records["$idx":firstseen]="$seentime"
    if [[ -z "${records["$idx":lastseen]}" ]]; then records["$idx":lastseen]="$seentime"; fi
    newdist="$(awk "BEGIN { if ($distance < ${records["$idx":distance]:-999999}) print $distance }")"
    if [[ -n "$newdist" ]]; then 
      records["$idx":distance]="$newdist"
      if [[ -n "$lat" ]]; then records["$idx":lat]="$lat"; fi
      if [[ -n "$lon" ]]; then records["$idx":lon]="$lon"; fi
      if [[ -n "$altitude" ]]; then records["$idx":altitude]="$altitude"; fi
      if [[ -n "$angle" ]]; then records["$idx":angle]="$angle"; fi
      if [[ -n "$gs" ]]; then records["$idx":groundspeed]="$gs"; fi
      if [[ -n "$track" ]]; then records["$idx":track]="$track"; fi
      records["$idx":time_at_mindist]="$seentime"
      if [[ -n "$squawk" ]]; then records["$idx":squawk]="$squawk"; fi
    fi
    if [[ -z "${records["$idx":squawk]}" ]]; then
      records["$idx":squawk]="$squawk"
    fi

    # Placeholders for later enrichment
    # records["$idx":notif_discord]=""
    # records["$idx":notif_mastodon]=""
    # records["$idx":notif_telegram]=""
    # records["$idx":notif_bluesky]=""
    # records["$idx":notif_mqtt]=""
    # records["$idx":noisegraph_file]=""
    # records["$idx":noisegraph_link]=""
    # records["$idx":spectro_file]=""
    # records["$idx":spectro_link]=""
    # records["$idx":mp3_file]=""
    # records["$idx":mp3_link]=""
  done

  debug_print "Initial processing complete. Continuing to add callsigns, routes, and owners."

  # try to pre-seed the noisecapt log:
  if curl -fsSL "$REMOTENOISE/noisecapt-$TODAY.log" >/tmp/noisecapt.log 2>/dev/null; then
    noiselog="$(</tmp/noisecapt.log)"
  fi  
  
  # Now try to add callsigns and owners for those that don't already have them:
  for ((idx=0; idx<records[maxindex]; idx++)); do

    # Add complete label if current time is outside COLLAPSEWITHIN window
    if [[ -z "${records["$idx":complete]}" ]] && (( NOWTIME - ${records["$idx":lastseen]} > COLLAPSEWITHIN )); then
      records["$idx":complete]="true"
    fi

    # Add a callsign if there isn't any
    if [[ -z "${records["$idx":callsign]}" ]]; then
      callsign="$(ICAO2TAIL "${records["$idx":icao]}")"
      records["$idx":callsign]="${callsign//[[:space:]]/}"
      records["$idx":fa_link]="https://flightaware.com/live/modes/$hex_ident/ident/${callsign//[[:space:]]/}/redirect/"
    fi

    # get the owner's name
    if ! chk_enabled "${records["$idx":owner_checked]}" && [[ -z "${records["$idx":owner]}" ]] && [[ -n "${records["$idx":callsign]}" ]]; then
      records["$idx":owner]="$(/usr/share/planefence/airlinename.sh "${records["$idx":callsign]}" "${records["$idx":icao]}" 2>/dev/null)"
      records["$idx":owner_checked]=true
    fi

    # get route information
    if ! chk_disabled "$CHECKROUTE" && \
       ! chk_enabled "${records["$idx":route_checked]}" && \
       [[ -z ${records["$idx":route]} ]] && \
       [[ -n "${records["$idx":callsign]}" ]]; then
          records["$idx":route]="$(GET_ROUTE "${records["$idx":callsign]}")"
          if [[ -n "${records["$idx":route]}" ]]; then records[HASROUTE]=true; fi
          records["$idx":route_checked]=true
    fi

    # get images
    if chk_enabled "$SHOWIMAGES" && \
       ! chk_enabled "${records["$idx":image_checked]}" && \
       [[ -z "${records["$idx":image_thumblink]}" ]] && \
       [[ -n "${records["$idx":icao]}" ]]; then
          records["$idx":image_thumblink]="$(GET_PS_PHOTO "${records["$idx":icao]}" "thumblink")"
          records["$idx":image_link]="$(GET_PS_PHOTO "${records["$idx":icao]}" "link")"
          records["$idx":image_file]="$(GET_PS_PHOTO "${records["$idx":icao]}" "image")"
          records["$idx":image_checked]=true
          records[HASIMAGES]=true
    fi

    # Add noisecapt stuff
    # pre-seed the log

    if [[ -n "$REMOTENOISE" ]] && \
       ! chk_enabled "${records["$idx":noisedata_checked]}" && \
       chk_enabled "${records["$idx":complete]}" && \
       [[ -z "${records["$idx":sound_peak]}" ]]; then
          read -r records["$idx":sound_peak] records["$idx":sound_1min] records["$idx":sound_5min] records["$idx":sound_10min] records["$idx":sound_1hour] records["$idx":sound_loudness] records["$idx":sound_color] <<< "$(GET_NOISEDATA "${records["$idx":firstseen]}" "${records["$idx":lastseen]}")"
          records["$idx":noisedata_checked]=true
          records[HASNOISE]=true
    fi
    if [[ -n "$REMOTENOISE" ]] && \
       ! chk_enabled "${records["$idx":noisegraph_checked]}" && \
       chk_enabled "${records["$idx":complete]}" && \
       [[ -z "${records["$idx":noisegraph_file]}" ]] && \
       [[ -n "${records["$idx":icao]}" ]]; then
          records["$idx":noisegraph_file]="$(CREATE_NOISEPLOT "${records["$idx":callsign]:-${records["$idx":icao]}}" "${records["$idx":firstseen]}" "${records["$idx":lastseen]}" "${records["$idx":icao]}")"
          if [[ -n "${records["$idx":noisegraph_file]}" ]]; then
            records["$idx":noisegraph_link]="$(basename "${records["$idx":noisegraph_file]}")"
          fi
          records["$idx":spectro_file]="$(CREATE_SPECTROGRAM "${records["$idx":firstseen]}" "${records["$idx":lastseen]}")"
          if [[ -n "${records["$idx":spectro_file]}" ]]; then
            records["$idx":spectro_link]="$(basename "${records["$idx":spectro_file]}")"
          fi
          records["$idx":mp3_file]="$(CREATE_MP3 "${records["$idx":firstseen]}" "${records["$idx":lastseen]}")"
          if [[ -n "${records["$idx":mp3_file]}" ]]; then
            records["$idx":mp3_link]="$(basename "${records["$idx":mp3_file]}")"
          fi
          records["$idx":noisegraph_checked]=true
    fi

  done

  if ! chk_enabled "${records[HASROUTE]}"; then records[HASROUTE]=false; fi
  if ! chk_enabled "${records[HASIMAGES]}"; then records[HASIMAGES]=false; fi
  if ! chk_enabled "${records[HASNOISE]}"; then records[HASNOISE]=false; fi
  if ! chk_enabled "${records[HASNOTIFS]}"; then records[HASNOTIFS]=false; fi

  debug_print "Processing complete. Last record processed: ${records[${records[maxindex]}:icao]}/${records[${records[maxindex]}:callsign]}. Maxindex=${records[maxindex]}. Now writing results to disk..."

  # ==========================
  # Save state
  # ==========================
  echo "${socketrecords[0]}" > "$LASTSOCKETRECFILE"
  declare -p records recidx > "$RECORDSFILE"

  # ==========================
  # Emit CSV snapshot
  # ==========================

  # shellcheck disable=SC2207
  keys=($(printf '%s\n' "${!records[@]}" | awk -F'[:\\]]' '!seen[$2]++ {print $2}' | sort -u))
  printf -v csvindex "%s," "${keys[@]}"; csvindex="${csvindex:0:-1}"

  {
      echo "index,$csvindex"
      for ((idx=0; idx<records[maxindex]; idx++)); do
          csv="$idx,"
          for key in "${keys[@]}"; do
              csv+="${records["$idx":$key]},"
          done
          echo "${csv:0:-1}"
      done
  } > "$CSVOUT"

  # ==========================
  # Emit JSON snapshot
  # ==========================
  {
      echo "["
      sep=""
      for ((idx=0; idx<records[maxindex]; idx++)); do
          printf '%s{\n' "$sep"
          sep=","
          keysep=""
          for key in "${keys[@]}"; do
              val=${records["$idx":$key]}
              # Escape quotes and backslashes for JSON safety
              val=${val//\\/\\\\}
              val=${val//\"/\\\"}
              printf '%s "%s":"%s"' "$keysep" "$key" "$val"
              keysep=","
          done
          echo -e "\n}"
      done
      echo "]"
  } > "$JSONOUT"

fi

debug_print "Done."
