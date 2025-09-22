#!/usr/bin/env bash
# Fast Nominatim reverse with cache and rounding; errors -> stderr
set -euo pipefail

lat=""; lon=""; raw=false
for arg in "$@"; do
  case "${arg,,}" in
    --lat=*) lat="${arg#*=}";;
    --lon=*) lon="${arg#*=}";;
    --raw)   raw=true;;
  esac
done
if [[ -z $lat || -z $lon ]]; then
  printf 'Missing argument. Usage: %s --lat=xx.xxxx --lon=yy.yyyy\n' "${0##*/}" >&2
  exit 1
fi

ROUND=3
CACHE_DIR=${NOMI_CACHE_DIR:-/tmp/nominatim-cache}
mkdir -p "$CACHE_DIR"

round() { printf "%.${ROUND}f" "$1"; }
rlat=$(round "$lat"); rlon=$(round "$lon")
key="${rlat},${rlon}"
cache_file="$CACHE_DIR/${key//,/_}.json"

ua="planefence-nominatim/1.0 (+https://github.com/sdr-enthusiasts/docker-planefence)"
url="https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$rlat&lon=$rlon&addressdetails=1"

# Fetch or cache
if [[ -s $cache_file && $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0))) -lt ${NOMI_TTL:-604800} ]]; then
  result=$(<"$cache_file")
else
  if [[ -n ${NOMI_RATE_SLEEP:-} ]]; then sleep "$NOMI_RATE_SLEEP"; else sleep 0.2; fi
  if ! result="$(curl -sS --fail -H "User-Agent: $ua" "$url")"; then
    printf 'Error fetching nominatim results - network\n' >&2
    exit 1
  fi
  if [[ $result == *'"error"'* ]]; then
    if [[ $result == *"Unable to geocode"* ]]; then
      : >"$cache_file"
      exit 0
    else
      msg=$(printf '%s' "$result" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"$[^"]*$".*/\1/p')
      printf 'Error fetching nominatim results: %s\n' "${msg:-unknown error}" >&2
      exit 1
    fi
  fi
  printf '%s' "$result" >"$cache_file".tmp && mv -f "$cache_file".tmp "$cache_file"
fi

$raw && { printf '%s\n' "$result"; exit 0; }

if command -v jq >/dev/null 2>&1; then
  city=$(jq -r '.address.city // empty' <<<"$result")
  town=$(jq -r '.address.town // empty' <<<"$result")
  municipality=$(jq -r '.address.municipality // empty' <<<"$result")
  state=$(jq -r '.address.state // empty' <<<"$result")
  # country=$(jq -r '.address.country // empty' <<<"$result")
  county=$(jq -r '.address.county // empty' <<<"$result")
  country_code=$(jq -r '.address.country_code // empty' <<<"$result")
  postcode=$(jq -r '.address.postcode // empty' <<<"$result")
else
  parse_json() { awk -v k="$1" -v s="$2" '
    function unq(x){gsub(/\\"/,"\"",x);gsub(/\\\\/,"\\",x);return x}
    BEGIN{match(k,/^[^.]+/); base=substr(k,1,RLENGTH); sub(/^[^.]+\./,"",k); subkey=k}
    {
      gsub(/\r/,"")
      if($0 ~ /"address"\s*:/){inaddr=1}
      if(inaddr && $0 ~ "\""subkey"\"[[:space:]]*:[[:space:]]*\""){
        match($0, "\""subkey"\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")
        str=substr($0,RSTART,RLENGTH)
        sub(/^[^:]*:[[:space:]]*"/,"",str); sub(/"$/,"",str)
        print unq(str); exit
      }
    }' <<<"$result"; }
  city=$(parse_json address.city)
  town=$(parse_json address.town)
  municipality=$(parse_json address.municipality)
  state=$(parse_json address.state)
 # country=$(parse_json address.country)
  county=$(parse_json address.county)
  country_code=$(parse_json address.country_code)
  postcode=$(parse_json address.postcode)
fi

case "${country_code,,}" in
  de) county="";;
  be) state="";;
  fr) state=""; [[ -n $postcode ]] && county="$county (${postcode:0:2})";;
esac

ret=""
[[ -n $city ]] && ret="$city, "
[[ -z $ret && -n $town ]] && ret="$town, "
[[ -z $ret && -n $municipality ]] && ret="$municipality, "
[[ -n $county ]] && ret+="$county, "
[[ -n $state ]] && ret+="$state, "
[[ -n $country_code ]] && ret+="${country_code^^}"
printf '%s\n' "$ret"
