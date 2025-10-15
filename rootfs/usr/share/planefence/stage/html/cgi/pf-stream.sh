#!/usr/bin/env bash
set -euo pipefail

DOCROOT="/usr/share/planefence/html"

# UTC dates to avoid TZ drift
utc_today="$(date -u +%y%m%d)"
# GNU date or BSD date (macOS) compatible yesterday
utc_yday="$(date -u -d 'yesterday' +%y%m%d 2>/dev/null || date -u -v-1d +%y%m%d)"

printf 'Content-Type: application/x-ndjson\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Pragma: no-cache\r\n'
printf 'Expires: 0\r\n'
printf 'X-Content-Type-Options: nosniff\r\n'
printf '\r\n'

choose_json() {
  local cand

  cand="${DOCROOT}/planefence-${utc_today}.json"
  [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }

  cand="${DOCROOT}/planefence-${utc_yday}.json"
  [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }

  # latest rolling backup
  local alt
  # shellcheck disable=SC2012
  alt="$(ls -1t "${DOCROOT}"/.planefence-records*.json 2>/dev/null | head -1 || true)"
  [[ -n "${alt:-}" && -r "$alt" && -s "$alt" ]] && { printf '%s' "$alt"; return; }

  printf ''  # none
}

JSONFILE="$(choose_json || true)"
if [[ -z "${JSONFILE:-}" ]]; then
  printf '{"error":"missing or unreadable: %s and %s"}\n' \
    "$(printf '%s' "${DOCROOT}/planefence-${utc_today}.json" | sed 's/"/\\"/g')" \
    "$(printf '%s' "${DOCROOT}/planefence-${utc_yday}.json" | sed 's/"/\\"/g')"
  exit 0
fi

# Stream schema then rows
if ! jq -r '
  def pri: [
    "index","icao","tail","callsign","type","owner","route","nominatim",
    "time:firstseen","time:time_at_mindist","time:lastseen","distance:value","distance:unit","complete",
    "lat","lon","altitude:value","altitude:unit","altitude:reference","groundspeed:value","groundspeed:unit",
    "track:value","track:name","angle:value","angle:name","squawk:value","squawk:description",
    "link:map","image:link","image:thumblink",
    "noisegraph:link","spectro:link","mp3:link",
    "link:fa","link:faa",
    "discord:link","discord:notified","bsky:link","bsky:notified","telegram:link","telegram:notified","mqtt:notified",
    "sound:color","sound:loudness","sound:peak",
    "screenshot:file","image:file","noisegraph:file","spectro:file","mp3:file"
  ];
  def globals: [
    "HASIMAGES","HASNOISE","LASTUPDATE","maxindex","HASROUTE"
  ];

  def flat1:
    if type!="object" then {}
    else ( . as $o
      | reduce (keys_unsorted[]) as $k ({};
          ($o[$k]) as $v
          | if $v==null then .
            elif ($v|type)=="object" then
              reduce (($v|keys_unsorted[])) as $kk (.;
                ($v[$kk]) as $vv
                | if $vv==null or (($vv|type)=="array") or (($vv|type)=="object") then .
                  else . + { ($k+":"+$kk): $vv } end)
            elif ($v|type)=="array" then .
            else . + { ($k): $v } end))
    end;

  def as_str_or_empty($x): if $x==null then "" else ($x|tostring) end;

  if type!="array" then {error:"expected array root"} | tojson
  else
    # Detect globals in first element (must be object and not have "index")
    ( .[0] | (type=="object") and (has("index")|not) ) as $has_globals
    | ( if $has_globals then .[0] else {} end ) as $globals
    | ( if $has_globals then .[1:] else . end ) as $rows

    # 1) Emit globals object (always emit, possibly empty {})
    | ({__globals: $globals} | tojson),

      # 2) Emit schema
      ({__columns: pri} | tojson),

      # 3) Emit rows
      ( $rows[]? | flat1 ) as $r
      | if ($r|length)==0
        then (reduce pri[] as $c ({}; .+{($c):""})) | tojson
        else (
          reduce pri[] as $c ({}; .+{($c): as_str_or_empty($r[$c])})
          + (reduce ((($r|keys)-pri)|sort)[] as $c ({}; .+{($c): as_str_or_empty($r[$c])}))
        ) | tojson
        end
  end
' -- "$JSONFILE"; then
  err=$?
  printf '{"error":"jq failed with exit %d"}\n' "$err"
fi
