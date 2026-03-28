#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154,SC2001
# -----------------------------------------------------------------------------------
# Copyright 2022-2026 Ramon F. Kolb, kx1t - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
# This script streams planefence, plane-alert, or Plane-Alert candidates via CGI
# Usage:
#   stream.sh [mode=planefence|plane-alert|pa-candidates] [date=YYMMDD|all]
#   or via HTTP GET with query string parameters:
#   http://<server>/cgi/stream.sh?mode=planefence|plane-alert|pa-candidates[&date=YYMMDD|all]
# -----------------------------------------------------------------------------------
set -eo pipefail

source /scripts/pf-common

DOCROOT="/usr/share/planefence/html"
RUNROOT="/run/planefence"

# UTC dates to avoid TZ drift
utc_today="$(date -u +%y%m%d)"
# GNU date or BSD date (macOS) compatible yesterday
utc_yday="$(date -u -d 'yesterday' +%y%m%d 2>/dev/null || date -u -v-1d +%y%m%d)"

PLANEALERT_CFG_VALUE="$(GET_PARAM pf PLANEALERT || true)"
if ! chk_disabled "${PLANEALERT_CFG_VALUE:-}"; then
  PLANEALERT_ENABLED=true
  PLANEALERT_ENABLED_HEADER=1
else
  PLANEALERT_ENABLED=false
  PLANEALERT_ENABLED_HEADER=0
fi

PLANEFENCE_CFG_VALUE="$(GET_PARAM pf PLANEFENCE || true)"
if ! chk_disabled "${PLANEFENCE_CFG_VALUE:-}"; then
  #PLANEFENCE_ENABLED=true
  PLANEFENCE_ENABLED_HEADER=1
else
  #PLANEFENCE_ENABLED=false
  PLANEFENCE_ENABLED_HEADER=0
fi

PA_CANDIDATES_CFG_VALUE="$(GET_PARAM base PA_COLLECT_CANDIDATES || true)"
if chk_disabled "${PA_CANDIDATES_CFG_VALUE:-}"; then
  PA_CANDIDATES_ENABLED=false
  PA_CANDIDATES_ENABLED_HEADER=0
else
  PA_CANDIDATES_ENABLED=true
  PA_CANDIDATES_ENABLED_HEADER=1
fi

PA_CANDIDATES_HEADER_DEFAULT="ICAO,Tail,Operator,Type,ICAO Type,CMPG,,,,Category,photo_link"
PA_CANDIDATES_HEADER="$(GET_PARAM pa PA_COLLECT_CANDIDATES_HEADER || true)"
PA_CANDIDATES_HEADER="${PA_CANDIDATES_HEADER:-${PA_CANDIDATES_HEADER_DEFAULT}}"
PA_CANDIDATES_FILE="$(GET_PARAM pa PA_COLLECT_CANDIDATES_FILE || true)"
PA_CANDIDATES_FILE="${PA_CANDIDATES_FILE:-plane-alert-candidates.txt}"
PA_CANDIDATES_FILE="/usr/share/planefence/persist/${PA_CANDIDATES_FILE##*/}"
PA_CANDIDATES_BASENAME="${PA_CANDIDATES_FILE##*/}"
PA_CANDIDATES_AUTOADD=false
PF_ALERTLIST_RAW="$(GET_PARAM base PF_ALERTLIST || true)"
if [[ -n "${PF_ALERTLIST_RAW:-}" ]]; then
  IFS=',' read -r -a pf_alertlist_items <<< "$PF_ALERTLIST_RAW"
  for pf_item in "${pf_alertlist_items[@]}"; do
    pf_item="${pf_item%$'\r'}"
    pf_item="${pf_item#"${pf_item%%[![:space:]]*}"}"
    pf_item="${pf_item%"${pf_item##*[![:space:]]}"}"
    pf_item="${pf_item#\"}"
    pf_item="${pf_item%\"}"
    [[ -z "$pf_item" ]] && continue
    [[ "$pf_item" == *"://"* ]] && continue
    pf_base="${pf_item##*/}"
    if [[ "$pf_base" == "$PA_CANDIDATES_BASENAME" ]]; then
      PA_CANDIDATES_AUTOADD=true
      break
    fi
  done
fi

stream_pa_candidates_ndjson() {
  local file="${PA_CANDIDATES_FILE}"
  local fallback_header="${PA_CANDIDATES_HEADER}"
  local header_line=""
  local line trimmed

  printf '{"__globals":{"pa:candidates:enabled":%s,"pa:candidates:autoadd":%s}}\n' "${PA_CANDIDATES_ENABLED}" "${PA_CANDIDATES_AUTOADD}"
  printf '{"__columns":["photo_link","icao","tail","operator","type"]}\n'

  [[ "${PA_CANDIDATES_ENABLED}" == "true" ]] || return 0
  [[ -r "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line%$'\r'}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    [[ "${trimmed:0:1}" == "#" ]] && continue
    header_line="$trimmed"
    break
  done < "$file"

  [[ -n "$header_line" ]] || header_line="$fallback_header"

  awk -v hdr="$header_line" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    function unquote(s) {
      s = trim(s)
      if (s ~ /^".*"$/) {
        s = substr(s, 2, length(s) - 2)
      }
      gsub(/""/, "\"", s)
      return s
    }
    function canon(s) {
      s = tolower(unquote(s))
      gsub(/[[:space:]]+/, " ", s)
      return s
    }
    function jesc(s) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s)
      gsub(/\r/, "\\r", s)
      gsub(/\n/, "\\n", s)
      return s
    }
    function csv_split(s, out,    i, ch, nextch, inq, n, field) {
      inq = 0
      n = 0
      field = ""
      delete out
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (inq) {
          if (ch == "\"") {
            nextch = substr(s, i + 1, 1)
            if (nextch == "\"") {
              field = field "\""
              i++
            } else {
              inq = 0
            }
          } else {
            field = field ch
          }
        } else {
          if (ch == "\"") {
            inq = 1
          } else if (ch == ",") {
            out[++n] = field
            field = ""
          } else {
            field = field ch
          }
        }
      }
      out[++n] = field
      return n
    }
    BEGIN {
      header_count = csv_split(hdr, header_cols)
      for (i = 1; i <= header_count; i++) {
        name = canon(header_cols[i])
        if (name == "icao") idx_icao = i
        else if (name == "tail") idx_tail = i
        else if (name == "operator") idx_operator = i
        else if (name == "type") idx_type = i
        else if (name == "imagelink" || name == "image_link" || name == "imagelink1") idx_image_link = i
        else if (name == "photo_link") idx_photo = i
      }
      if (!idx_icao) idx_icao = 1
      if (!idx_tail) idx_tail = 2
      if (!idx_operator) idx_operator = 3
      if (!idx_type) idx_type = 4
      if (!idx_image_link && !idx_photo) idx_photo = 11
      consumed_header = 0
    }
    {
      raw = $0
      gsub(/\r$/, "", raw)
      line = trim(raw)
      if (line == "" || line ~ /^#/) next
      if (!consumed_header) {
        consumed_header = 1
        next
      }
      n = csv_split(raw, row)
      icao = trim(unquote((idx_icao <= n ? row[idx_icao] : "")))
      if (icao == "" || toupper(icao) == "ICAO") next
      tail = trim(unquote((idx_tail <= n ? row[idx_tail] : "")))
      oper = trim(unquote((idx_operator <= n ? row[idx_operator] : "")))
      typ = trim(unquote((idx_type <= n ? row[idx_type] : "")))
      if (idx_image_link) {
        photo = trim(unquote((idx_image_link <= n ? row[idx_image_link] : "")))
      } else {
        photo = trim(unquote((idx_photo <= n ? row[idx_photo] : "")))
      }
      printf("{\"photo_link\":\"%s\",\"icao\":\"%s\",\"tail\":\"%s\",\"operator\":\"%s\",\"type\":\"%s\"}\n", jesc(photo), jesc(icao), jesc(tail), jesc(oper), jesc(typ))
    }
  ' "$file"
}

plane_alert_hist_days() {
  local val
  val="$(GET_PARAM plane-alert HISTTIME)"
  val="${val//[[:space:]]/}"
  [[ "$val" =~ ^[0-9]+$ ]] || val=14
  printf '%s' "${val}"
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

extract_station_version() {
  local file="${1:-}" val
  [[ -n "$file" ]] || { printf ''; return; }
  val="$(jq -r '
    if (type=="array") and (.[0]|type=="object") and (.[0]|has("index")|not) then
      (.[0]["station:version"] // .[0]["station.version"] // "")
    else "" end
  ' "$file" 2>/dev/null || true)"
  [[ "$val" == "null" ]] && val=""
  printf '%s' "$val"
 }

build_plane_alert_all_json() {
  local mode="${1:-plane-alert}" hist_days files=() tmp MAX_ROWS=500
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
  local TODAY_GLOBALS="{}"
  TODAY_LASTUPDATE=$(jq -r '
    if (.[0]|type)=="object" and ((.[0]|has("index"))|not) then
      (.[0].LASTUPDATE // "")
    else "" end
  ' "${files[0]}" 2>/dev/null || true)
  [[ "$TODAY_LASTUPDATE" == "null" ]] && TODAY_LASTUPDATE=""
  TODAY_GLOBALS=$(jq -c '
    if (.[0]|type)=="object" and ((.[0]|has("index"))|not) then
      .[0]
    else {} end
  ' "${files[0]}" 2>/dev/null || true)
  [[ -z "$TODAY_GLOBALS" || "$TODAY_GLOBALS" == "null" ]] && TODAY_GLOBALS="{}"

  tmp="$(mktemp)" || return 1
  if jq -s --arg today_lastupdate "$TODAY_LASTUPDATE" --argjson today_globals "$TODAY_GLOBALS" '
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
      {globals:null, rows:[]};
      (split_parts($f)) as $chunk
      | .globals = (if ($chunk.globals|type)=="object" and ($chunk.globals|length)>0 then $chunk.globals else .globals end)
      | .rows = (if ($chunk.rows|type)=="array" then (.rows + $chunk.rows) else .rows end)
    )
    | .globals = (if (.globals|type)=="object" then .globals else {} end)
      | .globals["station:motd"] = (
          if ($today_globals|has("station:motd")) then $today_globals["station:motd"]
          elif ($today_globals|has("station.motd")) then $today_globals["station.motd"]
          else .globals["station:motd"] end
        )
      | .globals["station.motd"] = (
          if ($today_globals|has("station.motd")) then $today_globals["station.motd"]
          elif ($today_globals|has("station:motd")) then $today_globals["station:motd"]
          else .globals["station.motd"] end
        )
    | .rows = (.rows[0:'"$MAX_ROWS"'])                    # keep newest-first subset
    | .rows = (.rows | reverse)                             # oldest-first for reindex
    | .rows = [ range(0; (.rows|length)) as $i | (.rows[$i] // {}) + {index:$i} ]
    | .rows = (.rows | reverse)                             # emit newest-first
    | .globals.maxindex = ((.rows|length) - 1)
    | .globals.totallines = (
      if ($today_globals|has("totallines")) then $today_globals.totallines
      elif (.globals|has("totallines")) then .globals.totallines
      else (.rows|length) end)
    | .globals.LASTUPDATE = (
      if ($today_lastupdate|length) > 0 then $today_lastupdate
      elif ($today_globals|has("LASTUPDATE")) then $today_globals.LASTUPDATE
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
printf 'X-Planefence-PlaneAlert-Enabled: %s\r\n' "${PLANEALERT_ENABLED_HEADER}"
printf 'X-Planefence-Planefence-Enabled: %s\r\n' "${PLANEFENCE_ENABLED_HEADER}"
printf 'X-Planefence-Pa-Candidates-Enabled: %s\r\n' "${PA_CANDIDATES_ENABLED_HEADER}"
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
        [[ "$val" == "pa-candidates" ]] && FILTER_MODE="pa-candidates"
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

if [[ "$FILTER_MODE" == "pa-candidates" ]]; then
  stream_pa_candidates_ndjson
  exit 0
fi

if [[ "$REQUESTED_DATE" == "all" ]]; then
  TMP_ALL_FILE="$(build_plane_alert_all_json "$FILTER_MODE" || true)"
  JSONFILE="$TMP_ALL_FILE"
else
  JSONFILE="$(choose_json "$FILTER_MODE" "$REQUESTED_DATE" || true)"
fi

TODAYS_VERSION_SOURCE=""
TODAYS_VERSION=""
TODAYS_VERSION_SOURCE="$(choose_json_for_date "$FILTER_MODE" "$utc_today" || true)"
if [[ -n "$TODAYS_VERSION_SOURCE" ]]; then
  TODAYS_VERSION="$(extract_station_version "$TODAYS_VERSION_SOURCE" || true)"
fi
if [[ -z "$TODAYS_VERSION" && -n "$JSONFILE" ]]; then
  TODAYS_VERSION="$(extract_station_version "$JSONFILE" || true)"
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
if ! jq -r --arg todays_version "${TODAYS_VERSION:-}" --argjson planealert_enabled "${PLANEALERT_ENABLED}" --argjson pa_candidates_enabled "${PA_CANDIDATES_ENABLED}" --argjson pa_candidates_autoadd "${PA_CANDIDATES_AUTOADD}" '
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
    | ( if $has_globals then .[0] else {} end ) as $raw_globals
    | ( if ($todays_version|length)>0
      then $raw_globals + {"station:version":$todays_version, "station.version":$todays_version}
      else $raw_globals end ) as $globals0
    | ($globals0 + {"planealert:enabled":$planealert_enabled, "planealert.enabled":$planealert_enabled, "pa:candidates:enabled":$pa_candidates_enabled, "pa.candidates.enabled":$pa_candidates_enabled, "pa:candidates:autoadd":$pa_candidates_autoadd, "pa.candidates.autoadd":$pa_candidates_autoadd}) as $globals
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
