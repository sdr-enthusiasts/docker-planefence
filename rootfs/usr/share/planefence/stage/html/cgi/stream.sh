#!/usr/bin/env bash
set -eo pipefail

DOCROOT="/usr/share/planefence/html"
RUNROOT="/run/planefence"
PLANE_ALERT_CONF="/usr/share/planefence/plane-alert.conf"

# UTC dates to avoid TZ drift
utc_today="$(date -u +%y%m%d)"
# GNU date or BSD date (macOS) compatible yesterday
utc_yday="$(date -u -d 'yesterday' +%y%m%d 2>/dev/null || date -u -v-1d +%y%m%d)"

plane_alert_hist_days() {
  local val
  val="$(sed -n 's/^\s*HISTTIME\s*=\s*\(.*\)$/\1/p' "$PLANE_ALERT_CONF" | head -n1)"
  val="${val%%#*}"
  val="${val//\"/}"
  val="${val//\'/}"
  val="${val//[[:space:]]/}"
  [[ "$val" =~ ^[0-9]+$ ]] || val=14
  printf '%s' "$val"
}

choose_json_for_date() {
  local mode="${1:-}" req_date="${2:-}" cand
  if [[ -z "$mode" || -z "$req_date" || ! "$req_date" =~ ^[0-9]{6}$ ]]; then
    printf ''
    return
  fi

  # Preferred locations: runtime (today) then persisted history
  local -a candidates=(
    "${RUNROOT}/${mode}-${req_date}.json"
    "${DOCROOT}/${mode}-${req_date}.json"
    "${DOCROOT}/${mode}/${mode}-${req_date}.json"
  )

  for cand in "${candidates[@]}"; do
    [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }
  done

  printf ''
}

build_plane_alert_all_json() {
  local hist_days files=() tmp mode="plane-alert" MAX_ROWS=500
  hist_days="$(plane_alert_hist_days)"

  # Walk days from today backwards (UTC), collect newest files first until we satisfy MAX_ROWS or HISTTIME
  local total_rows=0 rows_in_file=0 day=0 req_date file
  for (( day=0; day<hist_days; day++ )); do
    req_date="$(date -u -d "-${day} days" +%y%m%d 2>/dev/null || true)"
    [[ -z "$req_date" ]] && continue
    file="$(choose_json_for_date "$mode" "$req_date" || true)"
    [[ -z "$file" ]] && continue

    rows_in_file=$(jq -r 'if (type=="array") then ( ( (.[0]|type=="object" and (.[0]|has("index")|not))? (.[1:]|length) : length ) ) else 0 end' "$file" 2>/dev/null || echo 0)
    [[ "$rows_in_file" =~ ^[0-9]+$ ]] || rows_in_file=0

    files+=("$file")
    total_rows=$(( total_rows + rows_in_file ))
    if (( total_rows >= MAX_ROWS )); then
      break
    fi
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    tmp="$(mktemp)" || return 1
    printf '[]' > "$tmp"
    printf '%s' "$tmp"
    return 0
  fi

  # Capture today's LASTUPDATE (if present) to propagate into combined globals
  local TODAY_LASTUPDATE=""
  TODAY_LASTUPDATE=$(jq -r '
    if (.[0]|type)=="object" and ((.[0]|has("index"))|not) then
      (.[0].LASTUPDATE // "")
    else "" end
  ' "${files[0]}" 2>/dev/null || true)
  [[ "$TODAY_LASTUPDATE" == "null" ]] && TODAY_LASTUPDATE=""

  tmp="$(mktemp)" || return 1
  if jq -s --arg todays_file "${files[0]}" --arg today_lastupdate "$TODAY_LASTUPDATE" '
    def split_parts(arr):
      if (arr|type)!="array" then {globals:{}, rows:[]}
      else (
        (arr[0]|type=="object" and (arr[0]|has("index")|not)) as $has_globals
        | {
            globals: (if $has_globals then arr[0] else {} end),
            rows: (if $has_globals then (arr[1:]) else arr end)
          }
      ) end;

    reduce .[] as $f (
      {globals:null, rows:[], today_globals:null};
      (split_parts($f)) as $chunk
      | .globals = (if ($chunk.globals|type)=="object" and ($chunk.globals|length)>0 then $chunk.globals else .globals end)
      | .rows = (if ($chunk.rows|type)=="array" then (.rows + $chunk.rows) else .rows end)
      | .today_globals = (if (.today_globals==null and ($f|tostring)==$todays_file and ($chunk.globals|type)=="object") then $chunk.globals else .today_globals end)
    )
    | .globals = (if (.globals|type)=="object" then .globals else {} end)
    | .today_globals = (if (.today_globals|type)=="object" then .today_globals else {} end)
    | .rows = (.rows[0:'"$MAX_ROWS"'])                    # keep newest-first subset
    | .rows = (.rows | reverse)                             # oldest-first for reindex
    | .rows = [ range(0; (.rows|length)) as $i | (.rows[$i] // {}) + {index:$i} ]
    | .rows = (.rows | reverse)                             # emit newest-first
    | .globals.maxindex = ((.rows|length) - 1)
    | .globals.totallines = (.rows|length)
    | .globals.LASTUPDATE = (
      if ($today_lastupdate|length) > 0 then $today_lastupdate
      elif (.today_globals|has("LASTUPDATE")) then .today_globals.LASTUPDATE
      elif (.globals|has("LASTUPDATE")) then .globals.LASTUPDATE
      else 0 end)
    | [ .globals ]
      + [ .rows[] ]
  ' "${files[@]}" > "$tmp"; then
    printf '%s' "$tmp"
    return 0
  fi

  rm -f "$tmp"
  return 1
}

printf 'Content-Type: application/x-ndjson\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Pragma: no-cache\r\n'
printf 'Expires: 0\r\n'
printf 'X-Content-Type-Options: nosniff\r\n'
printf '\r\n'

choose_json() {
  local mode="${1:-planefence}"
  local req_date="${2:-}"
  local cand

  if [[ -n "${req_date}" ]]; then
    cand="$(choose_json_for_date "$mode" "$req_date")"
    [[ -n "$cand" ]] && { printf '%s' "$cand"; return; }
    printf ''
    return
  fi

  cand="${RUNROOT}/${mode}-${utc_today}.json"
  [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }
  cand="${DOCROOT}/${mode}-${utc_today}.json"
  [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }

  cand="${RUNROOT}/${mode}-${utc_yday}.json"
  [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }
  cand="${DOCROOT}/${mode}-${utc_yday}.json"
  [[ -r "$cand" && -s "$cand" ]] && { printf '%s' "$cand"; return; }

  # latest rolling backup for the selected mode
  local alt
  # shellcheck disable=SC2012
  alt="$(ls -1t "${DOCROOT}"/."${mode}"-records*.json 2>/dev/null | head -1 || true)"
  [[ -n "${alt:-}" && -r "$alt" && -s "$alt" ]] && { printf '%s' "$alt"; return; }

  printf ''  # none
}

# get env var from http GET or CLI key=value pairs
method="${REQUEST_METHOD:-GET}"
FILTER_MODE="planefence"
REQUESTED_DATE=""
TMP_ALL_FILE=""

# Build a unified list of query-like pairs
declare -a pf_qs=()
if [[ "$method" == "GET" && -n "${QUERY_STRING:-}" ]]; then
  IFS='&' read -ra pf_qs <<< "${QUERY_STRING}"
elif [[ $# -gt 0 ]]; then
  pf_qs=("$@")
fi

if [[ ${#pf_qs[@]} -gt 0 ]]; then
  for pair in "${pf_qs[@]}"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    [[ "$pair" == "$key" ]] && val=""
    case "$key" in
      mode)
        [[ "$val" == "plane-alert" ]] && FILTER_MODE="plane-alert"
        [[ "$val" == "planefence" ]] && FILTER_MODE="planefence"
        ;;
      date)
        if [[ "$val" =~ ^([0-9]{6})$ ]]; then
          REQUESTED_DATE="${BASH_REMATCH[1]}"
        elif [[ "$val" == "all" ]]; then
          REQUESTED_DATE="all"
        fi
        ;;
    esac
  done
elif [[ "$1" == "mode=plane-alert" ]]; then
  FILTER_MODE="plane-alert"
fi

if [[ "$FILTER_MODE" == "plane-alert" && "$REQUESTED_DATE" == "all" ]]; then
  TMP_ALL_FILE="$(build_plane_alert_all_json || true)"
  JSONFILE="$TMP_ALL_FILE"
else
  JSONFILE="$(choose_json "$FILTER_MODE" "$REQUESTED_DATE" || true)"
fi

if [[ -n "$TMP_ALL_FILE" ]]; then
  cleanup_all_tmp() { [[ -n "$TMP_ALL_FILE" ]] && rm -f "$TMP_ALL_FILE"; }
  trap cleanup_all_tmp EXIT
fi
if [[ -z "${JSONFILE:-}" ]]; then
  if [[ "${REQUESTED_DATE:-}" == "all" ]]; then
    printf '{"error":"no plane-alert history files found (all)"}\n'
  elif [[ -n "${REQUESTED_DATE:-}" ]]; then
    printf '{"error":"missing or unreadable: %s"}\n' \
      "$(printf '%s' "${DOCROOT}/${FILTER_MODE}-${REQUESTED_DATE}.json" | sed 's/"/\\"/g')"
  else
    printf '{"error":"missing or unreadable: %s and %s"}\n' \
      "$(printf '%s' "${DOCROOT}/${FILTER_MODE}-${utc_today}.json" | sed 's/"/\\"/g')" \
      "$(printf '%s' "${DOCROOT}/${FILTER_MODE}-${utc_yday}.json" | sed 's/"/\\"/g')"
  fi
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
    "screenshot:file","image:file","noisegraph:file","spectro:file","mp3:file",
    "db:cpmg","db:tag1","db:tag2","db:tag3","db:category","db:link","db:imagelink1","db:imagelink2",
    "mode"
  ];
  def globals: [
    "HASIMAGES","HASNOISE","LASTUPDATE","maxindex","HASROUTE","totallines"
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
