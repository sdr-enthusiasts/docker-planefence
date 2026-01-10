#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2026 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
#
# This script converts a Plane-Alert.csv file generatedd by Plane-Alert v5 into 
# a Planefence record file for v6.
# It will check if there's already an existing record file. If so, it will not overwrite
# existing records, but only add new ones.

DEBUG=true

source /scripts/pf-common
source /usr/share/planefence/plane-alert.conf

CSVFILE="${OUTFILE:-/usr/share/planefence/plane-alert/plane-alert.csv}"
PLANEALERT="${PLANEALERT:-true}"
RETENTION_DAYS=14
TODAY_EPOCH=$(date -d "00:00:00" +%s)

PA_FILE="/usr/share/planefence/persist/.internal/plane-alert-db.txt"

if [[ ! -f "$CSVFILE" ]]; then
  log_print ERROR "Input file $CSVFILE not found. Exiting."
  exit 1
fi

# --------------------------
# Functions
# --------------------------

GET_PA_INFO () {
  local lookup="$1"
  if ! chk_enabled "$PLANEALERT" || [[ -z $lookup ]] || [[ ! -f $PA_FILE ]]; then
    log_print DEBUG "Plane-Alert: No PA data available for $lookup (PLANEALERT=$PLANEALERT, PA_FILE=$PA_FILE)" 
    return
  fi
  local header_line
  header_line="$(sed -En '/^\s*ALERTHEADER=/ { s/^\s*ALERTHEADER='\''?([^'\'']*)'\''?/\1/; p; q }' /usr/share/planefence/plane-alert.conf)"
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

GET_TYPE () {
  local apiUrl="https://api.adsb.lol/v2/hex"
  local header_line

  header_line="$ALERTHEADER"
  header_line="${header_line:-$(head -n1 "$PA_FILE" 2>/dev/null)}"
  header_line="${header_line//[#$]/}"
  if [[ -n "$header_line" ]]; then
    colnumber=0
    IFS=',' read -r -a __pa_header <<< "$header_line"
    for col in "${__pa_header[@]}"; do
      if [[ ${col//[#?]/} == "ICAO Type" ]]; then
        break
      fi
      colnumber=$((colnumber + 1))
    done
    if [[ ${__pa_header[colnumber]} == "ICAO Type" ]]; then
      local record
      record="$(awk -F',' -v key="$1" -v col="$colnumber" 'NR>1 && $1==key { print $col; exit }' "$PA_FILE")"
      record="${record#\"}"
      record="${record%\"}"
      if [[ -n $record ]]; then
        printf '%s\n' "$record"
        return
      fi
    fi
  fi
  curl -m 30 -sSL "$apiUrl/$1" | jq -r '.ac[] .t' 2>/dev/null
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
     link="$(jq -r 'try .photos[].link | select(. != null) | .' <<< "$json" | head -n1)" && \
     thumb="$(jq -r 'try .photos[].thumbnail_large.src | select(. != null) | .' <<< "$json" | head -n1)" && \
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

# Read existing records to avoid duplicates
READ_RECORDS

if [[ ! $DEBUG ]] && (( pa_records[maxindex] >= 0 )); then
  log_print DEBUG "There are already ${pa_records[maxindex]} existing records. Won't add old records; exiting..."
  exit 0
fi

log_print DEBUG "Converting Plane-Alert CSV file $CSVFILE to Planefence record format..."

totalrecords=$(wc -l < "$CSVFILE")
linesread=0
retention=$(( TODAY_EPOCH - (RETENTION_DAYS*86400) ))
retention_iso=$(date -d "@$retention" +%F)

# Pre-filter the CSV: keep only rows with ISO dates >= retention to avoid expensive per-line date parsing later.
# Be tolerant of quotes, whitespace, and CRLF line endings; keep non-ISO rows (e.g., headers) so the loop can log/skip them explicitly.
mapfile -t pa_lines < <(
  awk -F',' -v r="$retention_iso" '
    /^[[:space:]]*$/ { next }
    {
      d=$5
      gsub(/\r/, "", d)
      gsub(/^"|"$/, "", d)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
      d_norm=d
      gsub(/\//, "-", d_norm)
      if (d_norm ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) { if (d_norm >= r) print; next }
      # keep non-ISO rows so downstream can decide (typically headers)
      print
    }
  ' "$CSVFILE"
)
filteredrecords=${#pa_lines[@]}
log_print DEBUG "Retention filter kept $filteredrecords of $totalrecords rows (>= $retention_iso)."

for LINE in "${pa_lines[@]}"; do
  linesread=$((linesread + 1))
  # shellcheck disable=SC2034
  IFS=, read -r icao tail owner long_type date time lat lon callsign adsblink rest <<< "$LINE"

  # guard against non-ISO dates that slipped through (e.g., header)
  date=${date//$'\r'/}
  date=${date%\"}
  date=${date#\"}
  date=${date#"${date%%[![:space:]]*}"}   # trim leading space
  date=${date%"${date##*[![:space:]]}"}   # trim trailing space
  date_norm=${date//\//-}
  if [[ ! $date_norm =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    log_print DEBUG "Skipping line $linesread with non-ISO date '$date'"
    continue
  fi

  idx=$((pa_records[maxindex] + 1))
  datetime_epoch=$(date -d "${date} ${time}" +%s)

  # get info from the plane-alert-db file:
  #log_print DEBUG "calling GET_PA_INFO for ICAO $icao"
  IFS=',' read -r Registration CPMG Tag1 Tag2 Tag3 Category Link ImageLink1 ImageLink2 ImageLink3 <<< "$(GET_PA_INFO "$icao")"
  #log_print DEBUG "returned from calling GET_PA_INFO for ICAO $icao"
  pa_records["$idx":tail]="${tail:-$Registration}"
  pa_records["$idx":checked:tail]=true
  pa_records["$idx":db:cpmg]="${pa_records["$idx":db:cpmg]:-$CPMG}"
  pa_records["$idx":db:tag1]="${pa_records["$idx":db:tag1]:-$Tag1}"
  pa_records["$idx":db:tag2]="${pa_records["$idx":db:tag2]:-$Tag2}"
  pa_records["$idx":db:tag3]="${pa_records["$idx":db:tag3]:-$Tag3}"
  pa_records["$idx":db:category]="${pa_records["$idx":db:category]:-$Category}"
  pa_records["$idx":db:link]="${pa_records["$idx":db:link]:-$Link}"
  pa_records["$idx":db:imagelink1]="${pa_records["$idx":db:imagelink1]:-$ImageLink1}"
  pa_records["$idx":db:imagelink2]="${pa_records["$idx":db:imagelink2]:-$ImageLink2}"
  pa_records["$idx":db:imagelink3]="${pa_records["$idx":db:imagelink3]:-$ImageLink3}"
  pa_records["$idx":checked:db]=true
  if [[ ${icao:0:1} =~ [aA] ]]; then
    pa_records["$idx":link:faa]="https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt=${pa_records["$idx":tail]}"
  elif [[ ${icao:0:1} =~ [cC] ]]; then
    t="${pa_records["$idx":tail]:1}"  # remove leading C
    pa_records["$idx":link:faa]="https://wwwapps.tc.gc.ca/saf-sec-sur/2/ccarcs-riacc/RchSimpRes.aspx?m=%7c${t//-/}%7c"
  fi
  pa_records["$idx":checked:faa]=true
  # get type
  if [[ "${pa_records["$idx":checked:type]}" != "true" && -z "${pa_records["$idx":type]}" ]]; then
    #log_print DEBUG "calling GET_TYPE for ICAO $icao"
    pa_records["$idx":type]="$(GET_TYPE "$icao")"
    #log_print DEBUG "returned from calling GET_TYPE for ICAO $icao"
    pa_records["$idx":checked:type]=true
  fi
  # Callsign handling
  callsign="${callsign//[[:space:]]/}"
  if [[ -n $callsign ]]; then
    pa_records["$idx":callsign]="$callsign"
    pa_records["$idx":link:fa]="https://flightaware.com/live/modes/$icao/ident/$callsign/redirect"
    pa_records["$idx":checked:callsign]=true
  fi

  # shellcheck disable=SC2034
  if (( ${pa_last_idx_for_icao["$icao"]:-0} < datetime_epoch)); then pa_last_idx_for_icao["$icao"]=$idx; fi
  pa_records["$idx":complete]=true
  pa_records["$idx":icao]="$icao"
  pa_records["$idx":owner]="$owner"
  pa_records["$idx":callsign]="$call"; pa_records["$idx":checked:callsign]=true
  pa_records["$idx":lat]="$lat"
  pa_records["$idx":lon]="$lon"
  pa_records["$idx":time:firstseen]="$datetime_epoch"
  pa_records["$idx":time:lastseen]="$datetime_epoch"
  pa_records["$idx":time:time_at_mindist]="$datetime_epoch"
  pa_records["$idx":complete]="false"
  pa_records["$idx":link:map]="$adsblink"
  pa_records[maxindex]=$idx

  # get images
  if chk_enabled "$SHOWIMAGES"; then
      #log_print DEBUG "calling GET_PS_PHOTO for ICAO $icao"
      pa_records["$idx":image:thumblink]="$(GET_PS_PHOTO "$icao" "thumblink")"
      pa_records["$idx":image:link]="$(GET_PS_PHOTO "$icao" "link")"
      pa_records["$idx":image:file]="$(GET_PS_PHOTO "$icao" "image")"
      #log_print DEBUG "returned from calling GET_PS_PHOTO for ICAO $icao"
      pa_records["$idx":checked:image]=true
      pa_records[HASIMAGES]=true
  fi
  # nominatim lookup
  # log_print DEBUG "calling nominatim.sh for ICAO $icao (lat=$lat, lon=$lon)"
  # pa_records["$idx":nominatim]="$(/usr/share/planefence/nominatim.sh --lat="$lat" --lon="$lon" 2>/dev/null || true)"
  # log_print DEBUG "returned from calling nominatim.sh for ICAO $icao"
  # pa_records["$idx":checked:nominatim]=true


  log_print DEBUG "Added record for ICAO $icao as index $idx (line $linesread of $filteredrecords)."

done

