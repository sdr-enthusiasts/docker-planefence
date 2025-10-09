#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2155
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

## DEBUG stuff:
# DEBUG=true

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf
echo "$" > /run/planefence.pid

# ==========================
# Config and initialization
# ==========================
#HTMLDIR="/tmp"
HTMLDIR="${OUTFILEDIR:-/usr/share/planefence/html}"
mkdir -p "$HTMLDIR"

TODAY="$(date +%y%m%d)"
YESTERDAY="$(date -d "yesterday" +%y%m%d)"
NOWTIME="$(date +%s)"

TODAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${TODAY}.txt" -print | sort | head -n 1)"
YESTERDAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${YESTERDAY}.txt" -print | sort | head -n 1)"

RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}.gz"
YESTERDAYRECORDSFILE="$HTMLDIR/.planefence-records-${YESTERDAY}.gz"

CSVOUT="$HTMLDIR/planefence-${TODAY}.csv"
JSONOUT="$HTMLDIR/planefence-${TODAY}.json"

# Precompute midnight of today only once:
midnight_epoch=$(date -d "$(date +%F) 00:00:00" +%s)
today_ymd=$(date +%Y/%m/%d)
yesterday_epoch=$(date -d yesterday +%s)

# constants
COLLAPSEWITHIN_SECS=${COLLAPSEWITHIN:?}
declare -A last_idx_for_icao   # icao -> most recent idx within window
declare -A lastseen_for_icao   # icao -> lastseen epoch
declare -A heatmap            # lat,lon -> count
declare -a updatedrecords

if [[ -z "$TRACKSERVICE" ]] || [[ "${TRACKSERVICE,,}" == "adsbexchange" ]]; then
  TRACKURL="globe.adsbexchange.com"
elif [[ "${TRACKSERVICE,,}" == "flightaware" ]]; then
  TRACKURL="flightaware"
elif [[ -n "$TRACKSERVICE" ]]; then
  TRACKURL="$(sed -E 's|^(https?://)?([^/]+).*|\2|' <<< "$TRACKSERVICE")"
else
  TRACKURL="globe.adsbexchange.com"
fi

# ==========================
# Functions
# ==========================

GET_TAIL() {
  # Usage: GET_TAIL "$icao"
  local icao=${1^^}

  # see if it's in our own cache first
  if [[  -f "/usr/share/planefence/persist/.internal/icao2tail.cache" ]]; then
    tail="$(awk -F, -v icao="$icao" '$1 == icao {print $2; exit}' "/usr/share/planefence/persist/.internal/icao2tail.cache")"
    if [[ -n "$tail" ]]; then
      echo "${tail// /}"
      return
    fi
  fi

  # Look up the ICAO in the mictronics database (local copy) if we have it downloaded:  
	if [[ -f /run/planefence/icao2plane.txt ]]; then
		tail="$(grep -m1 -i -F "$icao" /run/planefence/icao2plane.txt 2>/dev/null | awk -F, '{print $2}')"
	fi

  # If there is a OpenSkyDB file, check that one:
  if [[ -z "$tail" ]] && [[ -f /run/OpenSkyDB.csv ]]; then
    tail="$(grep -m1 -i -F "$icao" /run/OpenSkyDB.csv | awk -F, '{print $27}')"
    tail="${tail//[ \"\']/}"
  fi

	# If the ICAO starts with "A"  (but is not in  the range of AExxxx ADExxx ADFxxx - those are US military without N number) and there is no flight or tail number, let's algorithmically determine the tail number
	if [[ -z "$tail" ]] &&  [[ "$icao" =~ ^A && ! "$icao" =~ ^AE && ! "$icao" =~ ^ADE && ! "$icao" =~ ^ADF ]]; then
		tail="$(/usr/share/planefence/icao2tail.py "$icao")"
	fi
	if [[ -n "$tail" ]]; then 
    echo "$icao,${tail// /}" >> "/usr/share/planefence/persist/.internal/icao2tail.cache"
    echo "${tail// /}"
    return
  fi
}

GET_CALLSIGN() {
  local icao="$1"
  local tail=""

	# See if we have it somewhere in the socket30003 file:
  tail="$(tac "$RECORDSFILE" | awk -F "," -v icao="$icao" '($1 == icao && $12 != "") {print $12;exit;}' 2>/dev/null)"
	if [[ -n "$tail" ]]; then echo "${tail// /}"; return; fi

  # If it's not there, then use GET_TAIL to replace the callsign with the tail number
  GET_TAIL "$icao"
  return
}

GET_TYPE () {
  local apiUrl="https://api.adsb.lol/v2/hex"
  curl -sSL "$apiUrl/$1" | jq -r '.ac[] .t' 2>/dev/null
}

GET_ROUTE_BULK () {
  # function to get a route by callsign. Must have a callsign - ICAO won't work
  # Usage: GET_ROUTE <callsign>
  # Uses the adsb.im API to retrieve the route

  local apiUrl="https://adsb.im/api/0/routeset"
  declare -A routesarray=()
  declare -a indexarray=()
  local idx line call route plausible

  # first comb through records[] to get the callsigns we need to look up the route for
  for (( idx=0; idx<=records[maxindex]; idx++ )); do
    if ! chk_enabled "${records["$idx":route:checked]}" && [[ -n "${records["$idx":callsign]}" ]]; then
      routesarray["$idx":callsign]="${records["$idx":callsign]:-${records["$idx":tail]}}"
      routesarray["$idx":lat]="${records["$idx":lat]}"
      routesarray["$idx":lon]="${records["$idx":lon]}"
      indexarray+=("$idx")
    fi
  done

  # If there's anything to be looked up, then create a JSON object and submit it to the API. The call returns a comma separated object with call,route,plausibility(boolean)
  if (( ${#indexarray[@]} > 0 )); then
    records[HASROUTE]=true
    json='{ "planes": [ '
    for idx in "${indexarray[@]}"; do
      json+="{ \"callsign\":\"${routesarray["$idx":callsign]}\", \"lat\": ${routesarray["$idx":lat]}, \"lng\": ${routesarray["$idx":lon]} },"
    done
    json="${json:0:-1}" # strip the final comma
    json+=" ] }" # terminate the JSON object

    while read -r line; do
      IFS=, read -r call route plausible <<< "$line"

      # get the routes, process them line by line.
      # Example results: RPA5731,BOS-PIT-BOS,true\nRPA5631,IND-BOS,true\nN409FZ,unknown,null\n

      for idx in "${indexarray[@]}"; do
        if [[ "${routesarray["$idx":callsign]}" == "$call" ]]; then
          if [[ -z "$route" ]] || [[ "$route" == "unknown" ]] || [[ "$route" == "null" ]]; then
            records["$idx":route]="n/a"
          else
            records["$idx":route]="$route"
            if chk_disabled "$plausibe"; then records["$idx":route]=+" (?)";fi
          fi
        records["$idx":route:checked]=true
        fi
      done

    done <<< "$(curl -sSL -X 'POST' "$apiUrl" -H 'accept: application/json' -H 'Content-Type: application/json' -d "$json" | jq -r '.[] | [.callsign, ._airport_codes_iata, (.plausible|tostring)] | @csv  | gsub("\"";"")')"
  fi
}

GET_ROUTE_INDIVIDUAL () {
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
  # Usage: GET_PS_PHOTO ICAO [image|link|thumblink]
  local icao="$1" returntype json link thumb CACHETIME
  returntype="${2:-link}"; returntype="${returntype,,}"

  # validate
  case "$returntype" in
    image) ;;
    link) ;;
    thumblink) ;;
    *) return 1;;
  esac

  $SHOWIMAGES || return 0

  CACHETIME=$((3 * 24 * 3600))  # 3 days in seconds

  local dir="/usr/share/planefence/persist/planepix/cache"
  local jpg="$dir/$icao.jpg"
  local lnk="$dir/$icao.link"
  local tlnk="$dir/$icao.thumb.link"
  local na="$dir/$icao.notavailable"

  [[ -f "$na" ]] && return 0

  # cache hits
  case "$returntype" in
    image)     if [[ -f "$jpg"  ]] && (( $(date +%s) - $(stat -c %Y -- "$jpg") < CACHETIME )); then printf '%s\n' "$jpg";  return 0; fi ;;
    link)      if [[ -f "$lnk"  ]] && (( $(date +%s) - $(stat -c %Y -- "$lnk") < CACHETIME )); then cat "$lnk"; return 0; fi ;;
    thumblink) if [[ -f "$tlnk" ]] && (( $(date +%s) - $(stat -c %Y -- "$tlnk") < CACHETIME )); then cat "$tlnk"; return 0; fi ;;
  esac

  # fetch
  if json="$(curl -fsSL --fail "https://api.planespotters.net/pub/photos/hex/$icao")" && \
     link="$(jq -r 'try .photos[].link | select(. != null) | .' <<<"$json" | head -n1)" && \
     thumb="$(jq -r 'try .photos[].thumbnail_large.src | select(. != null) | .' <<<"$json" | head -n1)" && \
     [[ -n $link && -n $thumb ]]; then

    curl -fsSL --fail "$thumb" > "$jpg" || :
    printf '%s\n' "$link"  >"$lnk"
    printf '%s\n' "$thumb" >"$tlnk"

    case "$returntype" in
      image)     printf '%s\n' "$jpg"  ;;
      link)      printf '%s\n' "$link" ;;
      thumblink) printf '%s\n' "$thumb";;
    esac
  else
    rm -f "$dir/$icao".* 2>/dev/null || :
    touch "$na"
  fi

  # do a quick cache cleanup
  find /usr/share/planefence/persist/planepix/cache -type f '(' -name '*.jpg' -o -name '*.link' -o -name '*.thumblink' -o -name '*.notavailable' ')' -mmin +"$(( CACHETIME / 60 ))" -delete 2>/dev/null
}

CHK_NOTIFICATIONS_ENABLED () {
  # Check if any notifications are enabled
  if chk_enabled "$PF_DISCORD" || \
     { [[ -n "${BLUESKY_APP_PASSWORD}" ]] && [[ -n "$BLUESKY_HANDLE" ]]; } || \
     [[ -n "${MASTODON_ACCESS_TOKEN}" ]] || \
     [[ -n "$MQTT_URL" ]] || \
     [[ -n "${PF_TELEGRAM_CHAT_ID}" ]]; then
    return 0
  else
    return 1
  fi
}

GET_NOISEDATA () {
  # Get noise data from the remote server
  # It returns the average values over the specified time range
  # Usage: GET_NOISEDATA <firstseen_epoch> [<lastseen_epoch>]
  if [[ -z "$REMOTENOISE" ]] || [[ -z "$1" ]]; then return; fi
  local firstseen lastseen samplescount=0 ts level level_1min level_5min level_10min level_1hr loudness color avglevel avg1min avg5min avg10min avg1hr
  local noiselogdate
  firstseen="$1"
  lastseen="$2"
  if [[ -z "$lastseen" ]] || (( lastseen - firstseen < 15 )); then lastseen="$(( firstseen + 15 ))"; fi

  # get the noisecapt log - download them all in case there's a date discrepancy
  # Extract matching filenames, sorted
  readarray -t files < <(
    printf '%s\n' "$noiselist" |
      sed -En 's/.*\b(noisecapt-[0-9]{6}\.log)\b.*/\1/p' |
      sort -u
  )

  # Fetch in order, filter by first field (epoch seconds), collect into Bash array
  noiserecords=()
  while IFS= read -r line; do
    noiserecords+=("$line")
  done < <(
    for f in "${files[@]}"; do
      curl -fsSL "$REMOTENOISE/$f"
    done | awk -F',' -v s="$firstseen" -v e="$lastseen" '{ t=$1+0; if (t>=s && t<=e) print }'
  )

  for line in "${noiserecords[@]}"; do
    if [[ -z "$line" ]]; then continue; fi
    IFS=, read -r ts level level_1min level_5min level_10min level_1hr <<< "$line"
    (( samplescount++ )) || true
    avglevel="$(( avglevel + level ))"
    avg1min="$(( avg1min + level_1min ))"
    avg5min="$(( avg5min + level_5min ))"
    avg10min="$(( avg10min + level_10min ))"
    avg1hr="$(( avg1hr + level_1hr ))"
  done
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
	local TITLE="Noise plot for $1 at $(date -d "@$2")"
	local NOISEGRAPHFILE="$OUTFILEDIR"/"noisegraph-$STARTTIME-$4.png"
  # check if we can get the noisecapt log:
  if [[ -z "$noiselog" ]]; then
    if ! curl -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$STARTTIME" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
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
  
  local MAXSPREAD=${MAXSPREAD:-15}
  local spectrofile

  # get the noisecapt log - download them all in case there's a date discrepancy
  # Extract matching filenames, sorted
  readarray -t files < <(
    printf '%s\n' "$noiselist" |
      sed -En 's/.*\b(noisecapt-[0-9]{6}\.log)\b.*/\1/p' |
      sort -u
  )

  # Assumes $noiselist is newline-separated filenames
  spectrofile="$(awk -v T="${records["$idx":time_at_mindist]}" -v L="$MAXSPREAD" '
    BEGIN {
      INF = 9223372036854775807   # big sentinel
      best_before_dt = INF; best_after_dt = INF
      best_before = ""; best_after = ""
    }
    $0 ~ /^noisecapt-spectro-[0-9]+\.png$/ {
      if (match($0, /noisecapt-spectro-([0-9]+)\.png/, m)) {
        ts = m[1] + 0
        if (ts <= T) {
          dt = T - ts
          if (dt < best_before_dt) { best_before_dt = dt; best_before = $0 }
        } else {
          dt = ts - T
          if (dt < best_after_dt)  { best_after_dt  = dt; best_after  = $0 }
        }
      }
    }
    END {
      if (best_before != "" && best_before_dt <= L) { print best_before; exit }
      if (best_after  != "" && best_after_dt  <= L) { print best_after;  exit }
      # else print nothing (empty result)
    }
  ' <<< "$noiselist")"


	if [[ -z "$spectrofile" ]]; then 
    # debug_print "There's no noise data between $(date -d "@$STARTTIME") and $(date -d "@$ENDTIME")."
    return
  fi


	if [[ ! -s "$OUTFILEDIR/$spectrofile" ]]; then
		# we don't have $spectrofile locally, or if it's an empty file, we get it:
		# shellcheck disable=SC2076

      debug_print "Getting spectrogram $spectrofile from $REMOTENOISE"
      if ! curl -fsSL "$REMOTENOISE/$spectrofile" > "$OUTFILEDIR/$spectrofile" || \
        { [[ -f "$spectrofile" ]] && (( $(stat -c '%s' "$OUTFILEDIR/x${spectrofile:---}" 2>/dev/null || echo 0) < 10 ));}; then
          debug_print "Curling spectrogram $spectrofile from $REMOTENOISE failed!"
          rm -f "$OUTFILEDIR/$spectrofile"
          return
      fi

	fi
  debug_print "Spectrogram file: $OUTFILEDIR/$spectrofile"
  echo "$OUTFILEDIR/$spectrofile"
}

LINK_LATEST_SPECTROFILE () {

  # link the latest spectrogram to a fixed name for easy access
  # Save current nullglob state
  local latestfile
  latestfile="$(find "$OUTFILEDIR" \
                  -maxdepth 1 \
                  -type f \
                  -regextype posix-extended \
                  -regex '.*/noisecapt-spectro-[0-9]+\.png' \
                  -printf '%f\n' | sort | tail -n 1)"

  if [[ -n "$latestfile" ]]; then
    ln -sf "$OUTFILEDIR/$latestfile" "$OUTFILEDIR/noisecapt-spectro-latest.png"
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

to_epoch() {
  # Fast YYYY/MM/DD HH:MM:SS -> epoch (no subsecond needed)
  local d="$1" t="$2"
  # split date
  local Y=${d:0:4} M=${d:5:2} D=${d:8:2}
  local h=${t:0:2} m=${t:3:2} s=${t:6:2}
  # GNU date can parse RFC-3339 fastest if given numeric; but to avoid invoking per-line,
  # compute offset using seconds since epoch at midnight plus H:M:S. Precompute midnight once:
}

GENERATE_CSV() {
  # This looks complex but is highly opimized for speed by using awk for the heavy lifting.
  local tmpfile="$(mktemp)"
  local re
  local k
  # Export records[] to awk as NUL-safe stream. 
  {
    printf 'MAXIDX\x01%s\n' "${records[maxindex]}"
    # Use "${!records[@]}" directly; it's fast enough for ~40k entries
    re='^([0-9]+):([A-Za-z0-9_-]+)(:([A-Za-z0-9_-]+))?$'
    for k in "${!records[@]}"; do      
      if [[ $k =~ $re && $k != *":checked" ]] ; then printf '%s\x01%s\n' "$k" "${records[$k]}"; fi
    done
  } | awk -v OFS=',' -v soh="$(printf '\001')" '
  function isdec(s){ return (s ~ /^[0-9]+$/) }
  function has_heatmap(s){ return (s ~ /heatmap/) }
  function split_key(k,   n, i, rest) {
    # Expect formats: index:key or index:key:subkey
    n = index(k, ":")
    if (n == 0) return 0
    i = substr(k, 1, n-1)
    rest = substr(k, n+1)
    if (!isdec(i)) return 0
    if (has_heatmap(rest)) return 0
    key = rest
    idx = i
    return 1
  }
  BEGIN{
    FS = soh
  }
  NR==1 {
    # First line carries maxindex
    if ($1 == "MAXIDX") maxidx = $2 + 0
    next
  }
  {
    rawk = $1; val = $2
    # rawk looks like records[INDEX:KEY...] in bash variable name? No: we fed the map key only.
    # Our bash loop printed keys exactly as "INDEX:KEY..." or "maxindex".
    # So rawk is like "12:temperature" or "12:meta:unit"
    key=""; idx=""
    if (!split_key(rawk)) next
    # Collect unique keys and values
    if (!(key in keyseen)) { keyseen[key]=1; keys_order[++kcount]=key }
    table[idx SUBSEP key] = val
    if (idx+0 > hiidx) hiidx = idx+0
  }
  END{
    # Decide max index bound
    if (maxidx == 0 && hiidx > 0) maxidx = hiidx
    # Header
    printf "index"
    # Stable order as encountered; if you prefer lexicographic, uncomment sort
    # Sort keys lexicographically for deterministic CSV
    n = asorti(keyseen, skeys)
    for (i=1; i<=n; i++) {
      printf ",%s", skeys[i]
      cols[i] = skeys[i]
    }
    printf "\n"
    # Rows
    for (i=0; i<=maxidx; i++) {
      printf "%d", i
      for (c=1; c<=n; c++) {
        k = cols[c]
        v = table[i SUBSEP k]
        # Simple CSV encoding here; keep minimal and let shell csv_encode if desired
        # Escape in awk for speed: double quotes double, wrap if needed
        if (v ~ /["\n,]/) {
          gsub(/"/, "\"\"", v)
          printf ",\"%s\"", v
        } else {
          printf ",%s", v
        }
      }
      printf "\n"
    }
  }
  ' > "$tmpfile" # write to tmpfile first so $CSVOUT is always a full file
  mv -f "$tmpfile" "$CSVOUT"
  chmod a+r "$CSVOUT"
}

GENERATE_JSON() {
  ### Generate JSON object
  # This is done with (g)awk + jq for speed
  local tmpfile="$(mktemp)"
  local re
  local k
  {
    re='^([0-9]+):([A-Za-z0-9_-]+)(:([A-Za-z0-9_-]+))?$'
    for k in "${!records[@]}"; do
      if [[ $k =~ $re && $k != *":checked" ]]; then printf '%s\0%s\0' "$k" "${records[$k]}"; fi
    done
  } \
  | gawk -v RS='\0' -v ORS='\0' '
  BEGIN { count = 0 }
  {
    # read key and value in pairs
    if (NR % 2 == 1) {
      key = $0
      next
    } else {
      val = $0
    }

    n = split(key, a, ":")
    if (n < 2 || n > 3) next
    if (a[1] !~ /^[0-9]+$/) next
    if (a[2] !~ /^[A-Za-z0-9_-]+$/) next
    if (n == 3 && a[3] !~ /^[A-Za-z0-9_-]+$/) next

    idx = a[1]
    k = a[2]
    subkey = ""
    if (n == 3) subkey = a[3]

    # emit idx\0key\0sub\0value\0
    printf "%s\0%s\0%s\0%s\0", idx, k, subkey, val
    count++
  }' | \
  jq -R -s '
    split("\u0000")
    | .[:-1]
    | [range(0; length; 4) as $i |
        {i:(.[ $i ]|tonumber),
        k:.[ $i+1 ],
        s:(if (.[ $i+2 ]|length)==0 then null else .[ $i+2 ] end),
        v:.[ $i+3 ] }
      ]
    | reduce .[] as $t ({};
        .[$t.i|tostring] |= (
          (. // {})
          | if $t.s == null then
              # Set scalar; overwrite object—last write wins
              .[$t.k] = $t.v
            else
              # Ensure object before setting subkey
              .[$t.k] = ((.[$t.k] | if type=="object" then . else {} end) | .[$t.s] = $t.v)
            end
        )
      )
    | to_entries
    | sort_by(.key|tonumber)
    | map({index:(.key|tonumber)} + .value)
  '  > "$tmpfile"
  mv -f "$tmpfile" "$JSONOUT"
  chmod a+r "$JSONOUT"
}

log_print INFO "Hello. Starting $0"

# ==========================
# Prep-work:
# ==========================

if [[ "$1" == "reset" ]]; then
  log_print INFO "Resetting records"
  rm -f "$RECORDSFILE" "$CSVOUT" "$JSONOUT" "/tmp/.records.lock"
  unset records
  declare -A records 
  records[maxindex]="-1"
fi

debug_print "Getting $RECORDSFILE"
LOCK_RECORDS
READ_RECORDS ignore-lock

debug_print "Got $RECORDSFILE. Getting ignorelist"
if [[ -f "$IGNORELIST" ]]; then
    sed -i '/^$/d' "$IGNORELIST" 2>/dev/null  # clean empty lines from ignorelist
else
    touch "$IGNORELIST"
fi

debug_print "Got ignorelist. Getting noiselist in the background as this may take a while"
if [[ -n $REMOTENOISE ]]; then
  curl -fsSL "$REMOTENOISE/noisecapt-dir.gz" | zcat > /tmp/.allnoise 2>/dev/null &
fi

# ==========================
# Collect new lines
# ==========================
if [[ -n "$LASTPROCESSEDLINE" ]]; then
  lastdate="$(awk -F, '{print $5}' <<< "$LASTPROCESSEDLINE")"
fi

log_print INFO "Collecting new records. Last processed date is $lastdate"

if [[ "$(date -d "${lastdate:-1972/01/01}" +%y%m%d)" == "$TODAY" ]]; then
  nowlines="$(grep -A9999999 -F "$LASTPROCESSEDLINE" "$TODAYFILE" | wc -l)" || true
  records[totallines]="$(( records[totallines] + nowlines ))"
elif [[ -f "$TODAYFILE" ]]; then 
  records[totallines]="$(cat "$TODAYFILE" | wc -l)"
  nowlines="${records[totallines]}"
else
  records[totallines]="0"
  nowlines=0
fi

currentrecords=$(( records[maxindex] + 1 ))

readarray -t socketrecords <<< "$(
    { if [[ -n "$LASTPROCESSEDLINE" ]]; then
      # Check if last run was yesterday
      if [[ "$(date -d "$lastdate" +%y%m%d)" == "$YESTERDAY" ]]; then
          # Grab remainder of yesterday + all of today
          { debug_print "Last processed line was from yesterday ($(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")), so grabbing remainder of yesterday's file and all of today's file"
            grep -A9999999 -F "$LASTPROCESSEDLINE" "$YESTERDAYFILE" 2>/dev/null || true
            cat "$TODAYFILE"
          }
      elif [[ "$(date -d "$lastdate" +%y%m%d)" == "$TODAY" ]]; then # Just grab remainder of today
        debug_print "Last processed line was from today ($(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")), so grabbing remainder of today's file"
        grep -A9999999 -F "$LASTPROCESSEDLINE" "$TODAYFILE" 2>/dev/null || true
      else
        debug_print "Last processed line was from before today ($(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")), so grabbing all of today's file"
        cat "$TODAYFILE"
      fi
    else
      # First run: all of today’s file
      debug_print "No last processed line found, so grabbing all of today's file"
        cat "$TODAYFILE"
    fi; } \
      | tac \
      | grep -v -i -f "$IGNORELIST" 2>/dev/null \
      | awk -F, -v dist="$DIST" -v maxalt="$MAXALT" '$8 <= dist && $2 <= maxalt && NF==12 { print }'
  )"
log_print INFO "Collected $nowlines new SBS records from your ADSB data feed, of which ${#socketrecords[@]} are within $DIST $DISTUNIT distance and $MAXALT $ALTUNIT altitude."

# ==========================
# Process lines
# ==========================
if (( ${#socketrecords[@]} > 0 )); then
  for line in "${socketrecords[@]}"; do

    [[ -z $line ]] && continue
    IFS=',' read -r icao altitude lat lon date time angle distance squawk gs track callsign <<< "$line"
    [[ $icao == "hex_ident" ]] || [[ -z "$time" ]] && continue # skip header or incomplete lines

    # Parse timestamp fast (assumes most lines are for today)
    t=${time%%.*}
    if [[ $date == "$today_ymd" && ${#t} -ge 8 ]]; then
      seentime=$(( midnight_epoch + 3600*10#${t:0:2} + 60*10#${t:3:2} + 10#${t:6:2} ))
    else
      seentime=$(date -d "$date $t" +%s)
    fi

    # Heatmap tally 
    latlonkey="$(printf "%.3f,%.3f" "$lat" "$lon")"
    heatmap["$latlonkey"]=$(( ${heatmap["$latlonkey"]:-0} + 1 ))

    # Collapse window lookup (O(1))
    idx=""
    ls="${lastseen_for_icao[$icao]}"
    if [[ -n $ls ]]; then
      dt=$(( ls - seentime ))
      if (( ${dt//-/} <= COLLAPSEWITHIN )); then
        idx="${last_idx_for_icao[$icao]}"
        updatedrecords[idx]=1
      else
        if chk_enabled "$IGNOREDUPES"; then
          continue  # ignore this dupe
        fi
      fi
    fi

    # Create new idx if needed
    if [[ -z $idx ]]; then
      idx=$(( records[maxindex] + 1 ))
      records[maxindex]="$idx"
      records["$idx":complete]=false
    fi

    # Update fast ICAO index maps
    last_idx_for_icao[$icao]=$idx
    lastseen_for_icao[$icao]=$seentime

    # Initialize once-per-record fields
    if [[ -z ${records["$idx":icao]} ]]; then
      records["$idx":icao]="$icao"
      # map link at first touch
      if [[ -n $lat && -n $lon ]]; then
        records["$idx":map:link]="https://$TRACKURL/?icao=$icao&lat=$lat&lon=$lon&showTrace=$TODAY"
      else
        records["$idx":map:link]="https://$TRACKURL/?icao=$icao&showTrace=$TODAY"
      fi
    fi

    # add a tail if there isn't any
    if ! chk_enabled "${records["$idx":tail:checked]}" && [[ -z "${records["$idx":tail]}" ]]; then
      records["$idx":tail]="$(GET_TAIL "$icao")"
      if [[ -n "${records["$idx":tail]}" ]]; then 
        if [[ ${icao:0:1} =~ [aA] ]]; then
          records["$idx":faa:link]="https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt=${records["$idx":tail]}"
        elif [[ ${icao:0:1} =~ [cC] ]]; then
          t="${records["$idx":tail]:1}"  # remove leading C
          records["$idx":faa:link]="https://wwwapps.tc.gc.ca/saf-sec-sur/2/ccarcs-riacc/RchSimpRes.aspx?m=%7c${t//-/}%7c"
        fi
      fi
      records["$idx":tail:checked]=true
    fi

    # get type
    if ! chk_enabled "${records["$idx":type:checked]}" && [[ -z "${records["$idx":type]}" ]]; then
      records["$idx":type]="$(GET_TYPE "${records["$idx":icao]}")"
      records["$idx":type:checked]=true
    fi

    # Callsign handling
    callsign="${callsign//[[:space:]]/}"
    if [[ -n $callsign ]]; then
      records["$idx":callsign]="$callsign"
      records["$idx":fa:link]="https://flightaware.com/live/modes/$icao/ident/$callsign/redirect"
      records["$idx":callsign:checked]=true
    fi

    # First/last seen
    if (( seentime < ${records["$idx":firstseen]:-9999999999} )); then records["$idx":firstseen]="$seentime"; fi
    if (( seentime > ${records["$idx":lastseen]:-0} )); then records["$idx":lastseen]="$seentime"; fi

    # Min-distance update (float-safe without awk by string compare fallback)
    curdist=${records["$idx":distance]}
    do_update=false
    if [[ -z $curdist ]]; then
      do_update=true
    else
      # numeric compare using bc-less trick: compare as floats via printf %f then string compare is unsafe; instead use scaled ints
      # scale to 2 decimals
      d1=${distance#-}; d2=${curdist#-}
      d1i=${d1%.*}; d1f=${d1#*.}; d1f=${d1f%%[!0-9]*}; d1f=${d1f:0:2}; d1f=${d1f:-0}
      d2i=${d2%.*}; d2f=${d2#*.}; d2f=${d2f%%[!0-9]*}; d2f=${d2f:0:2}; d2f=${d2f:-0}
      s1=$(( 10#$d1i*100 + 10#$d1f ))
      s2=$(( 10#$d2i*100 + 10#$d2f ))
      if (( s1 < s2 )); then do_update=true; fi
    fi
    if $do_update; then
      records["$idx":distance]="$distance"
      [[ -n $lat ]] && records["$idx":lat]="$lat"
      [[ -n $lon ]] && records["$idx":lon]="$lon"
      [[ -n $altitude ]] && records["$idx":altitude]="$altitude"
      [[ -n $angle ]] && records["$idx":angle]="${angle%.*}" && records["$idx":angle:name]="$(deg_to_compass "$angle")"
      [[ -n $gs ]] && records["$idx":groundspeed]="$gs"
      [[ -n $track ]] && records["$idx":track]="$track" && records["$idx":track:name]="$(deg_to_compass "$track")"
      records["$idx":time_at_mindist]="$seentime"
      [[ -n $squawk ]] && records["$idx":squawk]="$squawk"
    else
      # ensure squawk gets set once if still empty
      if [[ -n $squawk && -z ${records["$idx":squawk]} ]]; then
        records["$idx":squawk]="$squawk"
      fi
    fi
  done

  log_print INFO "Initial processing complete. New/Updated: $((records[maxindex] + 1 - currentrecords))/${#updatedrecords[@]}. Total number of records is now ${records[maxindex]}. Continue adding more info."

  # try to pre-seed the noisecapt log:
  if [[ -n "$REMOTENOISE" ]] && curl -fsSL "$REMOTENOISE/noisecapt-$TODAY.log" >/tmp/noisecapt.log 2>/dev/null; then
    noiselog="$(</tmp/noisecapt.log)"
  fi

#  lc=0
#  timingstart=$(date +%s.%3N)
  
  # Now try to add callsigns and owners for those that don't already have them:
  for ((idx=0; idx<records[maxindex]; idx++)); do

    # ------------------------------------------------------------------------------------
    # The first portion of this loop can be done regardless of completeness of the record
    # ------------------------------------------------------------------------------------
    # get the owner's name
    # namestart=$(date +%s.%3N)
    if ! chk_enabled "${records["$idx":owner:checked]}" && [[ -n "${records["$idx":callsign]}" ]]; then
      records["$idx":owner]="$(/usr/share/planefence/airlinename.sh "${records["$idx":callsign]}" "${records["$idx":icao]}" 2>/dev/null)"
      records["$idx":owner:checked]=true
    fi
    # nametiming=$(bc -l <<< "${nametiming:-0} + $(date +%s.%3N) - $namestart")

    # get images
    # imgstart=$(date +%s.%3N)
    if chk_enabled "$SHOWIMAGES" && \
       ! chk_enabled "${records["$idx":image:checked]}" && \
       [[ -z "${records["$idx":image:thumblink]}" ]] && \
       [[ -n "${records["$idx":icao]}" ]]; then
          records["$idx":image:thumblink]="$(GET_PS_PHOTO "${records["$idx":icao]}" "thumblink")"
          records["$idx":image:link]="$(GET_PS_PHOTO "${records["$idx":icao]}" "link")"
          records["$idx":image:file]="$(GET_PS_PHOTO "${records["$idx":icao]}" "image")"
          records["$idx":image:checked]=true
          records[HASIMAGES]=true
    fi
    # imgtiming=$(bc -l <<< "${imgtiming:-0} + $(date +%s.%3N) - $imgstart")

    # callstart=$(date +%s.%3N)
    # Add a callsign if there isn't any
    if [[ -z "${records["$idx":callsign]}" ]]; then
      callsign="$(GET_CALLSIGN "${records["$idx":icao]}")"
      records["$idx":callsign]="${callsign//[[:space:]]/}"
      records["$idx":fa:link]="https://flightaware.com/live/modes/$hex:ident/ident/${callsign//[[:space:]]/}/redirect/"
    fi
    # calltiming=$(bc -l <<< "${calltiming:-0} + $(date +%s.%3N) - $callstart")

    # ------------------------------------------------------------------------------------
    # The remainder of this loop only makes sense for complete records. It also only needs to be done once.
    # So skip if already complete.
    # ------------------------------------------------------------------------------------
    
    # Add complete label if current time is outside COLLAPSEWITHIN window
    if [[ "${records["$idx":complete]}" != "true" ]] && (( NOWTIME - ${records["$idx":lastseen]} > COLLAPSEWITHIN )); then
      records["$idx":complete]=true
    else
      continue
    fi

    # Add noisecapt stuff
    # noisestart=$(date +%s.%3N)
    if [[ -n "$REMOTENOISE" ]] && \
       ! chk_enabled "${records["$idx":noisedata:checked]}" && \
       [[ -z "${records["$idx":sound:peak]}" ]]; then
          # Make sure we have the noiselist
          if [[ -z "$noiselist" ]]; then
            wait $!
            noiselist="$(</tmp/.allnoise)"
            rm -f /tmp/.allnoise
            # noisestart=$(date +%s.%3N)
          fi
          noisedate="$(awk -F'[.-]' '($1=="noisecapt" && $2 ~ /^[0-9]{6}$/ && $2>m){m=$2} END{if(m!="")print m}' <<< "$noiselist")"
          noisedate="${noisedate:-$TODAY}"
          read -r records["$idx":sound:peak] records["$idx":sound:1min] records["$idx":sound:5min] records["$idx":sound:10min] records["$idx":sound:1hour] records["$idx":sound:loudness] records["$idx":sound:color] <<< "$(GET_NOISEDATA "${records["$idx":firstseen]}" "${records["$idx":lastseen]}")"
          records["$idx":noisedata:checked]=true
          records[HASNOISE]=true
    fi
    if [[ -n "$REMOTENOISE" ]] && \
       ! chk_enabled "${records["$idx":noisegraph:checked]}" && \chk_enabled "${records["$idx":complete]}" && \
       [[ -z "${records["$idx":noisegraph:file]}" ]] && \
       [[ -n "${records["$idx":icao]}" ]]; then
          records["$idx":noisegraph:file]="$(CREATE_NOISEPLOT "${records["$idx":callsign]:-${records["$idx":icao]}}" "${records["$idx":firstseen]}" "${records["$idx":lastseen]}" "${records["$idx":icao]}")"
          if [[ -n "${records["$idx":noisegraph:file]}" ]]; then
            records["$idx":noisegraph:link]="$(basename "${records["$idx":noisegraph:file]}")"
          fi
          records["$idx":spectro:file]="$(CREATE_SPECTROGRAM "${records["$idx":firstseen]}" "${records["$idx":lastseen]}")"
          if [[ -n "${records["$idx":spectro:file]}" ]]; then
            records["$idx":spectro:link]="$(basename "${records["$idx":spectro:file]}")"
          fi
          records["$idx":mp3:file]="$(CREATE_MP3 "${records["$idx":firstseen]}" "${records["$idx":lastseen]}")"
          if [[ -n "${records["$idx":mp3:file]}" ]]; then
            records["$idx":mp3:link]="$(basename "${records["$idx":mp3:file]}")"
          fi
          records["$idx":noisegraph:checked]=true
    fi
    # noisetiming=$(bc -l <<< "${noisetiming:-0} + $(date +%s.%3N) - $noisestart")

    # get Nominating location. Note - this is slow because we need to do an API call for each lookup
    # nomstart=$(date +%s.%3N)
    if ! chk_enabled "${records["$idx":nominatim:checked]}" && \
       [[ -n "${records["$idx":lat]}" ]] && \
       [[ -n "${records["$idx":lon]}" ]]; then
      records["$idx":nominatim]="$(/usr/share/planefence/nominatim.sh --lat="${records["$idx":lat]}" --lon="${records["$idx":lon]}")"
      records["$idx":nominatim:checked]=true
    fi
    # nomtiming=$(bc -l <<< "${nomtiming:-0} + $(date +%s.%3N) - $nomstart")

    # save distance / altitude / speed units
    if [[ -z "${records["$idx":altitude:unit]}" ]]; then records["$idx":altitude:unit]="$ALTUNIT"; fi
    if [[ -z "${records["$idx":distance:unit]}" ]]; then records["$idx":distance:unit]="$DISTUNIT"; fi
    if [[ -z "${records["$idx":groundspeed:unit]}" ]]; then records["$idx":groundspeed:unit]="$SPEEDUNIT"; fi

  done

  # get route information in bulk (single API call)
  # routestart=$(date +%s.%3N)
  if ! chk_disabled "$CHECKROUTE"; then GET_ROUTE_BULK; fi
  # routetiming=$(bc -l <<< "${routetiming:-0} + $(date +%s.%3N) - $routestart")

  if ! chk_enabled "${records[HASROUTE]}"; then records[HASROUTE]=false; fi
  if ! chk_enabled "${records[HASIMAGES]}"; then records[HASIMAGES]=false; fi
  if ! chk_enabled "${records[HASNOISE]}"; then records[HASNOISE]=false; else LINK_LATEST_SPECTROFILE; fi



  log_print INFO "Processing complete. Now writing results to disk..."

  # ==========================
  # Save state
  # ==========================
  LASTPROCESSEDLINE="${socketrecords[0]}"
  WRITE_RECORDS ignore-lock
  debug_print "Wrote $RECORDSFILE"

  # # ==========================
  # # Emit CSV snapshot
  # # ==========================


  GENERATE_CSV
  debug_print "Wrote CSV object to $CSVOUT"

  GENERATE_JSON
  debug_print "Wrote JSON object to $JSONOUT"

fi
log_print INFO "Done."
