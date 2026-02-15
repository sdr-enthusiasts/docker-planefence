#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2155
#
# PF-PROCESS_SBS - a Bash shell script to read SBS data and create a planefence and plane-alert database
#
# Copyright 2020-2026 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
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
DEBUG=false

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf
echo "$$" > /run/planefence.pid

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

# RECORDSFILE="/usr/share/planefence/persist/records/planefence-records-${TODAY}.gz"
# YESTERDAYRECORDSFILE="/usr/share/planefence/persist/records/planefence-records-${YESTERDAY}.gz"

# CSVOUT="$HTMLDIR/planefence-${TODAY}.csv"
# PA_CSVOUT="$HTMLDIR/plane-alert-${TODAY}.csv"
# JSONOUT="$HTMLDIR/planefence-${TODAY}.json"
# PA_JSONOUT="$HTMLDIR/plane-alert-${TODAY}.json"

CSVOUT="/run/planefence/planefence-${TODAY}.csv"
PA_CSVOUT="/run/planefence/plane-alert-${TODAY}.csv"
JSONOUT="/run/planefence/planefence-${TODAY}.json"
PA_JSONOUT="/run/planefence/plane-alert-${TODAY}.json"

VERSION="${VERSION}${VERSION:+-}"
if [[ -s "/.VERSION" ]]; then
  VERSION+="$(</.VERSION)"
else
  VERSION+="build_unknown"
fi

# Precompute midnight of today only once:
midnight_epoch=$(date -d "$(date +%F) 00:00:00" +%s)
today_ymd=$(date +%Y/%m/%d)
yesterday_epoch=$(date -d yesterday +%s)
tracedate="${today_ymd//\//-}"  # YYYY-MM-DD
# ==========================

# constants
COLLAPSEWITHIN_SECS=${COLLAPSEWITHIN:?}
declare -A last_idx_for_icao pa_last_idx_for_icao   # icao -> most recent idx within window
declare -A lastseen_for_icao  # icao -> lastseen epoch
declare -A heatmap            # lat,lon -> count
declare -A pa_squawkmatch     # icao -> "true" if the icao matches the squawk filter (and has been seen with that squawk for at least SQUAWKTIME seconds), empty or "false" otherwise. This is used to mark records that match the squawk filter in the planefence and plane-alert records, and is updated in real time as new squawks are seen.
declare -a updatedrecords newrecords processed_indices pa_updatedrecords pa_newrecords pa_processed_indices ready_to_notify_initial

if [[ -z "$TRACKSERVICE" || "${TRACKSERVICE,,}" == "adsbexchange" ]]; then
  TRACKURL="globe.adsbexchange.com"
elif [[ "${TRACKSERVICE,,}" == "flightaware" ]]; then
  TRACKURL="flightaware"
elif [[ -n "$TRACKSERVICE" ]]; then
  TRACKURL="$(sed -E 's|^(https?://)?([^/]+).*|\2|' <<< "$TRACKSERVICE")"
else
  TRACKURL="globe.adsbexchange.com"
fi
PA_FILE="$(GET_PARAM pa PLANEFILE)"
PA_FILE="${PA_FILE:-/usr/share/planefence/persist/.internal/plane-alert-db.txt}"

PA_RANGE="$(GET_PARAM pa RANGE)"
PA_RANGE="${PA_RANGE%%#*}"
PA_RANGE="${PA_RANGE//[\"\'[:space:]]/}"
if [[ -z "$PA_RANGE" ]]; then
  PA_RANGE=999999
elif ! [[ $PA_RANGE =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  log_print WARN "Invalid PA_RANGE '$PA_RANGE' in plane-alert.conf; defaulting to infinite"
  PA_RANGE=999999
fi
log_print DEBUG "PA_RANGE=$PA_RANGE"

readarray -d , -t SQUAWKS < <(GET_PARAM pa SQUAWKS)
SQUAWKS[-1]="${SQUAWKS[-1]%$'\n'}"
if (( ${#SQUAWKS[@]} > 0 )); then 
  printf -v SQUAWKS_REGEX "%s|" "${SQUAWKS[@]}"
  SQUAWKS_REGEX="${SQUAWKS_REGEX%|}"
  log_print DEBUG "SQUAWKS to monitor: ${SQUAWKS[*]}"
fi
SQUAWKTIME="$(GET_PARAM pa SQUAWKTIME)"
SQUAWKTIME="${SQUAWKTIME:-10}"

PF_MOTD="$(GET_PARAM pf PF_MOTD)"
PA_MOTD="$(GET_PARAM pa PA_MOTD)"

# ==========================
# Functions
# ==========================

CLEANUP() {
  # CLEANUP
  # Remove matching transient files/dirs in /tmp if older than DELETEAFTER minutes.
  # Local configurable threshold (minutes), defaults to 10.
  # Remove transient Planefence artifacts in /tmp created during runtime.
  # Patterns removed (if present):
  #   /tmp/.pf-noisecache-*   (noise data cache dirs/files)
  #   /tmp/tmp.*              (generic temp files matching tmp.<something>)
  #   /tmp/pa_key_*           (plane-alert temporary key files)
  local TMPDELETEAFTER="10" # minutes
  local RAWRECSDELETEAFTER="14" # days
  # Limit depth to prevent descending into other directories.
  find /tmp -maxdepth 1 -mindepth 1 \
    \( -name '.pf-noisecache-*' -o -name 'tmp.*' -o -name 'pa_key_*' \) \
    -mmin +"${TMPDELETEAFTER}" \
    -exec rm -rf -- {} + 2>/dev/null || :
  find /usr/share/planefence/persist/records -type f -name 'planefence-records-*.gz' \
    -mtime +"${RAWRECSDELETEAFTER}" \
    -exec rm -f -- {} + 2>/dev/null || :
}

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
  if [[ -z "$tail" && -f /run/OpenSkyDB.csv ]]; then
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
  if [[ -f "$TODAYFILE" ]]; then
    tail="$(tac "$TODAYFILE" | awk -F "," -v icao="$icao" '($1 == icao && $12 != "") {print $12;exit;}' 2>/dev/null)"
  fi
	if [[ -n "$tail" ]]; then echo "${tail// /}"; return; fi

  # If it's not there, then use GET_TAIL to replace the callsign with the tail number
  GET_TAIL "$icao"
  return
}

GET_TYPE () {
  local apiUrl="https://api.adsb.lol/v2/hex"
  curl -m 30 -sSL "$apiUrl/$1" | jq -r '.ac[] .t' 2>/dev/null
}

GET_ROUTE_BULK () {
  # function to get a route by callsign. Must have a callsign - ICAO won't work
  # Usage: GET_ROUTE <callsign>
  # Uses the adsb.im API to retrieve the route

  local apiUrl="https://adsb.im/api/0/routeset"
  declare -A routesarray=()
  declare -A pf_indexarray=() pa_indexarray=()
  local idx line call route plausible

  # first comb through records[] to get the callsigns we need to look up the route for
  for (( idx=0; idx<=records[maxindex]; idx++ )); do
    if [[ "${records["$idx":checked:route]}" != "true" && -n "${records["$idx":callsign]}" ]]; then
      routesarray["$idx":callsign]="${records["$idx":callsign]:-${records["$idx":tail]}}"
      routesarray["$idx":lat]="${records["$idx":lat]}"
      routesarray["$idx":lon]="${records["$idx":lon]}"
      pf_indexarray["$idx"]="${records["$idx":callsign]}"
    fi
  done
    for (( idx=0; idx<=pa_records[maxindex]; idx++ )); do
    if [[ "${pa_records["$idx":checked:route]}" != "true" && -n "${pa_records["$idx":callsign]}" ]]; then
      routesarray["$idx":callsign]="${pa_records["$idx":callsign]:-${pa_records["$idx":tail]}}"
      routesarray["$idx":lat]="${pa_records["$idx":lat]}"
      routesarray["$idx":lon]="${pa_records["$idx":lon]}"
      pa_indexarray["$idx"]="${pa_records["$idx":callsign]}"
    fi
  done

  if (( ${#pf_indexarray[@]} > 0 )); then
    records[HASROUTE]=true
  fi
  if (( ${#pa_indexarray[@]} > 0 )); then
    pa_records[HASROUTE]=true
  fi

  # If there's anything to be looked up, then create a JSON object and submit it to the API. The call returns a comma separated object with call,route,plausibility(boolean)
  if (( ${#pf_indexarray[@]} + ${#pa_indexarray[@]} > 0 )); then

    json='{ "planes": [ '
    for idx in "${!pf_indexarray[@]}"; do
      json+="{ \"callsign\":\"${routesarray["$idx":callsign]}\", \"lat\": ${routesarray["$idx":lat]}, \"lng\": ${routesarray["$idx":lon]} },"
    done
    for idx in "${!pa_indexarray[@]}"; do
      json+="{ \"callsign\":\"${routesarray["$idx":callsign]}\", \"lat\": ${routesarray["$idx":lat]}, \"lng\": ${routesarray["$idx":lon]} },"
    done
    json="${json:0:-1}" # strip the final comma
    json+=" ] }" # terminate the JSON object

    while read -r line; do
      IFS=, read -r call route plausible <<< "$line"

      # get the routes, process them line by line.
      # Example results: RPA5731,BOS-PIT-BOS,true\nRPA5631,IND-BOS,true\nN409FZ,unknown,null\n
      for idx in "${!pf_indexarray[@]}"; do
        if [[ "${pf_indexarray["$idx"]}" == "$call" && "${records["$idx":checked:route]}" != "true" ]]; then
          if [[ -z "$route" || "$route" == "unknown" || "$route" == "null" ]]; then
            records["$idx":route]="n/a"
          else
            records["$idx":route]="$route"
            if chk_disabled "$plausible"; then records["$idx":route]+=" (?)"; fi
          fi
          records["$idx":checked:route]=true
        fi
      done
      for idx in "${!pa_indexarray[@]}"; do
        if [[ "${pa_indexarray["$idx"]}" == "$call" && "${pa_records["$idx":checked:route]}" != "true" ]]; then
          if [[ -z "$route" || "$route" == "unknown" || "$route" == "null" ]]; then
            pa_records["$idx":route]="n/a"
          else
            pa_records["$idx":route]="$route"
            if chk_disabled "$plausible"; then pa_records["$idx":route]+=" (?)"; fi
          fi
          pa_records["$idx":checked:route]=true
        fi
      done
    done <<< "$(curl -m 30 -sSL -X 'POST' "$apiUrl" -H 'accept: application/json' -H 'Content-Type: application/json' -d "$json" | jq -r '.[] | if type=="object" then [((.callsign // "")|tostring), ((._airport_codes_iata // "")|tostring), ((.plausible // "")|tostring)] elif type=="array" then [((.[0] // "")|tostring), ((.[1] // "")|tostring), ((.[2] // "")|tostring)] else empty end | @csv | gsub("\"";"")')"
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

    if route="$(curl -m 30 -fsSL -X 'POST' 'https://api.adsb.lol/api/0/routeset' \
		                      -H 'accept: application/json' \
													-H 'Content-Type: application/json' \
													-d '{"planes": [{"callsign": "'"${1^^}"'","lat": '"$LAT"',"lng": '"$LON"'}] }' \
								| jq -r '.[]._airport_codes_iata')" \
				&& [[ -n "$route" && "$route" != "unknown" && "$route" != "null" ]]
		then
			echo "${1^^},$route" >> "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt"
			echo "$route"
		elif [[ "${route,,}" == "unknown" || "${route,,}" == "null" ]]; then
			echo "${1^^},unknown" >> "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt"
		fi
}

GET_PA_INFO () {
  local lookup="$1"
  if ! chk_enabled "$PLANEALERT" || [[ -z $lookup ]] || [[ ! -f $PA_FILE ]]; then
    log_print DEBUG "Plane-Alert: No PA data available for $lookup (PLANEALERT=$PLANEALERT, PA_FILE=$PA_FILE)" 
    return
  fi
  local header_line
  header_line="$(GET_PARAM pa ALERTHEADER)"
  header_line="${header_line:-$(head -n1 "$PA_FILE" 2>/dev/null)}"
  header_line="${header_line//[#$]/}"
  if [[ -z "$header_line" ]]; then
    log_print DEBUG "Plane-Alert: No PA header line found in config or PA file for $lookup"
    return
  fi

  IFS=',' read -r -a __pa_header <<< "$header_line"
  declare -A __pa_cols=()
  local idx name
  for idx in "${!__pa_header[@]}"; do
    name="${__pa_header[$idx]}"
    __pa_cols["$name"]=$idx
  done

  local record
  record="$(awk -F',' -v key="$lookup" 'NR>1 && $1==key { print; exit }' "$PA_FILE")"
  [[ -n $record ]] || return

  IFS=',' read -r -a __pa_fields <<< "$record"
  local first_field=""

  if [[ -n ${__pa_cols[Registration]} ]]; then
    first_field="${__pa_fields[${__pa_cols[Registration]}]:-}"
  elif [[ -n ${__pa_cols[Tail]} ]]; then
    first_field="${__pa_fields[${__pa_cols[Tail]}]:-}"
  elif [[ -n ${__pa_cols[Ident]} ]]; then
    first_field="${__pa_fields[${__pa_cols[Ident]}]:-}"
  else
    first_field="$lookup"
  fi
  first_field="${first_field#\"}"
  first_field="${first_field%\"}"

  local -a desired=(CPMG "Tag 1" "Tag 2" "Tag 3" Category Link ImageLink ImageLink2 ImageLink3)
  local out=()
  out+=("$first_field")
  local col value
  for col in "${desired[@]}"; do
    if [[ -n ${__pa_cols[$col]} ]]; then
      value="${__pa_fields[${__pa_cols[$col]}]:-}"
      value="${value#\"}"
      value="${value%\"}"
    else
      value=""
    fi
    out+=("$value")
  done

  (IFS=','; printf '%s\n' "${out[*]}")
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
  if json="$(curl -m 30 -fsSL --fail "https://api.planespotters.net/pub/photos/hex/$icao")" && \
     link="$(jq -r 'try .photos[].link | select(. != null) | .' <<<"$json" | head -n1)" && \
     thumb="$(jq -r 'try .photos[].thumbnail_large.src | select(. != null) | .' <<<"$json" | head -n1)" && \
     [[ -n $link && -n $thumb ]]; then

    curl -m 30 -fsSL --fail "$thumb" > "$jpg" || :
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
     [[ ( -n "${BLUESKY_APP_PASSWORD}" && -n "$BLUESKY_HANDLE" ) || \
     -n "${MASTODON_ACCESS_TOKEN}" || \
     -n "$MQTT_URL" || \
     -n "${PF_TELEGRAM_CHAT_ID}" ]]; then
    return 0
  else
    return 1
  fi
}

GET_NOISEDATA () {
  # Get noise data from the remote server
  # It returns the average values over the specified time range
  # Usage: GET_NOISEDATA <firstseen_epoch> [<lastseen_epoch>]
  if [[ -z "$REMOTENOISE" || -z "$1" ]]; then return; fi
  local firstseen lastseen samplescount=0 ts level level_1min level_5min level_10min level_1hr loudness color avglevel avg1min avg5min avg10min avg1hr
  local noiselogdate
  firstseen="$1"
  lastseen="$2"
  if [[ -z "$lastseen" ]] || (( lastseen - firstseen < 15 )); then lastseen="$(( firstseen + 15 ))"; fi

  # Build candidate list limited to TODAY and YESTERDAY only, and only if window intersects the day
  readarray -t files < <(
    for d in "$TODAY" "$YESTERDAY"; do
      ds=$(date -d "20${d:0:2}-${d:2:2}-${d:4:2} 00:00:00" +%s)
      de=$(( ds + 86400 - 1 ))
      if (( lastseen >= ds && firstseen <= de )); then
        printf 'noisecapt-%s.log\n' "$d"
      fi
    done | sort -u
  )

  # Prepare a per-run cache directory so multiple calls reuse the same downloads
  if [[ -z "${NOISECACHE_DIR:-}" ]]; then
    NOISECACHE_DIR="/tmp/.pf-noisecache-$$"
    mkdir -p "$NOISECACHE_DIR" 2>/dev/null || :
  fi

  # Ensure each needed file is cached locally for this process
  for f in "${files[@]}"; do
    if [[ ! -s "$NOISECACHE_DIR/$f" ]]; then
      curl -m 30 -fsSL "$REMOTENOISE/$f" -o "$NOISECACHE_DIR/$f" 2>/dev/null || :
    fi
  done

  # Read cached content and filter rows in the time window
  noiserecords=()
  while IFS= read -r line; do
    noiserecords+=("$line")
  done < <(
    for f in "${files[@]}"; do
      [[ -s "$NOISECACHE_DIR/$f" ]] && cat "$NOISECACHE_DIR/$f"
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
	local NOISEGRAPHFILE="$OUTFILEDIR/noise/noisegraph-$STARTTIME-$4.png"
  # check if we can get the noisecapt log:
  if [[ -z "$noiselog" ]]; then
    if ! curl -m 30 -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$STARTTIME" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
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
      ln -sf "$NOISEGRAPHFILE" "$OUTFILEDIR/noisegraph-latest.png"
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
  spectrofile="$(awk -v T="${records["$idx":time:time_at_mindist]}" -v L="$MAXSPREAD" '
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
    # log_print DEBUG "There's no noise data between $(date -d "@$STARTTIME") and $(date -d "@$ENDTIME")."
    return
  fi


	if [[ ! -s "$OUTFILEDIR/noise/$spectrofile" ]]; then
		# we don't have $spectrofile locally, or if it's an empty file, we get it:
		# shellcheck disable=SC2076

      log_print DEBUG "Getting spectrogram $spectrofile from $REMOTENOISE"
      if ! curl -m 30 -fsSL "$REMOTENOISE/$spectrofile" > "$OUTFILEDIR/noise/$spectrofile" 2>/dev/null || \
        { [[ -f "$spectrofile" ]] && (( $(stat -c '%s' "$OUTFILEDIR/noise/${spectrofile:---}" 2>/dev/null || echo 0) < 10 ));}; then
          log_print DEBUG "Curling spectrogram $spectrofile from $REMOTENOISE failed!"
          rm -f "$OUTFILEDIR/noise/$spectrofile"
          return
      fi

	fi
  log_print DEBUG "Spectrogram file: $OUTFILEDIR/noise/$spectrofile"
  echo "$OUTFILEDIR/noise/$spectrofile"
}

LINK_LATEST_SPECTROFILE () {

  # link the latest spectrogram to a fixed name for easy access
  # Save current nullglob state
  local latestfile
  latestfile="$(find "$OUTFILEDIR/noise" \
                  -maxdepth 1 \
                  -type f \
                  -regextype posix-extended \
                  -regex '.*/noisecapt-spectro-[0-9]+\.png' \
                  -printf '%f\n' | sort | tail -n 1)"

  if [[ -n "$latestfile" ]]; then
    ln -sf "$OUTFILEDIR/noise/$latestfile" "$OUTFILEDIR/noisecapt-spectro-latest.png"
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
    if ! curl -m 30 -fsSL "$REMOTENOISE/noisecapt-$(date -d "@$1" +%y%m%d).log" >/tmp/noisecapt.log 2>/dev/null; then
      return
    fi
    noiselog="$(</tmp/noisecapt.log)"
  fi

	# get the measurement from noisecapt-"$FENCEDATE".log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	mp3time="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /tmp/noisecapt.log)"
	mp3f="noisecapt-recording-${mp3time}.mp3"

	# shellcheck disable=SC2076
	if [[ ! -s "$OUTFILEDIR/noise/$mp3f" && $noiselist =~ "$mp3f" ]] ; then
		# we don't have $sf locally, or if it's an empty file, we get it:
    curl -m 30 -fsSL "$REMOTENOISE/$mp3f" > "$OUTFILEDIR/noise/$mp3f" 2>/dev/null
	fi
	# shellcheck disable=SC2012
	if [[ ! -s "$OUTFILEDIR/noise/$mp3f" ]] || (( $(ls -s1 "$OUTFILEDIR/noise/$mp3f" | awk '{print $1}') < 4 )); then
		# we don't have $mp3f (or it's an empty file) and we can't get it; so let's erase it in case it's an empty file:
		rm -f "$OUTFILEDIR/noise/$mp3f"
	else
		echo "$OUTFILEDIR/noise/$mp3f"
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

GENERATE_PF_CSV() {
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

GENERATE_PA_CSV() {
  # This looks complex but is highly opimized for speed by using awk for the heavy lifting.
  local tmpfile="$(mktemp)"
  local re
  local k
  # Export records[] to awk as NUL-safe stream.
  {
    printf 'MAXIDX\x01%s\n' "${pa_records[maxindex]}"
    # Use "${!pa_records[@]}" directly; it's fast enough for ~40k entries
    re='^([0-9]+):([A-Za-z0-9_-]+)(:([A-Za-z0-9_-]+))?$'
    for k in "${!pa_records[@]}"; do
      if [[ $k =~ $re && $k != *":checked" ]] ; then printf '%s\x01%s\n' "$k" "${pa_records[$k]}"; fi
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
  mv -f "$tmpfile" "$PA_CSVOUT"
  chmod a+r "$PA_CSVOUT"
}

GENERATE_PF_JSON() {
  ### Generate JSON object
  # This is done with (g)awk + jq for speed
  local tmpfile="$(mktemp)"
  local re
  local k
  {
    re='^(totallines|LAST.*|HAS.*|max.*|station.*|([0-9]+):([A-Za-z0-9_-]+)(:([A-Za-z0-9_-]+))?)$'
    for k in "${!records[@]}"; do
      if [[ $k =~ $re && $k != "checked:"* ]]; then printf '%s\0%s\0' "$k" "${records[$k]}"; fi
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

    idx = a[1]
    k = a[2]
    if (n == 3) { subkey = a[3] } else { subkey = "" }
    if (idx == "maxindex" || idx == "totallines" || idx ~ /^LAST/ || idx ~ /^HAS/) {
      # Global keys
      k = idx
      idx = -1
    } else if (idx == "station") {
      # Preserve full key (e.g., "station:dist:value") as a single global entry
      k = key
      subkey = ""
      idx = -1
    } else if (idx !~ /^[0-9]+$/) {
      next
    }


    # emit idx\0key\0sub\0value\0
    printf "%s\0%s\0%s\0%s\0", idx, k, subkey, val
    count++
  }' | \
  jq -R -s '
    def set_kvs(obj; k; s; v):
      if s == null or s == "" then obj + { (k): v }
      else obj + { (k): ((obj[k] // {}) + { (s): v }) }
      end;

    ( . // "" )
    | split("\u0000") | .[:-1]
    | [ range(0; length; 4) as $i |
        { i: (.[ $i ] | tonumber),
          k: .[$i+1],
          s: (if (.[ $i+2] | length) == 0 then null else .[$i+2] end),
          v: .[$i+3] }
      ]
    | reduce .[] as $t ({ groups: {}, globals: {} };
        if $t.i == -1 then
          .globals = set_kvs(.globals; $t.k; $t.s; $t.v)
        else
          .groups[($t.i | tostring)] =
            set_kvs((.groups[($t.i | tostring)] // {}); $t.k; $t.s; $t.v)
        end
      )
    | ( .groups
        | to_entries
        | sort_by(.key | tonumber)
        | reverse
        | map({ index: (.key | tonumber) } + .value)
      ) as $items
    | [ .globals ] + $items
  ' > "$tmpfile"
  mv -f "$tmpfile" "$JSONOUT"
  chmod a+r "$JSONOUT"
  ln -sf "$JSONOUT" "$HTMLDIR/planefence.json"
}

GENERATE_PA_JSON() {
  ### Generate JSON object
  # This is done with (g)awk + jq for speed
  local tmpfile="$(mktemp)"
  local re
  local k
  {
    re='^(totallines|LAST.*|HAS.*|max.*|station.*|([0-9]+):([A-Za-z0-9_-]+)(:([A-Za-z0-9_-]+))?)$'
    for k in "${!pa_records[@]}"; do
      if [[ $k =~ $re && $k != "checked:"* ]]; then printf '%s\0%s\0' "$k" "${pa_records[$k]}"; fi
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

    idx = a[1]
    k = a[2]
    if (n == 3) { subkey = a[3] } else { subkey = "" }
    if (idx == "maxindex" || idx == "totallines" || idx ~ /^LAST/ || idx ~ /^HAS/) {
      # Global keys
      k = idx
      idx = -1
    } else if (idx == "station") {
      # Preserve full key (e.g., "station:dist:value") as a single global entry
      k = key
      subkey = ""
      idx = -1
    } else if (idx !~ /^[0-9]+$/) {
      next
    }


    # emit idx\0key\0sub\0value\0
    printf "%s\0%s\0%s\0%s\0", idx, k, subkey, val
    count++
  }' | \
  jq -R -s '
    def set_kvs(obj; k; s; v):
      if s == null or s == "" then obj + { (k): v }
      else obj + { (k): ((obj[k] // {}) + { (s): v }) }
      end;

    ( . // "" )
    | split("\u0000") | .[:-1]
    | [ range(0; length; 4) as $i |
        { i: (.[ $i ] | tonumber),
          k: .[$i+1],
          s: (if (.[ $i+2] | length) == 0 then null else .[$i+2] end),
          v: .[$i+3] }
      ]
    | reduce .[] as $t ({ groups: {}, globals: {} };
        if $t.i == -1 then
          .globals = set_kvs(.globals; $t.k; $t.s; $t.v)
        else
          .groups[($t.i | tostring)] =
            set_kvs((.groups[($t.i | tostring)] // {}); $t.k; $t.s; $t.v)
        end
      )
    | ( .groups
        | to_entries
        | sort_by(.key | tonumber)
        | reverse
        | map({ index: (.key | tonumber) } + .value)
      ) as $items
    | [ .globals ] + $items
  ' > "$tmpfile"
  mv -f "$tmpfile" "$PA_JSONOUT"
  chmod a+r "$PA_JSONOUT"
  ln -sf "$PA_JSONOUT" "$HTMLDIR/plane-alert.json"
}

GENERATE_HEATMAPJS() {
  	# Create the heatmap data
    local tmpfile="$(mktemp)"
	{ printf "var addressPoints = [\n"
		for i in "${!heatmap[@]}"; do
				printf "[ %s,%s ],\n" "$i" "${heatmap["$i"]}"
		done
		printf "];\n"
	} > "$tmpfile"
  mv -f "$tmpfile" "$OUTFILEDIR/js/planeheatdata.js"
}

log_print INFO "Hello. Starting $0"

# ==========================
# Prep-work:
# ==========================


log_print DEBUG "Getting RECORDSFILE"
LOCK_RECORDS
READ_RECORDS ignore-lock

log_print DEBUG "Got RECORDSFILE. Getting ignorelist"
if [[ -f "$IGNORELIST" ]]; then
    sed -i '/^$/d' "$IGNORELIST" 2>/dev/null  # clean empty lines from ignorelist
else
    touch "$IGNORELIST"
fi

log_print DEBUG "Got ignorelist. Getting noiselist in the background as this may take a while"
if [[ -n $REMOTENOISE ]]; then
  curl -m 30 -fsSL "$REMOTENOISE/noisecapt-dir.gz" 2>/dev/null | zcat > /tmp/.allnoise 2>/dev/null &
  noise_pid=$!
fi

if chk_enabled "$PLANEALERT"; then
  awk -F',' 'NR>1 {print "^" $1 "," }' "$PA_FILE" > /tmp/pa_keys_$$ 2>/dev/null || touch /tmp/pa_keys_$$
  if (( ${#SQUAWKS[@]} > 0 )); then 
    # shellcheck disable=SC2046
    printf "^([^,]*,){8}%s(,|$)\n" "${SQUAWKS[@]}" >> /tmp/pa_keys_$$
  fi
fi

# ==========================
# Collect new lines
# ==========================
if [[ -n "$LASTPROCESSEDLINE" ]]; then
  lastdate="$(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")"
fi

log_print INFO "Collecting new records. Last processed date is $lastdate"

if [[ "$(date -d "${lastdate:-@0}" +%y%m%d)" == "$TODAY" ]]; then
  nowlines="$(grep -A9999999 -F "$LASTPROCESSEDLINE" "$TODAYFILE" | wc -l)" || true
  records[totallines]="$(( records[totallines] + nowlines ))"
elif [[ -f "$TODAYFILE" ]]; then
  # shellcheck disable=SC2002
  records[totallines]="$(cat "$TODAYFILE" | wc -l)"
  nowlines="${records[totallines]}"
else
  records[totallines]="0"
  nowlines=0
fi

pa_records[totallines]="${records[totallines]}"
currentrecords=$(( records[maxindex] + 1 ))

{ if [[ -n "$LASTPROCESSEDLINE" ]]; then
      # Check if last run was yesterday
      if [[ "$(date -d "$lastdate" +%y%m%d)" == "$YESTERDAY" ]]; then
          # Grab remainder of yesterday + all of today
          { log_print DEBUG "Last processed line was from yesterday ($(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")), so grabbing remainder of yesterday's file and all of today's file"
            grep -A9999999 -F "$LASTPROCESSEDLINE" "$YESTERDAYFILE" 2>/dev/null || true
            cat "$TODAYFILE"
          }
      elif [[ "$(date -d "$lastdate" +%y%m%d)" == "$TODAY" ]]; then # Just grab remainder of today
        log_print DEBUG "Last processed line was from today ($(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")), so grabbing remainder of today's file"
        grep -A9999999 -F "$LASTPROCESSEDLINE" "$TODAYFILE" 2>/dev/null || cat "$TODAYFILE" || true
      else
        log_print DEBUG "Last processed line was from before today ($(awk -F, '{print $5 " " $6}' <<< "$LASTPROCESSEDLINE")), so grabbing all of today's file"
        cat "$TODAYFILE"
      fi
    else
      # First run: all of today’s file
      log_print DEBUG "No last processed line found, so grabbing all of today's file"
        cat "$TODAYFILE"
  fi
} | tac > /tmp/filtered_records_$$ \
|| { rm -f /run/socket30003/*.pid 2>/dev/null || true; exit 1; }  # if tac fails, it's likely disk full; so kill socket30003.pl to trigger a log file cleanup and exit with error
log_print DEBUG "Collected new records into /tmp/filtered_records_$$"

# since the last line may be incomplete, set the LASTPROCESSEDLINE to the second line
# note that they are in reverse order due to tac
LASTPROCESSEDLINE="$(head -n2 /tmp/filtered_records_$$ | tail -1 || true)"

# Create pf_socketrecords array
readarray -t pf_socketrecords < <(grep -v -i -f "$IGNORELIST" /tmp/filtered_records_$$ 2>/dev/null | awk -F, -v dist="$DIST" -v maxalt="$MAXALT" '$8 <= dist && $2 <= maxalt && NF==12 { print }' || true)
log_print DEBUG "Created pf_socketrecords array with ${#pf_socketrecords[@]} entries"

# Create pa_socketrecords array
if chk_enabled "$PLANEALERT" && (( $(wc -l < /tmp/pa_keys_$$) > 0 )); then
  # Patterns in /tmp/pa_keys_$$ are regular expressions anchored with ^, so use regex grep
  readarray -t pa_socketrecords < <(grep -E -f /tmp/pa_keys_$$ /tmp/filtered_records_$$ 2>/dev/null | awk -F, -v dist="$PA_RANGE" '$8 <= dist && NF==12 { print }' || true)
  rm -f /tmp/pa_keys_$$
  log_print DEBUG "Created pa_socketrecords array with ${#pa_socketrecords[@]} entries"
else
  log_print DEBUG "Note - PlaneAlert not enabled or no PA keys found, so skipping PA records"
fi
rm -f /tmp/filtered_records_$$

# read the unique icao's into arrays:
readarray -t pf_icaos < <(printf '%s\n' "${pf_socketrecords[@]}" | sort -t, -k1,1 -u | awk -F, '{print $1}')
log_print DEBUG "Created index array with ${#pf_icaos[@]} unique planefence entries"
if chk_enabled "$PLANEALERT"; then
  readarray -t pa_icaos < <(printf '%s\n' "${pa_socketrecords[@]}" | sort -t, -k1,1 -u | awk -F, '{print $1}')
  log_print DEBUG "Created index array with ${#pa_icaos[@]} unique plane-alert entries"
fi

# ==========================
# Process lines
# ==========================
if (( ${#pf_socketrecords[@]} + ${#pa_socketrecords[@]} > 0 )); then
  # Build a de-duplicated combined list efficiently (preserves first-seen order)
  orig_count=$(( ${#pf_socketrecords[@]} + ${#pa_socketrecords[@]} ))
  readarray -t socketrecords < <(
    {
      printf '%s\n' "${pf_socketrecords[@]}"
      printf '%s\n' "${pa_socketrecords[@]}"
    } | awk 'BEGIN{FS="\n"} !seen[$0]++'
  )
  log_print DEBUG "Created socketrecords array with ${#socketrecords[@]} entries (deduped from ${orig_count})."
fi
for line in "${socketrecords[@]}"; do

  [[ -z $line ]] && continue
  IFS=',' read -r icao altitude lat lon date time angle distance squawk gs track callsign <<< "$line"
  [[ $icao == "hex_ident" || -z "$time" ]] && continue # skip header or incomplete lines

  # Parse timestamp fast (assumes most lines are for today)
  t=${time%%.*}
  if [[ $date == "$today_ymd" && ${#t} -ge 8 ]]; then
    seentime=$(( midnight_epoch + 3600*10#${t:0:2} + 60*10#${t:3:2} + 10#${t:6:2} ))
  else
    seentime=$(date -d "$date $t" +%s)
  fi

  # Collapse window lookup for planefence
  if [[ " ${pf_icaos[*]} " == *" $icao "* ]]; then
    idx=""
    ls="${lastseen_for_icao["$icao"]}"
    if [[ -n $ls ]]; then
      dt=$(( ls - seentime ))
      if (( ${dt//-/} <= COLLAPSEWITHIN )); then
        idx="${last_idx_for_icao["$icao"]}"
      else
        if chk_enabled "$IGNOREDUPES"; then
          continue  # ignore this dupe
        fi
      fi
    fi
    # Create new idx if needed
    if [[ -z "$idx" ]]; then
      idx=$(( records[maxindex] + 1 ))
      records[maxindex]="$idx"
      records["$idx":complete]=false
      newrecords["$idx"]=1
    else
      updatedrecords["$idx"]=1
    fi
    # Update fast ICAO index maps
    last_idx_for_icao["$icao"]="$idx"
    lastseen_for_icao["$icao"]="$seentime"

    # Heatmap tally (for PF records only)
    latlonkey="$(printf "%.3f,%.3f" "$lat" "$lon")"
    heatmap["$latlonkey"]=$(( ${heatmap["$latlonkey"]:-0} + 1 ))
    mode_pf=true
  else
    mode_pf=false
  fi

  # check for squawk filter matches and ensure that we've seen the squawk at least for SQUAWKTIME seconds to avoid transient squawks:
  if [[ -n "$squawk" && \
        "${pa_squawkmatch["$icao"]}" != "true" && \
        -n "$SQUAWKS_REGEX" && $squawk =~ $SQUAWKS_REGEX ]]; then
    log_print DEBUG "$icao matches squawk filter with $squawk!"
    # Find first and last occurrence of the icao/squawk combination:
    read -r sq_start sq_end < <(
      printf '%s\n' "${socketrecords[@]}" |
      awk -F',' -v icao="$icao" -v squawk="$squawk" '
        # d = YYYY/MM/DD, t = HH:MM:SS.mmm  (we ignore .mmm)
        function to_epoch(d, t,    y, m, d2, H, M, S, tmp) {
          split(d, a, "/");  y=a[1]; m=a[2]; d2=a[3]

          # remove milliseconds
          split(t, tmp, ".");  t = tmp[1]
          split(t, b, ":");    H=b[1]; M=b[2]; S=b[3]

          return mktime(y " " m " " d2 " " H " " M " " S)
        }

        $1 == icao && $9 == squawk {
          ts = to_epoch($5, $6)
          if (first_ts == "" || ts < first_ts) first_ts = ts
          if (last_ts  == "" || ts > last_ts)  last_ts  = ts
        }

        END {
          if (first_ts != "")
            print first_ts, last_ts
        }
      '
    )
    if (( ${sq_end:-999999} - ${sq_start:-0} < SQUAWKTIME )); then
      log_print DEBUG "NOK: Squawk $squawk for $icao has not been active for at least $SQUAWKTIME seconds (only from $(date -d "@$sq_start") to $(date -d "@$sq_end")), so skipping for PlaneAlert."
    else
      log_print DEBUG "OK: Squawk $squawk for $icao was active for at least $SQUAWKTIME seconds (from $(date -d "@$sq_start") to $(date -d "@$sq_end")), so including it for PlaneAlert."
      pa_squawkmatch["$icao"]=true
    fi
  fi

  # For plane-alert, always collapse into an existing record if any was available today
  if [[ " ${pa_icaos[*]} " == *" $icao "* || "${pa_squawkmatch["$icao"]}" == "true" ]]; then    
    pa_idx="${pa_last_idx_for_icao["$icao"]}"
    # Create new idx if none found or if last seen was before today
    if [[ -z "$pa_idx" || ${pa_records["$pa_idx":time:lastseen]:-0} -lt $midnight_epoch ]]; then
      pa_idx=$(( pa_records[maxindex] + 1 ))
      pa_records[maxindex]="$pa_idx"
      pa_records["$pa_idx":complete]=true # always complete for PA records
      pa_newrecords["$pa_idx"]=1
    else
      pa_updatedrecords["$pa_idx"]=1
    fi
    # Update fast ICAO index maps
    pa_last_idx_for_icao["$icao"]="$pa_idx"
    mode_pa=true
  else
    mode_pa=false
  fi

  # Update planefence record if in planefence mode
  if $mode_pf; then
    # Initialize once-per-record fields
    if [[ -z ${records["$idx":icao]} ]]; then
      records["$idx":icao]="$icao"
      # map link at first touch
      if [[ -n $lat && -n $lon ]]; then
        records["$idx":link:map]="https://$TRACKURL/?icao=$icao&lat=$lat&lon=$lon&showTrace=$tracedate"
      else
        records["$idx":link:map]="https://$TRACKURL/?icao=$icao&showTrace=$tracedate"
      fi
    fi

    # add a tail if there isn't any
    if [[ "${records["$idx":checked:tail]}" != "true" && -z "${records["$idx":tail]}" ]]; then
      records["$idx":tail]="$(GET_TAIL "$icao")"
      if [[ -n "${records["$idx":tail]}" ]]; then
        if [[ ${icao:0:1} =~ [aA] ]]; then
          records["$idx":link:faa]="https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt=${records["$idx":tail]}"
        elif [[ ${icao:0:1} =~ [cC] ]]; then
          t="${records["$idx":tail]:1}"  # remove leading C
          records["$idx":link:faa]="https://wwwapps.tc.gc.ca/saf-sec-sur/2/ccarcs-riacc/RchSimpRes.aspx?m=%7c${t//-/}%7c"
        fi
      fi
      records["$idx":checked:tail]=true
    fi

    # get type
    if [[ "${records["$idx":checked:type]}" != "true" && -z "${records["$idx":type]}" ]]; then
      records["$idx":type]="$(GET_TYPE "${records["$idx":icao]}")"
      records["$idx":checked:type]=true
    fi

    # Callsign handling
    callsign="${callsign//[[:space:]]/}"
    if [[ -n $callsign ]]; then
      records["$idx":callsign]="$callsign"
      records["$idx":link:fa]="https://flightaware.com/live/modes/$icao/ident/$callsign/redirect"
      records["$idx":checked:callsign]=true
    fi

    # First/last seen
    if (( seentime < ${records["$idx":time:firstseen]:-9999999999} )); then records["$idx":time:firstseen]="$seentime"; fi
    if (( seentime > ${records["$idx":time:lastseen]:-0} )); then records["$idx":time:lastseen]="$seentime"; fi

    # Min-distance update (float-safe without awk by string compare fallback)
    curdist=${records["$idx":distance:value]}
    do_update=false
    at_mindist=false
    if [[ -z $curdist ]]; then
      do_update=true
      at_mindist=true
    else
      # numeric compare using bc-less trick: compare as floats via printf %f then string compare is unsafe; instead use scaled ints
      # scale to 2 decimals
      d1=${distance#-}; d2=${curdist#-}
      d1i=${d1%.*}; d1f=${d1#*.}; d1f=${d1f%%[!0-9]*}; d1f=${d1f:0:2}; d1f=${d1f:-0}
      d2i=${d2%.*}; d2f=${d2#*.}; d2f=${d2f%%[!0-9]*}; d2f=${d2f:0:2}; d2f=${d2f:-0}
      s1=$(( 10#$d1i*100 + 10#$d1f ))
      s2=$(( 10#$d2i*100 + 10#$d2f ))
      if (( s1 < s2 )); then
        do_update=true
      fi
    fi
    if $do_update; then
      records["$idx":distance:value]="$distance" && records["$idx":distance:unit]="$DISTUNIT"
      [[ -n $lat ]] && records["$idx":lat]="$lat"
      [[ -n $lon ]] && records["$idx":lon]="$lon"
      [[ -n $altitude ]] && records["$idx":altitude:value]="$altitude" && records["$idx":altitude:unit]="$ALTUNIT" && records["$idx":altitude:reference]="$ALTREF"
      [[ -n $angle ]] && records["$idx":angle:value]="${angle%.*}" && records["$idx":angle:name]="$(deg_to_compass "$angle")"
      [[ -n $gs ]] && records["$idx":groundspeed:value]="$gs" && records["$idx":groundspeed:unit]="$SPEEDUNIT"
      [[ -n $track ]] && records["$idx":track:value]="$track" && records["$idx":track:name]="$(deg_to_compass "$track")"
      records["$idx":time:time_at_mindist]="$seentime"
    fi
    if [[ -z ${ready_to_notify_initial[$idx]+set} ]]; then
      ready_to_notify_initial[idx]="${records["$idx":ready_to_notify]}"
    fi
    initial_ready="${ready_to_notify_initial[$idx]}"
    current_ready="${records["$idx":ready_to_notify]}"
    ready_updated=false
    if [[ "$current_ready" != "$initial_ready" ]]; then
      ready_updated=true
    fi

    if $do_update; then
      if [[ "$initial_ready" == "true" && $ready_updated == false ]]; then
        :
      elif $ready_updated; then
        log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) updated since READ_RECORD; setting FALSE (closest dist detected)"
        records["$idx":ready_to_notify]="false"
      fi
    elif $ready_updated; then
      if [[ "$current_ready" == "false" ]]; then
        log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) was ${current_ready^^} and is now SEMI"
        records["$idx":ready_to_notify]="semi"
      elif [[ "$current_ready" == "semi" ]]; then
        log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) was ${current_ready^^} and is now TRUE"
        records["$idx":ready_to_notify]="true"
      fi
    fi

    if [[ -n $squawk && -z ${records["$idx":squawk:value]} ]]; then
      records["$idx":squawk:value]="$squawk" && records["$idx":squawk:description]="$(GET_SQUAWK_DESCRIPTION "$squawk")"
    fi
    # last - make sure we're storing the idx in the list of processed indices:
    processed_indices["$idx"]=true
  fi

  # ------------------------------------------------
  # Update plane-alert record if in plane-alert mode
  if $mode_pa; then
    # Initialize once-per-record fields
    if [[ -z ${pa_records["$pa_idx":icao]} ]]; then
      pa_records["$pa_idx":icao]="$icao"
      # map link at first touch
      if [[ -n $lat && -n $lon ]]; then
        pa_records["$pa_idx":link:map]="https://$TRACKURL/?icao=$icao&lat=$lat&lon=$lon&showTrace=$tracedate"
      else
        pa_records["$pa_idx":link:map]="https://$TRACKURL/?icao=$icao&showTrace=$tracedate"
      fi
    fi
    
    # get info from the plane-alert-db file:
    if [[ "${pa_records["$pa_idx":checked:db]}" != "true" ]]; then
      IFS=',' read -r Registration CPMG Tag1 Tag2 Tag3 Category Link ImageLink1 ImageLink2 ImageLink3 <<< "$(GET_PA_INFO "$icao")"
      pa_records["$pa_idx":tail]="${pa_records["$pa_idx":tail]:-$Registration}"
      pa_records["$pa_idx":db:cpmg]="${pa_records["$pa_idx":db:cpmg]:-$CPMG}"
      pa_records["$pa_idx":db:tag1]="${pa_records["$pa_idx":db:tag1]:-$Tag1}"
      pa_records["$pa_idx":db:tag2]="${pa_records["$pa_idx":db:tag2]:-$Tag2}"
      pa_records["$pa_idx":db:tag3]="${pa_records["$pa_idx":db:tag3]:-$Tag3}"
      pa_records["$pa_idx":db:category]="${pa_records["$pa_idx":db:category]:-$Category}"
      pa_records["$pa_idx":db:link]="${pa_records["$pa_idx":db:link]:-$Link}"
      pa_records["$pa_idx":db:imagelink1]="${pa_records["$pa_idx":db:imagelink1]:-$ImageLink1}"
      pa_records["$pa_idx":db:imagelink2]="${pa_records["$pa_idx":db:imagelink2]:-$ImageLink2}"
      pa_records["$pa_idx":db:imagelink3]="${pa_records["$pa_idx":db:imagelink3]:-$ImageLink3}"
      pa_records["$pa_idx":checked:db]=true
      if [[ -n "${pa_records["$pa_idx":tail]}" ]]; then pa_records["$pa_idx":checked:tail]=true; fi
      # log_print DEBUG "Plane-Alert: Retrieved DB info for $icao: $Registration / $CPMG / $Tag1,$Tag2,$Tag3 / $Category / $Link / $ImageLink1,$ImageLink2,$ImageLink3"
    fi

    # add a tail if there still isn't any
    if [[ "${pa_records["$pa_idx":checked:tail]}" != "true" && -z "${pa_records["$pa_idx":tail]}" ]]; then
      pa_records["$pa_idx":tail]="$(GET_TAIL "$icao")"
      pa_records["$pa_idx":checked:tail]=true
    fi
    if [[ "${pa_records["$pa_idx":checked:faa]}" != "true" && -n "${pa_records["$pa_idx":tail]}" && -z "${pa_records["$pa_idx":link:faa]}" ]]; then
      if [[ ${icao:0:1} =~ [aA] ]]; then
        pa_records["$pa_idx":link:faa]="https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt=${pa_records["$pa_idx":tail]}"
      elif [[ ${icao:0:1} =~ [cC] ]]; then
        t="${pa_records["$pa_idx":tail]:1}"  # remove leading C
        pa_records["$pa_idx":link:faa]="https://wwwapps.tc.gc.ca/saf-sec-sur/2/ccarcs-riacc/RchSimpRes.aspx?m=%7c${t//-/}%7c"
      fi
      pa_records["$pa_idx":checked:faa]=true
    fi

    # get type
    if [[ "${pa_records["$pa_idx":checked:type]}" != "true" && -z "${pa_records["$pa_idx":type]}" ]]; then
      pa_records["$pa_idx":type]="$(GET_TYPE "${pa_records["$pa_idx":icao]}")"
      pa_records["$pa_idx":checked:type]=true
    fi

    # Callsign handling
    callsign="${callsign//[[:space:]]/}"
    if [[ -n $callsign ]]; then
      pa_records["$pa_idx":callsign]="$callsign"
      pa_records["$pa_idx":link:fa]="https://flightaware.com/live/modes/$icao/ident/$callsign/redirect"
      pa_records["$pa_idx":checked:callsign]=true
    fi

    # First/last seen
    if (( seentime < ${pa_records["$pa_idx":time:firstseen]:-9999999999} )); then pa_records["$pa_idx":time:firstseen]="$seentime"; fi
    if (( seentime > ${pa_records["$pa_idx":time:lastseen]:-0} )); then pa_records["$pa_idx":time:lastseen]="$seentime"; fi

    # Min-distance update (float-safe without awk by string compare fallback)
    curdist=${pa_records["$pa_idx":distance:value]}
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
      pa_records["$pa_idx":distance:value]="$distance" && pa_records["$pa_idx":distance:unit]="$DISTUNIT"
      [[ -n $lat ]] && pa_records["$pa_idx":lat]="$lat"
      [[ -n $lon ]] && pa_records["$pa_idx":lon]="$lon"
      [[ -n $altitude ]] && pa_records["$pa_idx":altitude:value]="$altitude" && pa_records["$pa_idx":altitude:unit]="$ALTUNIT" && pa_records["$pa_idx":altitude:reference]="$ALTREF"
      [[ -n $angle ]] && pa_records["$pa_idx":angle:value]="${angle%.*}" && pa_records["$pa_idx":angle:name]="$(deg_to_compass "$angle")"
      [[ -n $gs ]] && pa_records["$pa_idx":groundspeed:value]="$gs" && pa_records["$pa_idx":groundspeed:unit]="$SPEEDUNIT"
      [[ -n $track ]] && pa_records["$pa_idx":track:value]="$track" && pa_records["$pa_idx":track:name]="$(deg_to_compass "$track")"
      pa_records["$pa_idx":time:time_at_mindist]="$seentime"
      # ensure squawk gets set once if still empty
    fi
    pa_records["$pa_idx":latfirstseen]="${pa_records["$pa_idx":latfirstseen]:-$lat}"
    pa_records["$pa_idx":lonfirstseen]="${pa_records["$pa_idx":lonfirstseen]:-$lon}"

    if [[ -n $squawk && -z ${pa_records["$pa_idx":squawk:value]} ]]; then
      pa_records["$pa_idx":squawk:value]="$squawk"
      pa_records["$pa_idx":squawk:description]="$(GET_SQUAWK_DESCRIPTION "$squawk")"
      if [[ "${pa_squawkmatch["$icao"]}" == "true" ]]; then
        pa_records["$pa_idx":squawk:match]=true
      fi
    fi

    # last - make sure we're storing the idx in the list of processed indices:
    pa_processed_indices["$pa_idx"]=true
  fi
done

# check if we need to process some of the indices that have timed out but that aren't marked yet as complete:

for ((idx=0; idx<=records[maxindex]; idx++)); do
  if [[ "${records["$idx":complete]}" != "true" ]] && (( NOWTIME - ${records["$idx":time:lastseen]:-0} > COLLAPSEWITHIN )); then
    processed_indices["$idx"]=true
    records["$idx":ready_to_notify]=true
    log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) is now TRUE due to collapse timeout"
  fi
done

log_print INFO "Initial processing complete. New/Updated: ${#newrecords[@]}/${#updatedrecords[@]} (PF); ${#pa_newrecords[@]}/${#pa_updatedrecords[@]} (PA). Total number of records is now $((records[maxindex] + 1)) (PF); $((pa_records[maxindex] + 1)) (PA) . Continue adding more info for records ${!processed_indices[*]} (PF) and ${!pa_processed_indices[*]} (PA)."

# try to pre-seed the noisecapt log:
if [[ -n "$REMOTENOISE" ]] && curl -m 30 -fsSL "$REMOTENOISE/noisecapt-$TODAY.log" >/tmp/noisecapt.log 2>/dev/null; then
  noiselog="$(</tmp/noisecapt.log)"
fi

# generate the heatmap data in the background
{ GENERATE_HEATMAPJS
  log_print DEBUG "Wrote Heatmap JS object"
} &

# Now try to add callsigns and owners for those that don't already have them:
# Planefence:
for idx in "${!processed_indices[@]}"; do

  icao="${records["$idx":icao]}"
  callsign="${records["$idx":callsign]}"

  # ------------------------------------------------------------------------------------
  # The first portion of this loop can be done regardless of completeness of the record
  # ------------------------------------------------------------------------------------
  if [[ "${records["$idx":checked:owner]}" != "true" && -n "$callsign" ]]; then
    log_print DEBUG "Getting owner data for record $idx"
    records["$idx":owner]="$(/usr/share/planefence/airlinename.sh "$callsign" "$icao" 2>/dev/null)"
    records["$idx":checked:owner]=true
  fi

  # get images
  if chk_enabled "$SHOWIMAGES" && \
      [[ "${records["$idx":checked:image]}" != "true" ]] && \
      [[ -z "${records["$idx":image:thumblink]}" ]] && \
      [[ -n "$icao" ]]; then
        log_print DEBUG "Getting image data for record $idx"
        records["$idx":image:thumblink]="$(GET_PS_PHOTO "$icao" "thumblink")"
        records["$idx":image:link]="$(GET_PS_PHOTO "$icao" "link")"
        records["$idx":image:file]="$(GET_PS_PHOTO "$icao" "image")"
        records["$idx":checked:image]=true
        records[HASIMAGES]=true
  fi

  # Add a callsign if there isn't any
  if [[ -z "$callsign" ]]; then
    log_print DEBUG "Getting callsign data for record $idx"
    callsign="$(GET_CALLSIGN "$icao")"
    records["$idx":callsign]="${callsign//[[:space:]]/}"
    records["$idx":link:fa]="https://flightaware.com/live/modes/$hex:ident/ident/${callsign//[[:space:]]/}/redirect/"
  fi

  # If TWEET_MINTIME is set, then ensure we're not notifying until at least after this time has passed,
  # of the record is complete.
  if [[ -n "$TWEET_MINTIME" ]]; then
    if [[ "${TWEET_BEHAVIOR,,}" == "post" ]]; then 
      if (( ${records["$idx":time:lastseen]} + TWEET_MINTIME <= seentime )); then
        records["$idx":ready_to_notify]="false"
        log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) is now FALSE due to TWEET_MINTIME not yet passed since last seen"
      fi
    else
      if (( ${records["$idx":time:firstseen]} + TWEET_MINTIME <= seentime )); then
        records["$idx":ready_to_notify]="false"
        log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) is now FALSE due to TWEET_MINTIME not yet passed since first seen"
      fi
    fi
  fi

  # ------------------------------------------------------------------------------------
  # The remainder of this loop only makes sense for complete records. It also only needs to be done once.
  # So skip if not complete.
  # ------------------------------------------------------------------------------------

  if (( NOWTIME - ${records["$idx":time:lastseen]:-99999999999} <= COLLAPSEWITHIN )); then
    continue
  fi

  records["$idx":complete]=true
  records["$idx":ready_to_notify]=true
  log_print DEBUG "[READY_TO_NOTIFY] $idx ($icao $callsign) is now TRUE due to record marked complete"

  # Add noisecapt stuff
  if [[ -n "$REMOTENOISE" ]] && \
      [[ "${records["$idx":checked:noisedata]}" != "true" ]] && \
      [[ -z "${records["$idx":sound:peak]}" ]]; then
        log_print DEBUG "Getting noise data for record $idx"
        # Make sure we have the noiselist
        if [[ -z "$noiselist" ]]; then
          wait "$noise_pid" 2>/dev/null || true
          if [[ -s /tmp/.allnoise ]]; then noiselist="$(</tmp/.allnoise)"; else REMOTENOISE=""; fi
          rm -f /tmp/.allnoise
        fi
        if [[ -n "$REMOTENOISE" ]]; then 
          noisedate="$(awk -F'[.-]' '($1=="noisecapt" && $2 ~ /^[0-9]{6}$/ && $2>m){m=$2} END{if(m!="")print m}' <<< "$noiselist")"
          noisedate="${noisedate:-$TODAY}"
          read -r records["$idx":sound:peak] records["$idx":sound:1min] records["$idx":sound:5min] records["$idx":sound:10min] records["$idx":sound:1hour] records["$idx":sound:loudness] records["$idx":sound:color] <<< "$(GET_NOISEDATA "${records["$idx":time:firstseen]}" "${records["$idx":time:lastseen]}")"
          records["$idx":checked:noisedata]=true
          if [[ -n "${records["$idx":sound:peak]}" ]]; then records[HASNOISE]=true; fi
        fi
  fi
  if [[ -n "$REMOTENOISE" ]] && \
      [[ -n "${records["$idx":sound:peak]}" ]] && \
      [[ "${records["$idx":checked:noisegraph]}" != "true" ]] && \
      [[ -z "${records["$idx":noisegraph:file]}" ]] && \
      [[ -n "${records["$idx":icao]}" ]]; then
        log_print DEBUG "Getting noisegraph for record $idx"
        records["$idx":noisegraph:file]="$(CREATE_NOISEPLOT "${records["$idx":callsign]:-${records["$idx":icao]}}" "${records["$idx":time:firstseen]}" "${records["$idx":time:lastseen]}" "${records["$idx":icao]}")"
        if [[ -n "${records["$idx":noisegraph:file]}" ]]; then
          records["$idx":noisegraph:link]="noise/$(basename "${records["$idx":noisegraph:file]}")"
        fi
        log_print DEBUG "Getting spectrogram for record $idx"
        records["$idx":spectro:file]="$(CREATE_SPECTROGRAM "${records["$idx":time:firstseen]}" "${records["$idx":time:lastseen]}")"
        if [[ -n "${records["$idx":spectro:file]}" ]]; then
          records["$idx":spectro:link]="noise/$(basename "${records["$idx":spectro:file]}")"
        fi
        log_print DEBUG "Getting mp3 for record $idx"
        records["$idx":mp3:file]="$(CREATE_MP3 "${records["$idx":time:firstseen]}" "${records["$idx":time:lastseen]}")"
        if [[ -n "${records["$idx":mp3:file]}" ]]; then
          records["$idx":mp3:link]="noise/$(basename "${records["$idx":mp3:file]}")"
        fi
        records["$idx":checked:noisegraph]=true
  fi

  # get Nominating location. Note - this is slow because we need to do an API call for each lookup
  if [[ "${records["$idx":checked:nominatim]}" != "true" ]] && \
      [[ -n "${records["$idx":lat]}" ]] && \
      [[ -n "${records["$idx":lon]}" ]]; then
    log_print DEBUG "Getting nominatim data for record $idx"
    records["$idx":nominatim]="$(/usr/share/planefence/nominatim.sh --lat="${records["$idx":lat]}" --lon="${records["$idx":lon]}" 2>/dev/null || true)"
    records["$idx":checked:nominatim]=true
  fi
done

# Plane-alert:
  for idx in "${!pa_processed_indices[@]}"; do

  # There's no real concept of "complete" in plane-alert mode, so we just process all records that were touched. We're also setting the "complete" flag; this is not really needed but keeps the logic similar.

  icao="${pa_records["$idx":icao]}"
  callsign="${pa_records["$idx":callsign]}"
  pa_records["$idx":complete]=true  # mark as complete since plane-alert mode has no collapse window

  # ------------------------------------------------------------------------------------
  if [[ "${pa_records["$idx":checked:owner]}" != "true" && -n "$callsign" ]]; then
    log_print DEBUG "Getting owner data for record $idx"
    pa_records["$idx":owner]="$(/usr/share/planefence/airlinename.sh "$callsign" "$icao" 2>/dev/null)"
    pa_records["$idx":checked:owner]=true
  fi

  # get images
  if chk_enabled "$SHOWIMAGES" && \
      [[ "${pa_records["$idx":checked:image]}" != "true" ]] && \
      [[ -z "${pa_records["$idx":image:thumblink]}" ]] && \
      [[ -n "$icao" ]]; then
        log_print DEBUG "Getting image data for record $idx"
        pa_records["$idx":image:thumblink]="$(GET_PS_PHOTO "$icao" "thumblink")"
        pa_records["$idx":image:link]="$(GET_PS_PHOTO "$icao" "link")"
        pa_records["$idx":image:file]="$(GET_PS_PHOTO "$icao" "image")"
        pa_records["$idx":checked:image]=true
        pa_records[HASIMAGES]=true
  fi

  # Add a callsign if there isn't any
  if [[ -z "$callsign" ]]; then
    log_print DEBUG "Getting callsign data for record $idx"
    callsign="$(GET_CALLSIGN "$icao")"
    pa_records["$idx":callsign]="${callsign//[[:space:]]/}"
    pa_records["$idx":link:fa]="https://flightaware.com/live/modes/$hex:ident/ident/${callsign//[[:space:]]/}/redirect/"
  fi

  # get Nominating location. Note - this is slow because we need to do an API call for each lookup
  if [[ "${pa_records["$idx":checked:nominatim]}" != "true" ]] && \
      [[ -n "${pa_records["$idx":latfirstseen]}" ]] && \
      [[ -n "${pa_records["$idx":lonfirstseen]}" ]]; then
    log_print DEBUG "Getting nominatim data for record $idx"
    pa_records["$idx":nominatim]="$(/usr/share/planefence/nominatim.sh --lat="${pa_records["$idx":latfirstseen]}" --lon="${pa_records["$idx":lonfirstseen]}" 2>/dev/null || true)"
    pa_records["$idx":checked:nominatim]=true
  fi
done

# get route information in bulk (single API call)
if ! chk_disabled "$CHECKROUTE"; then
  log_print DEBUG "Getting route data for record $idx"
  GET_ROUTE_BULK
fi

if [[ -z "${records[HASROUTE]}" ]]; then records[HASROUTE]=false; fi
if [[ -z "${records[HASIMAGES]}" ]]; then records[HASIMAGES]=false; fi
if [[ -z "${pa_records[HASROUTE]}" ]]; then pa_records[HASROUTE]=false; fi
if [[ -z "${pa_records[HASIMAGES]}" ]]; then pa_records[HASIMAGES]=false; fi
if [[ -z "${records[HASNOISE]}" || -z "$REMOTENOISE" ]] || chk_disabled "$REMOTENOISE"; then records[HASNOISE]=false; else LINK_LATEST_SPECTROFILE; fi

# Apply FUDGELOC rounding to station coordinates
case "${FUDGELOC:-3}" in
  0) _fudge_decimals=0 ;;
  1) _fudge_decimals=1 ;;
  2) _fudge_decimals=2 ;;
  3) _fudge_decimals=3 ;;
  4) _fudge_decimals=4 ;;
  *) _fudge_decimals=3 ;;
esac
printf -v _fudged_lat "%.${_fudge_decimals}f" "$LAT"
printf -v _fudged_lon "%.${_fudge_decimals}f" "$LON"

# Provide station metadata for front-end summaries
records["station:dist:value"]="${DIST:-}"
records["station:dist:unit"]="${DISTUNIT:-}"
records["station:altitude:value"]="${MAXALT:-}"
records["station:altitude:unit"]="${ALTUNIT:-}"
records["station:lat"]="${_fudged_lat:-}"
records["station:lon"]="${_fudged_lon:-}"
records["station:version"]="$VERSION"
records["station:heatmapzoom"]="$HEATMAPZOOM"
records["station:me"]="$MY"
records["station:myurl"]="$MYURL"
records["station:motd"]="$PF_MOTD"
records["station:histtime"]="$HISTTIME"
records["LASTUPDATE"]="$NOWTIME"

pa_records["station:dist:value"]="${DIST:-}"
pa_records["station:dist:unit"]="${DISTUNIT:-}"
pa_records["station:altitude:value"]="${MAXALT:-}"
pa_records["station:altitude:unit"]="${ALTUNIT:-}"
pa_records["station:lat"]="${_fudged_lat:-}"
pa_records["station:lon"]="${_fudged_lon:-}"
pa_records["station:version"]="$VERSION"
pa_records["station:me"]="$MY"
pa_records["station:myurl"]="$MYURL"
pa_records["station:me"]="$MY"
pa_records["station:myurl"]="$MYURL"
pa_records["station:motd"]="$PA_MOTD"
if [[ "$PA_RANGE" != "999999" ]]; then 
  pa_records["station:range"]="$PA_RANGE"
else 
  pa_records["station:range"]="-1"; 
fi
pa_records["LASTUPDATE"]="$NOWTIME"

log_print INFO "Processing complete. Now writing results to disk..."

# ==========================
# Save state
# ==========================
{ WRITE_RECORDS ignore-lock
  log_print DEBUG "Wrote RECORDSFILE"
} &

# ==========================
# Emit snapshots
# ==========================

if chk_enabled "$GENERATE_CSV"; then
  { GENERATE_PF_CSV
    log_print DEBUG "Wrote PF CSV object to $CSVOUT"
  } &
fi
  { GENERATE_PF_JSON
    log_print DEBUG "Wrote PF JSON object to $JSONOUT"
  } &

if chk_enabled "$PLANEALERT"; then
  if chk_enabled "$GENERATE_CSV"; then  
    { GENERATE_PA_CSV
      log_print DEBUG "Wrote PA CSV object to ${PA_CSVOUT}"
    } &
  fi
  { GENERATE_PA_JSON
    log_print DEBUG "Wrote PA JSON object to ${PA_JSONOUT}"
  } &
fi


# Cleanup the per-run noise cache so it doesn't outlive this execution
rm -rf "$NOISECACHE_DIR"

# wait for any straggler background processes to finish
wait 2>/dev/null || true

log_print INFO "Done."
