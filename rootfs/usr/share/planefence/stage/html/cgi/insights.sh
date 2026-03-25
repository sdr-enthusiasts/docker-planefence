#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091

set -eo pipefail

source /scripts/pf-common

DOCROOT="/usr/share/planefence/html"
RUNROOT="/run/planefence"
utc_today="$(date -u +%y%m%d)"
utc_now_hms="$(date -u +%H:%M:%S)"
utc_cutoff_sec="$((10#${utc_now_hms:0:2}*3600 + 10#${utc_now_hms:3:2}*60 + 10#${utc_now_hms:6:2}))"

EMIT_HEADERS=true
if [[ "${INSIGHTS_RAW:-0}" == "1" ]]; then
  EMIT_HEADERS=false
fi

history_days_for_mode() {
  local mode="$1" section val
  section="pf"
  [[ "$mode" == "plane-alert" ]] && section="plane-alert"
  val="$(GET_PARAM "$section" HISTTIME || true)"
  val="${val//[[:space:]]/}"
  [[ "$val" =~ ^[0-9]+$ ]] || val=14
  (( val < 1 )) && val=14
  (( val > 120 )) && val=120
  printf '%s' "$val"
}

historical_cache_ttl_sec_for_mode() {
  local mode="$1" section val
  local ttl_hours hist_days hist_hours
  section="pf"
  [[ "$mode" == "plane-alert" ]] && section="plane-alert"

  # Historical Insights payloads should remain reusable for at least HISTTIME.
  hist_days="$(GET_PARAM "$section" HISTTIME || true)"
  hist_days="${hist_days//[[:space:]]/}"
  [[ "$hist_days" =~ ^[0-9]+$ ]] || hist_days=14
  (( hist_days < 1 )) && hist_days=14
  (( hist_days > 120 )) && hist_days=120
  hist_hours=$((hist_days * 24))

  val="$(GET_PARAM "$section" INSIGHTS_HISTORICAL_CACHE_TTL_HOURS || true)"
  val="${val//[[:space:]]/}"
  [[ "$val" =~ ^[0-9]+$ ]] || val="$hist_hours"
  (( val < 1 )) && val="$hist_hours"
  (( val > 2880 )) && val=2880

  ttl_hours="$val"
  (( ttl_hours < hist_hours )) && ttl_hours="$hist_hours"
  printf '%s' "$((ttl_hours * 3600))"
}

collapsewithin_sec_for_mode() {
  local mode="$1" section val
  section="pf"
  [[ "$mode" == "plane-alert" ]] && section="plane-alert"
  val="$(GET_PARAM "$section" COLLAPSEWITHIN || true)"
  val="${val//[[:space:]]/}"
  [[ "$val" =~ ^[0-9]+$ ]] || val=300
  (( val < 1 )) && val=300
  (( val > 86399 )) && val=86399
  printf '%s' "$val"
}

date_yyMMdd_to_epoch_utc() {
  local date_yyMMdd="$1"
  [[ "$date_yyMMdd" =~ ^[0-9]{6}$ ]] || { printf '%s' "-1"; return; }
  date -u -d "20${date_yyMMdd:0:2}-${date_yyMMdd:2:2}-${date_yyMMdd:4:2} 00:00:00" +%s 2>/dev/null || printf '%s' "-1"
}

age_days_from_today_utc() {
  local date_yyMMdd="$1" req_epoch today_epoch
  req_epoch="$(date_yyMMdd_to_epoch_utc "$date_yyMMdd")"
  today_epoch="$(date_yyMMdd_to_epoch_utc "$utc_today")"
  if [[ ! "$req_epoch" =~ ^-?[0-9]+$ || ! "$today_epoch" =~ ^-?[0-9]+$ || "$req_epoch" == "-1" || "$today_epoch" == "-1" ]]; then
    printf '%s' "-1"
    return
  fi
  printf '%s' "$(((today_epoch - req_epoch) / 86400))"
}

choose_json_for_date() {
  local mode="$1" req_date="$2" cand
  [[ "$req_date" =~ ^[0-9]{6}$ ]] || { printf ''; return; }

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

FILTER_MODE="planefence"
REQUESTED_DATE=""
REQUESTED_DAYS=""
INSIGHTS_CACHE_SCHEMA_VERSION="3"

parse_params() {
  local method key val pair
  method="${REQUEST_METHOD:-GET}"

  declare -a qs=()
  if [[ "$method" == "GET" && -n "${QUERY_STRING:-}" ]]; then
    IFS='&' read -ra qs <<< "${QUERY_STRING}"
  elif [[ $# -gt 0 ]]; then
    qs=("$@")
  fi

  for pair in "${qs[@]}"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    [[ "$pair" == "$key" ]] && val=""
    case "$key" in
      mode)
        [[ "$val" == "plane-alert" ]] && FILTER_MODE="plane-alert"
        [[ "$val" == "planefence" ]] && FILTER_MODE="planefence"
        ;;
      date)
        if [[ "$val" =~ ^[0-9]{6}$ ]]; then
          REQUESTED_DATE="$val"
        elif [[ "$val" == "today" || "$val" == "all" ]]; then
          REQUESTED_DATE="$val"
        fi
        ;;
      days)
        [[ "$val" =~ ^[0-9]+$ ]] && REQUESTED_DAYS="$val"
        ;;
      raw)
        if [[ "$val" == "1" || "$val" == "true" ]]; then
          EMIT_HEADERS=false
        fi
        ;;
    esac
  done
}

parse_params "$@"

SELECTED_HINT_DATE=""
if [[ "$REQUESTED_DATE" =~ ^[0-9]{6}$ ]]; then
  SELECTED_HINT_DATE="$REQUESTED_DATE"
elif [[ -z "$REQUESTED_DATE" || "$REQUESTED_DATE" == "today" ]]; then
  SELECTED_HINT_DATE="$utc_today"
fi

if [[ "$EMIT_HEADERS" == true ]]; then
  printf 'Content-Type: application/json\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: 0\r\n'
  printf 'X-Content-Type-Options: nosniff\r\n'
  printf '\r\n'
fi

HISTORY_DAYS="$(history_days_for_mode "$FILTER_MODE")"
if [[ -n "$REQUESTED_DAYS" ]]; then
  HISTORY_DAYS="$REQUESTED_DAYS"
  (( HISTORY_DAYS < 1 )) && HISTORY_DAYS=1
  (( HISTORY_DAYS > 120 )) && HISTORY_DAYS=120
fi

cache_ttl_sec="${INSIGHTS_REQUEST_CACHE_TTL_SEC:-600}"
if [[ ! "$cache_ttl_sec" =~ ^[0-9]+$ ]] || (( cache_ttl_sec < 1 )); then
  cache_ttl_sec=600
fi

cache_date_key="${REQUESTED_DATE:-today}"
if [[ -z "$REQUESTED_DATE" || "$REQUESTED_DATE" == "today" ]]; then
  cache_date_key="$utc_today"
fi

cache_key="v${INSIGHTS_CACHE_SCHEMA_VERSION}:${FILTER_MODE}:${cache_date_key}:${HISTORY_DAYS}"
cache_hash="$(printf '%s' "$cache_key" | sha256sum | awk '{print $1}')"
cache_file="/tmp/insights-cache-${cache_hash}.json"
historical_cache_dir="/usr/share/planefence/persist/.internal/insights-cache"
historical_cache_file="${historical_cache_dir}/${cache_hash}.json"
historical_cache_ttl_sec="$(historical_cache_ttl_sec_for_mode "$FILTER_MODE")"
historical_cache_enabled=false
collapsewithin_sec="$(collapsewithin_sec_for_mode "$FILTER_MODE")"

if [[ "$REQUESTED_DATE" =~ ^[0-9]{6}$ ]]; then
  requested_age_days="$(age_days_from_today_utc "$REQUESTED_DATE")"
  if [[ "$requested_age_days" =~ ^-?[0-9]+$ ]]; then
    if (( requested_age_days >= 2 )); then
      historical_cache_enabled=true
    elif (( requested_age_days == 1 && utc_cutoff_sec > collapsewithin_sec )); then
      historical_cache_enabled=true
    fi
  fi
fi

if [[ "$historical_cache_enabled" == true ]]; then
  mkdir -p "$historical_cache_dir" 2>/dev/null || true
  if [[ -s "$historical_cache_file" ]]; then
    now_ts="$(date +%s)"
    cache_ts="$(stat -c %Y "$historical_cache_file" 2>/dev/null || printf '0')"
    if [[ "$cache_ts" =~ ^[0-9]+$ ]] && (( now_ts - cache_ts <= historical_cache_ttl_sec )); then
      printf '%s\n' "$(cat "$historical_cache_file")" > "$cache_file" 2>/dev/null || true
      cat "$historical_cache_file"
      exit 0
    fi
  fi
fi

if [[ -s "$cache_file" ]]; then
  now_ts="$(date +%s)"
  cache_ts="$(stat -c %Y "$cache_file" 2>/dev/null || printf '0')"
  if [[ "$cache_ts" =~ ^[0-9]+$ ]] && (( now_ts - cache_ts <= cache_ttl_sec )); then
    cat "$cache_file"
    exit 0
  fi
fi

series_file="$(mktemp)"
tmp_callsign="$(mktemp)"
tmp_icao="$(mktemp)"
tmp_typecode="$(mktemp)"
tmp_owner="$(mktemp)"
tmp_airline_prefix="$(mktemp)"
trap 'rm -f "$series_file" "$tmp_callsign" "$tmp_icao" "$tmp_typecode" "$tmp_owner" "$tmp_airline_prefix"' EXIT

extract_pattern_signals() {
  local filter_file="" cand
  for cand in \
    "/usr/share/planefence/stage/persist/pa-candidates-filter.txt" \
    "/usr/share/planefence/persist/pa-candidates-filter.txt"; do
    if [[ -r "$cand" ]]; then
      filter_file="$cand"
      break
    fi
  done
  [[ -n "$filter_file" ]] || return 0

  awk -F: \
    -v callsign_file="$tmp_callsign" \
    -v icao_file="$tmp_icao" \
    -v typecode_file="$tmp_typecode" \
    -v owner_file="$tmp_owner" \
  '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function clean_prefix(s){
      s=toupper(trim(s))
      sub(/[\[\]\(\)\*\+\?].*$/, "", s)
      gsub(/[^A-Z0-9-]/, "", s)
      return s
    }
    function clean_owner_kw(s){
      s=tolower(trim(s))
      gsub(/\*/, " ", s)
      gsub(/\?\(/, " ", s)
      gsub(/[\(\)]/, " ", s)
      gsub(/[^a-z0-9 ]/, " ", s)
      gsub(/ +/, " ", s)
      s=trim(s)
      return s
    }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    /^CALLSIGN:/ {
      pat=$2
      if (substr(pat,1,1)=="!") next
      pref=clean_prefix(pat)
      if (length(pref)>=2) print pref >> callsign_file
      own=clean_owner_kw($3)
      if (length(own)>=3) print own >> owner_file
      next
    }
    /^ICAO:/ {
      pat=$2
      if (substr(pat,1,1)=="!") next
      pref=clean_prefix(pat)
      if (length(pref)>=2) print pref >> icao_file
      own=clean_owner_kw($3)
      if (length(own)>=3) print own >> owner_file
      next
    }
    /^DATABASE:typecode:/ {
      pref=clean_prefix($3)
      if (length(pref)>=2) print pref >> typecode_file
      next
    }
    /^DATABASE:owner:/ {
      own=clean_owner_kw($3)
      if (length(own)>=3) print own >> owner_file
      next
    }
  ' "$filter_file"
}

extract_pattern_signals

extract_airline_codes() {
  local airline_file="" cand
  for cand in \
    "/usr/share/planefence/airlinecodes.txt" \
    "/usr/share/planefence/stage/airlinecodes.txt"; do
    if [[ -r "$cand" ]]; then
      airline_file="$cand"
      break
    fi
  done
  [[ -n "$airline_file" ]] || return 0

  awk -F, \
    -v prefix_file="$tmp_airline_prefix" \
  '
    function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
    function norm(s){ s=toupper(trim(s)); gsub(/[^A-Z0-9]/, "", s); return s }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    {
      prefix=norm($1)
      if (prefix ~ /^[A-Z0-9]{3}$/) print prefix >> prefix_file
    }
  ' "$airline_file"
}

extract_airline_codes

MIL_CALLSIGN_PREFIXES_JSON="$(jq -Rsc 'split("\n") | map(select(length>0)) | unique' "$tmp_callsign")"
MIL_ICAO_PREFIXES_JSON="$(jq -Rsc 'split("\n") | map(select(length>0)) | unique' "$tmp_icao")"
MIL_TYPE_PREFIXES_JSON="$(jq -Rsc 'split("\n") | map(select(length>0)) | unique' "$tmp_typecode")"
MIL_OWNER_KEYWORDS_JSON="$(jq -Rsc 'split("\n") | map(select(length>0)) | unique' "$tmp_owner")"
AIRLINE_PREFIX_MAP_JSON="$(jq -Rn '[inputs | select(length>0)] | unique | reduce .[] as $p ({}; .[$p] = true)' < "$tmp_airline_prefix")"

for (( day=HISTORY_DAYS-1; day>=0; day-- )); do
  req_date="$(date -u -d "-${day} days" +%y%m%d 2>/dev/null || true)"
  [[ -n "$req_date" ]] || continue
  json_file="$(choose_json_for_date "$FILTER_MODE" "$req_date")"
  [[ -n "$json_file" ]] || continue

  jq -c \
    --arg date "$req_date" \
    --arg selected_hint_date "$SELECTED_HINT_DATE" \
    --arg mode "$FILTER_MODE" \
    --argjson cutoff_sec "$utc_cutoff_sec" \
    --argjson mil_callsign_prefixes "$MIL_CALLSIGN_PREFIXES_JSON" \
    --argjson mil_icao_prefixes "$MIL_ICAO_PREFIXES_JSON" \
    --argjson mil_type_prefixes "$MIL_TYPE_PREFIXES_JSON" \
    --argjson mil_owner_keywords "$MIL_OWNER_KEYWORDS_JSON" \
    --argjson airline_prefix_map "$AIRLINE_PREFIX_MAP_JSON" '
      def clean_rows:
        if (type=="array") and (.[0]|type=="object") and (.[0]|has("index")|not) then .[1:]
        elif type=="array" then .
        else [] end;
      def low($x): (($x // "") | tostring | ascii_downcase);
      def up($x): (($x // "") | tostring | ascii_upcase);
      def norm_up($x): (up($x) | gsub("[^A-Z0-9]"; ""));
      def norm_low($x): (low($x) | gsub("[^a-z0-9]"; ""));
      def safe_txt($x): (($x // "") | tostring | gsub("[\r\n\t]+"; " ") | gsub("^ +| +$"; ""));
      def icao_of($r): norm_up($r.icao // $r.hex_ident // $r.hex // $r.hexid // $r.icao24 // $r["icao:hex"]);
      def cs($r): norm_up($r.callsign);
      def tl($r): norm_up($r.tail);
      def typ($r): norm_up($r.type);
      def own($r): low($r.owner);
      def dbcat($r): low($r["db:category"] // $r["db"]["category"] // "");
      def mil_callsign_prefixes_safe: ($mil_callsign_prefixes | map(select((type=="string") and (length>=3))));
      def mil_type_prefixes_safe: ($mil_type_prefixes | map(select((type=="string") and (length>=3))));
      def mil_owner_keywords_safe: ($mil_owner_keywords | map(select((type=="string") and (length>=5))));
      def text_blob($r):
        [low($r.owner), low($r.callsign), low($r.type), low(($r.icao // $r.hex_ident // $r.hex // $r.hexid // $r.icao24 // $r["icao:hex"])), low($r.route), low($r["db:category"]), low($r["db"]["category"])] | join(" ");
      def starts_any($s; $arr): if ($s|length)==0 then false else any($arr[]?; . as $p | ($s | startswith($p))) end;
      def contains_any($s; $arr): if ($s|length)==0 then false else any($arr[]?; ($s | contains(.))) end;
      def is_private($r): (cs($r) != "" and tl($r) != "" and cs($r) == tl($r));
      def callsign_airline($r): (cs($r) | test("^[A-Z]{2,3}[0-9]{1,4}[A-Z]?$"));
      def airline_prefix_hit($r):
        (cs($r)) as $c
        | if ($c|length) < 3 then false else (($airline_prefix_map[$c[0:3]] // false) == true) end;
      def is_military_by_patterns($r):
        if $mode != "plane-alert" then false
        else
          starts_any(cs($r); mil_callsign_prefixes_safe)
          or starts_any(typ($r); mil_type_prefixes_safe)
          or contains_any(own($r); mil_owner_keywords_safe)
        end;
      def is_military_hard($r):
        (dbcat($r) | test("mil|military|air force|navy|army|marines"; "i"))
        or ((icao_of($r)) | test("^(AE|AF|ADF[89A-F])"));
      def is_military($r):
        is_military_hard($r)
        or is_military_by_patterns($r)
        or ((text_blob($r)) | test("(^|[^a-z])(usaf|usn|usmc|raf|nato|air force|armed forces|defen[cs]e|military|army|navy|marine corps|coast guard|luftwaffe|space force|air corps|air national guard|guardia di finanza)([^a-z]|$)"; "i"))
        ;
      def is_government($r):
        (dbcat($r) | test("gov|government|state"; "i"))
        or ((text_blob($r)) | test("(^|[^a-z])(government|govt|state|royal flight|president|prime minister|ministry|department|police|customs|border patrol|king.?s flight|queen.?s flight)([^a-z]|$)"; "i"));
      def is_airline($r):
        (dbcat($r) | test("airline|commercial|cargo"; "i"))
        or airline_prefix_hit($r)
        or (callsign_airline($r) and (is_private($r) | not))
        or ((own($r)) | test("(^|[^a-z])(airlines?|airways|air line|cargo|express|delta|american|united|southwest|jetblue|alaska|spirit|frontier|porter|lufthansa|air france|klm|emirates|qatar|british airways)([^a-z]|$)"; "i"))
        or ((typ($r) | starts_any(.; ["A3","A2","B7","B73","B74","B75","B76","B77","B78","E17","E19","E75","E90","CRJ","AT7","AT4","DH8"])) and ((low($r.route) | contains("-")) or callsign_airline($r)));
      def is_private_jet($r):
        (dbcat($r) | test("biz|business|corporate|private"; "i"))
        or (typ($r) | starts_any(.; ["C25","C27","C28","C30","C5","C56","C68","C7","CL3","CL6","E35","E45","E50","E55","FA","F2","F9","GL","LJ","H25","PRM","PC24"]))
        or ((own($r)) | test("(^|[^a-z])(netjets|flexjet|vista|wheels up|executive|corporate|business jet|private jet)([^a-z]|$)"; "i"));
      def is_general_aviation($r):
        (dbcat($r) | test("ga|general aviation|private"; "i"))
        or (typ($r) | starts_any(.; ["C1","C2","C3","C4","BE","PA","P28","P32","SR2","DA4","DA6","RV","AT6","UL","GLID"]))
        or (is_private($r));
      def confidence_bucket($r; $cat):
        if $cat == "military" then
          if is_military_hard($r) then "high"
          elif is_military_by_patterns($r) then "medium"
          else "low" end
        elif $cat == "airline" then
          if (dbcat($r) | test("airline|commercial|cargo"; "i")) or airline_prefix_hit($r) then "high"
          elif callsign_airline($r) then "medium"
          else "low" end
        elif $cat == "government" then
          if (dbcat($r) | test("gov|government|state"; "i")) then "high"
          elif ((text_blob($r)) | test("(^|[^a-z])(government|govt|state|royal flight|president|prime minister|ministry|department|police|customs|border patrol)([^a-z]|$)"; "i")) then "medium"
          else "low" end
        elif $cat == "private_jet" then
          if (dbcat($r) | test("biz|business|corporate|private"; "i")) then "high"
          elif (typ($r) | starts_any(.; ["C25","C27","C28","C30","C5","C56","C68","C7","CL3","CL6","E35","E45","E50","E55","FA","F2","F9","GL","LJ","H25","PRM","PC24"])) then "medium"
          else "low" end
        elif $cat == "general_aviation" then
          if (dbcat($r) | test("ga|general aviation"; "i")) then "high"
          elif is_private($r) then "medium"
          else "low" end
        else
          "low"
        end;
      def route_pair($r):
        (($r.route // "") | tostring | ascii_upcase | gsub("[^A-Z0-9\\- ]"; "")) as $rt
        | ($rt | split("-") | map(gsub("^ +| +$"; "") | select(length >= 3))) as $parts
        | if ($parts | length) >= 2 then ($parts[0] + "->" + $parts[-1]) else null end;
      def type_family($r):
        (typ($r)) as $t
        | if ($t | starts_any(.; ["MQ","RQ","UAV","DRON"])) then "uav"
          elif ($t | starts_any(.; ["AH","UH","HH","MH","CH","NH","H47","H60","H53","V22","EC","AS","BK","R44","R66"])) then "rotorcraft"
          elif ($t | starts_any(.; ["AT","DH","SF3","J31","J32","C208","B190","E120","L4","C46"])) then "turboprop"
          elif ($t | starts_any(.; ["PA","C1","C2","C3","C4","P28","P32","SR2","DA4","DA6","BE3","BE2","M20","RV","UL"])) then "piston"
          elif ($t | starts_any(.; ["A","B7","B73","B74","B75","B76","B77","B78","E17","E19","E75","E90","CRJ","C5","C56","C68","C7","CL","E35","E45","E50","E55","FA","F2","F9","GL","LJ","H25","PRM","PC24"])) then "jet"
          else "other" end;
      def category($r):
        if is_military_hard($r) then "military"
        elif is_airline($r) then "airline"
        elif is_military($r) then "military"
        elif is_government($r) then "government"
        elif is_private_jet($r) then "private_jet"
        elif is_general_aviation($r) then "general_aviation"
        else "other" end;
      def parse_hms($s):
        (($s // "") | tostring) as $t
        | if ($t | test("^[0-9]{9,}$"))
          then ((($t | tonumber) % 86400 + 86400) % 86400)
          elif ($t | test("^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$"))
          then (($t[0:2] | tonumber) * 3600 + ($t[3:5] | tonumber) * 60 + (if ($t|length) >= 8 then ($t[6:8] | tonumber) else 0 end))
          else null
          end;
      def row_second_of_day($r):
        (parse_hms($r["time:firstseen"] // $r.time.firstseen)
         // parse_hms($r["time:time_at_mindist"] // $r.time.time_at_mindist)
         // parse_hms($r["time:lastseen"] // $r.time.lastseen));
      def within_cutoff($r):
        ((row_second_of_day($r) // 86400) <= $cutoff_sec);
      def military_role($r):
        (typ($r)) as $t
        | (cs($r)) as $c
        | if starts_any($t; ["KC10","KC135","KC46","KC130","A330M","MRTT","IL78","KC390","K35R"]) or starts_any($c; ["QID","QUID","OILER","OILGATE","TEXACO","EXTENDER","GETFUEL","SHELL","ESSO","EXXON","SHAMU","SPUR"]) then "tanker"
          elif starts_any($t; ["C17","C5","C130","C160","C27","C295","A400","IL76","IL96","AN12","AN22","AN72","Y8","Y20"]) or starts_any($c; ["RCH","REACH","RRR","MMF","NAF","CTM","DUKE","ROMA","PLF","RFR"]) then "transport"
          elif starts_any($t; ["F15","F16","F18","F18S","A10","EUFI","EUF1","MIG","SU","RFAL"]) or starts_any($c; ["IAF","HAF","FAF","GAF","HVK","TUN","RTAF","BAF","AME","UAF"]) then "fighter"
          elif starts_any($t; ["AH","UH","HH","MH","CH","NH","H47","H60","H53","V22","EC25"]) or starts_any($c; ["USCG","NAVY","COAST"]) then "helicopter"
          elif starts_any($t; ["T34","T38","T134","T154","T206","T214","TEX2"]) then "trainer"
          elif starts_any($t; ["P3","P8","E2","E3","E6","E8","R135","RQ4","RQ170","RQ180"]) or starts_any($c; ["NATO","SVF"]) then "patrol"
          elif starts_any($t; ["RQ","MQ","UAV","DRON","Q4"]) then "uav"
          elif starts_any($c; ["TKF","SAM","SPAR","V-","T-","UNIVERSAL","QUEST"]) then "vip"
          else "other_military" end;
      (clean_rows) as $rows
      | reduce $rows[] as $r (
          {
            date:$date,total:0,military:0,government:0,airline:0,private_jet:0,general_aviation:0,other:0,
            total_cutoff:0,military_cutoff:0,government_cutoff:0,airline_cutoff:0,private_jet_cutoff:0,general_aviation_cutoff:0,other_cutoff:0,
            military_types:{tanker:0,transport:0,fighter:0,helicopter:0,trainer:0,patrol:0,vip:0,uav:0,other_military:0},
            military_types_cutoff:{tanker:0,transport:0,fighter:0,helicopter:0,trainer:0,patrol:0,vip:0,uav:0,other_military:0},
            hourly:[range(0;24) | 0],
            hourly_cutoff:[range(0;24) | 0],
            route_pairs:{},
            route_pairs_cutoff:{},
            type_families:{jet:0,turboprop:0,piston:0,rotorcraft:0,uav:0,other:0},
            type_families_cutoff:{jet:0,turboprop:0,piston:0,rotorcraft:0,uav:0,other:0},
            confidence:{high:0,medium:0,low:0},
            confidence_cutoff:{high:0,medium:0,low:0},
            icao_seen:{},
            icao_seen_cutoff:{},
            icao_items:{},
            icao_items_cutoff:{}
          };
          (category($r)) as $cat
          | (within_cutoff($r)) as $in_cutoff
          | (row_second_of_day($r)) as $sec
          | (if $sec == null then null else (($sec / 3600) | floor) end) as $hour
          | (route_pair($r)) as $route_pair
          | (type_family($r)) as $family
          | (confidence_bucket($r; $cat)) as $confidence
          | (icao_of($r)) as $icao
          | (($selected_hint_date == "" or $date == $selected_hint_date)) as $collect_icao_items
          | (if ($collect_icao_items and ($icao | test("^[0-9A-F]{6}$"))) then {
              icao: $icao,
              callsign: safe_txt($r.callsign),
              tail: safe_txt($r.tail),
              operator: safe_txt($r.owner),
              type: safe_txt($r.type),
              category: $cat
            } else null end) as $icao_item
          | (($icao | test("^[0-9A-F]{6}$"))) as $icao_valid
          | .total += 1
          | .[$cat] += 1
          | .type_families[$family] += 1
          | .confidence[$confidence] += 1
          | if $icao_valid then .icao_seen[$icao] = true else . end
          | if $icao_item != null then .icao_items[$icao] = (.icao_items[$icao] // $icao_item) else . end
          | if ($hour != null and $hour >= 0 and $hour < 24) then .hourly[$hour] += 1 else . end
          | if ($route_pair != null and ($route_pair | length) > 0) then .route_pairs[$route_pair] = ((.route_pairs[$route_pair] // 0) + 1) else . end
          | if $in_cutoff then .total_cutoff += 1 | .[($cat + "_cutoff")] += 1 else . end
          | if $in_cutoff then
              .type_families_cutoff[$family] += 1
              | .confidence_cutoff[$confidence] += 1
              | if $icao_valid then .icao_seen_cutoff[$icao] = true else . end
              | if $icao_item != null then .icao_items_cutoff[$icao] = (.icao_items_cutoff[$icao] // $icao_item) else . end
              | if ($hour != null and $hour >= 0 and $hour < 24) then .hourly_cutoff[$hour] += 1 else . end
              | if ($route_pair != null and ($route_pair | length) > 0) then .route_pairs_cutoff[$route_pair] = ((.route_pairs_cutoff[$route_pair] // 0) + 1) else . end
            else . end
          | if $cat == "military" then
              (military_role($r)) as $role
              | .military_types[$role] += 1
              | if $in_cutoff then .military_types_cutoff[$role] += 1 else . end
            else . end
        )
    ' "$json_file" >> "$series_file" 2>/dev/null || true
done

if [[ ! -s "$series_file" ]]; then
  printf '{"error":"no data files found for mode %s in the requested history window"}\n' "$FILTER_MODE"
  exit 0
fi

jq_err_file="$(mktemp)"
trap 'rm -f "$series_file" "$tmp_callsign" "$tmp_icao" "$tmp_typecode" "$tmp_owner" "$tmp_airline_prefix" "$jq_err_file"' EXIT

payload="$(jq -s \
  --arg mode "$FILTER_MODE" \
  --arg req_date "$REQUESTED_DATE" \
  --arg today "$utc_today" \
  --arg now_hms "$utc_now_hms" \
  --argjson cutoff_sec "$utc_cutoff_sec" \
  --argjson hist_days "$HISTORY_DAYS" '
  def sort_by_date: sort_by(.date);
  def tail($n): if ($n <= 0) then [] else (if (length <= $n) then . else .[(length-$n):] end) end;
  def median: (map(select(type=="number")) | sort) as $a | ($a|length) as $n | if $n==0 then null elif ($n % 2)==1 then $a[($n/2|floor)] else (($a[$n/2 - 1] + $a[$n/2]) / 2) end;
  def abs($x): if $x < 0 then -$x else $x end;
  def mad($arr): ($arr | median) as $m | if $m == null then null else ($arr | map(abs(. - $m)) | median) end;
  def robust_z($x; $arr): ($arr | median) as $m | (mad($arr)) as $d | if ($m == null or $d == null or $d == 0) then null else ((($x - $m) / (1.4826 * $d)) * 100 | round / 100) end;
  def pct($x; $b): if ($b == null or $b == 0) then null else ((($x - $b) / $b) * 100) end;
  def round1($v): if $v == null then null else (($v * 10 | round) / 10) end;
  def share($part; $total): if ($total|tonumber) > 0 then ($part / $total) else 0 end;
  def severity($delta_pct; $z): ((if $delta_pct == null then 0 else ($delta_pct | if . < 0 then -. else . end) end)) as $d | ((if $z == null then 0 else ($z | if . < 0 then -. else . end) end)) as $az | if ($d >= 60 or $az >= 3.5) then "exceptional" elif ($d >= 35 or $az >= 2.5) then "high" elif ($d >= 15 or $az >= 1.5) then "elevated" else "normal" end;
  def percentile($arr; $p): ($arr | map(select(type=="number")) | sort) as $a | ($a|length) as $n | if $n == 0 then null else $a[((($n - 1) * $p) | round)] end;
  def sub_keys: ["tanker","transport","fighter","helicopter","trainer","patrol","vip","uav","other_military"];
  def family_keys: ["jet","turboprop","piston","rotorcraft","uav","other"];
  def subtype_sum($arr): reduce sub_keys[] as $k ({tanker:0,transport:0,fighter:0,helicopter:0,trainer:0,patrol:0,vip:0,uav:0,other_military:0}; .[$k] = ($arr | map(.military_types[$k] // 0) | add // 0));
  def subtype_share($obj; $mil_total): if ($mil_total|tonumber) <= 0 then {tanker:0,transport:0,fighter:0,helicopter:0,trainer:0,patrol:0,vip:0,uav:0,other_military:0} else reduce sub_keys[] as $k ({}; .[$k] = round1((($obj[$k] // 0) / $mil_total) * 100)) end;
  def families_zero: {jet:0,turboprop:0,piston:0,rotorcraft:0,uav:0,other:0};
  def confidence_zero: {high:0,medium:0,low:0};
  def arr24_zero: [range(0;24) | 0];
  def cum24($arr): reduce range(0;24) as $i ({sum:0,out:[]}; .sum += ($arr[$i] // 0) | .out += [.sum]) | .out;
  def argmax_index($arr): reduce range(0; ($arr|length)) as $i ({idx:0,val:-1}; if (($arr[$i] // 0) > .val) then {idx:$i,val:($arr[$i] // 0)} else . end) | .idx;
  def merge_maps($rows; $field): reduce $rows[] as $r ({}; reduce (($r[$field] // {}) | to_entries[]) as $e (. ; .[$e.key] = ((.[$e.key] // 0) + ($e.value // 0))));
  def top_entries($obj; $n): ($obj | to_entries | sort_by(-(.value // 0)) | .[:$n]);
  def epoch_for_date($d): ("20" + $d[0:2] + "-" + $d[2:4] + "-" + $d[4:6] + "T00:00:00Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime);
  def week_key($d): (epoch_for_date($d) | strftime("%G-W%V"));
  def month_key($d): (epoch_for_date($d) | strftime("%Y-%m"));
  def rollup_group($groups): $groups | map({key: .[0].key, start_date: .[0].date, end_date: .[-1].date, total: (map(.total)|add), military: (map(.military)|add), government: (map(.government)|add), airline: (map(.airline)|add), private_jet: (map(.private_jet)|add), general_aviation: (map(.general_aviation)|add), other: (map(.other)|add), military_types: subtype_sum(.)});

  def eff_total($r; $selected_is_today): (if $selected_is_today then ($r.total_cutoff // $r.total // 0) else ($r.total // 0) end);
  def eff_military($r; $selected_is_today): (if $selected_is_today then ($r.military_cutoff // $r.military // 0) else ($r.military // 0) end);
  def eff_government($r; $selected_is_today): (if $selected_is_today then ($r.government_cutoff // $r.government // 0) else ($r.government // 0) end);
  def eff_airline($r; $selected_is_today): (if $selected_is_today then ($r.airline_cutoff // $r.airline // 0) else ($r.airline // 0) end);
  def eff_private_jet($r; $selected_is_today): (if $selected_is_today then ($r.private_jet_cutoff // $r.private_jet // 0) else ($r.private_jet // 0) end);
  def eff_general_aviation($r; $selected_is_today): (if $selected_is_today then ($r.general_aviation_cutoff // $r.general_aviation // 0) else ($r.general_aviation // 0) end);
  def eff_other($r; $selected_is_today): (if $selected_is_today then ($r.other_cutoff // $r.other // 0) else ($r.other // 0) end);
  def eff_mil_types($r; $selected_is_today): (if $selected_is_today then ($r.military_types_cutoff // $r.military_types // {tanker:0,transport:0,fighter:0,helicopter:0,trainer:0,patrol:0,vip:0,uav:0,other_military:0}) else ($r.military_types // {tanker:0,transport:0,fighter:0,helicopter:0,trainer:0,patrol:0,vip:0,uav:0,other_military:0}) end);
  def eff_hourly($r; $selected_is_today): (if $selected_is_today then ($r.hourly_cutoff // $r.hourly // arr24_zero) else ($r.hourly // arr24_zero) end);
  def eff_families($r; $selected_is_today): (if $selected_is_today then ($r.type_families_cutoff // $r.type_families // families_zero) else ($r.type_families // families_zero) end);
  def eff_confidence($r; $selected_is_today): (if $selected_is_today then ($r.confidence_cutoff // $r.confidence // confidence_zero) else ($r.confidence // confidence_zero) end);
  def eff_routes($r; $selected_is_today): (if $selected_is_today then ($r.route_pairs_cutoff // $r.route_pairs // {}) else ($r.route_pairs // {}) end);
  def eff_icao_seen($r; $selected_is_today): (if $selected_is_today then ($r.icao_seen_cutoff // $r.icao_seen // {}) else ($r.icao_seen // {}) end);
  def eff_icao_items($r; $selected_is_today): (if $selected_is_today then ($r.icao_items_cutoff // $r.icao_items // {}) else ($r.icao_items // {}) end);

  (sort_by_date) as $series
  | ($series[-1]) as $latest
  | (if ($req_date|length) == 6 and ($series | any(.date == $req_date)) then $req_date elif $req_date == "today" and ($series | any(.date == $today)) then $today else $latest.date end) as $selected_date
  | ($selected_date == $today) as $selected_is_today
  | ($series | map(select(.date == $selected_date)) | .[0]) as $selected
  | ($series | map(select(.date < $selected_date))) as $previous
  | (eff_icao_items($selected; $selected_is_today)) as $selected_icao_map
  | ($previous | reduce .[] as $d ({}; reduce (eff_icao_seen($d; $selected_is_today) | keys[]) as $k (. ; .[$k] = true))) as $previous_icao_set
  | ($selected_icao_map | to_entries | map(select(((.value.icao // "") | length) > 0 and ((($previous_icao_set[.key] // false) | not)))) | map(.value) | sort_by(.icao)) as $new_aircraft_list
  | ($new_aircraft_list | length) as $new_aircraft_count
  | ($previous | map(eff_total(.; $selected_is_today)) | tail(7)) as $prev7_totals
  | ($previous | map(eff_total(.; $selected_is_today)) | tail(28)) as $prev28_totals
  | (epoch_for_date($selected_date) | gmtime | .[6]) as $sel_wday
  | ($previous | map(select((epoch_for_date(.date) | gmtime | .[6]) == $sel_wday))) as $same_wday
  | ($same_wday | map(eff_total(.; $selected_is_today)) | tail(8)) as $weekday_totals
  | ($prev7_totals | median) as $m7
  | ($prev28_totals | median) as $m28
  | ($weekday_totals | median) as $mwd
  | (eff_total($selected; $selected_is_today) | tonumber) as $actual
  | (if $m7 != null then $m7 elif $m28 != null then $m28 elif $mwd != null then $mwd else null end) as $baseline_total
  | ($previous | tail(7)) as $prev7_rows
  | (if ($prev7_rows|length) > 0 then {total: ($prev7_rows | map(eff_total(.; $selected_is_today)) | add), military: ($prev7_rows | map(eff_military(.; $selected_is_today)) | add), government: ($prev7_rows | map(eff_government(.; $selected_is_today)) | add), airline: ($prev7_rows | map(eff_airline(.; $selected_is_today)) | add), private_jet: ($prev7_rows | map(eff_private_jet(.; $selected_is_today)) | add), general_aviation: ($prev7_rows | map(eff_general_aviation(.; $selected_is_today)) | add), other: ($prev7_rows | map(eff_other(.; $selected_is_today)) | add)} else {total:0,military:0,government:0,airline:0,private_jet:0,general_aviation:0,other:0} end) as $prev7_sum
  | (subtype_sum([{"military_types": eff_mil_types($selected; $selected_is_today)}])) as $selected_subtypes
  | (subtype_sum($prev7_rows | map({"military_types": eff_mil_types(.; $selected_is_today)}))) as $prev7_subtypes
  | (eff_hourly($selected; $selected_is_today)) as $selected_hourly
  | (if ($prev7_rows|length) > 0 then [range(0;24) as $h | ([$prev7_rows[] | ((.hourly // arr24_zero)[$h] // 0)] | median // 0)] else $selected_hourly end) as $baseline_hourly_median
  | (if ($prev7_rows|length) > 0 then [range(0;24) as $h | ([$prev7_rows[] | ((.hourly // arr24_zero)[$h] // 0)] | percentile(.; 0.25) // 0)] else $selected_hourly end) as $baseline_hourly_p25
  | (if ($prev7_rows|length) > 0 then [range(0;24) as $h | ([$prev7_rows[] | ((.hourly // arr24_zero)[$h] // 0)] | percentile(.; 0.75) // 0)] else $selected_hourly end) as $baseline_hourly_p75
  | (eff_families($selected; $selected_is_today)) as $selected_families
  | (if ($prev7_rows|length) > 0 then reduce family_keys[] as $k (families_zero; .[$k] = (($prev7_rows | map(eff_families(.; $selected_is_today)[$k] // 0) | add // 0) / ($prev7_rows|length))) else families_zero end) as $baseline_families_avg
  | (eff_confidence($selected; $selected_is_today)) as $selected_confidence
  | (($selected_confidence.high + $selected_confidence.medium + $selected_confidence.low) // 0) as $confidence_total
  | (if $confidence_total > 0 then round1((((($selected_confidence.high // 0) * 1.0) + (($selected_confidence.medium // 0) * 0.6) + (($selected_confidence.low // 0) * 0.25)) * 100) / $confidence_total) else null end) as $confidence_score
  | (merge_maps($prev7_rows; "route_pairs")) as $prev7_route_sum
  | (top_entries(eff_routes($selected; $selected_is_today); 5) | map({route: .key, count: (.value // 0), baseline_daily_avg: (if ($prev7_rows|length) > 0 then round1((($prev7_route_sum[.key] // 0) / ($prev7_rows|length)) ) else 0 end), delta_pct: (if ($prev7_rows|length) > 0 then round1(pct((.value // 0); (($prev7_route_sum[.key] // 0) / ($prev7_rows|length)))) else null end)})) as $route_flow
  | ({
      military: round1((share(eff_military($selected; $selected_is_today); $actual) * 100) - (share($prev7_sum.military; $prev7_sum.total) * 100)),
      government: round1((share(eff_government($selected; $selected_is_today); $actual) * 100) - (share($prev7_sum.government; $prev7_sum.total) * 100)),
      airline: round1((share(eff_airline($selected; $selected_is_today); $actual) * 100) - (share($prev7_sum.airline; $prev7_sum.total) * 100)),
      private_jet: round1((share(eff_private_jet($selected; $selected_is_today); $actual) * 100) - (share($prev7_sum.private_jet; $prev7_sum.total) * 100)),
      general_aviation: round1((share(eff_general_aviation($selected; $selected_is_today); $actual) * 100) - (share($prev7_sum.general_aviation; $prev7_sum.total) * 100)),
      other: round1((share(eff_other($selected; $selected_is_today); $actual) * 100) - (share($prev7_sum.other; $prev7_sum.total) * 100))
    }) as $category_share_shift
  | (($category_share_shift | to_entries | sort_by(((.value // 0) | if . < 0 then -. else . end)) | reverse | .[0])) as $top_share_shift
  | (argmax_index($selected_hourly)) as $peak_hour
  | (($selected_hourly[$peak_hour] // 0)) as $peak_hour_count
  | (($baseline_hourly_median[$peak_hour] // 0)) as $peak_hour_baseline
  | ([
      (if (round1(pct($actual; $baseline_total)) // 0) >= 35 then {id:"total_spike", severity:"high", message:"Daily total is >=35% above baseline."} else empty end),
      (if (round1(share(eff_military($selected; $selected_is_today); $actual) * 100) // 0) >= 45 then {id:"mil_share_high", severity:"elevated", message:"Military share is above 45%."} else empty end),
      (if ($peak_hour_count >= (($peak_hour_baseline * 1.8) + 6)) then {id:"hourly_spike", severity:"elevated", message:"Peak hour traffic is sharply above normal."} else empty end),
      (if (($route_flow[0].delta_pct // 0) >= 120 and ($route_flow[0].count // 0) >= 4) then {id:"route_surge", severity:"elevated", message:"Top route pair surged above its recent average."} else empty end)
    ]) as $alerts
  | (percentile($weekday_totals; 0.25)) as $weekday_p25
  | (percentile($weekday_totals; 0.75)) as $weekday_p75
  | ($series | map(. + { key: week_key(.date) }) | group_by(.key) | rollup_group(.)) as $weekly_rollup
  | ($series | map(. + { key: month_key(.date) }) | group_by(.key) | rollup_group(.)) as $monthly_rollup
  | {
      mode: $mode,
      generated_utc: (now | floor),
      history_days: $hist_days,
      selected_date: $selected_date,
      selected: {
        date: $selected.date,
        total: $actual,
        categories: {military: eff_military($selected; $selected_is_today), government: eff_government($selected; $selected_is_today), airline: eff_airline($selected; $selected_is_today), private_jet: eff_private_jet($selected; $selected_is_today), general_aviation: eff_general_aviation($selected; $selected_is_today), other: eff_other($selected; $selected_is_today)},
        shares: {military: round1(share(eff_military($selected; $selected_is_today); $actual) * 100), government: round1(share(eff_government($selected; $selected_is_today); $actual) * 100), airline: round1(share(eff_airline($selected; $selected_is_today); $actual) * 100), private_jet: round1(share(eff_private_jet($selected; $selected_is_today); $actual) * 100), general_aviation: round1(share(eff_general_aviation($selected; $selected_is_today); $actual) * 100), other: round1(share(eff_other($selected; $selected_is_today); $actual) * 100)},
        military_types: $selected_subtypes,
        military_type_shares: subtype_share($selected_subtypes; (eff_military($selected; $selected_is_today) // 0)),
        hourly: $selected_hourly,
        type_families: $selected_families,
        confidence: $selected_confidence,
        routes_top: $route_flow
      },
      baselines: {
        previous_7d_median_total: $m7,
        previous_28d_median_total: $m28,
        same_weekday_median_total: $mwd,
        same_weekday_p25_total: $weekday_p25,
        same_weekday_p75_total: $weekday_p75,
        previous_7d_count: ($prev7_totals | length),
        previous_28d_count: ($prev28_totals | length),
        same_weekday_count: ($weekday_totals | length),
        baseline_days_used: ($prev7_totals | length),
        selected_is_today_partial: $selected_is_today,
        selected_cutoff_hms_utc: (if $selected_is_today then $now_hms else null end),
        previous_7d_category_shares: {military: round1(share($prev7_sum.military; $prev7_sum.total) * 100), government: round1(share($prev7_sum.government; $prev7_sum.total) * 100), airline: round1(share($prev7_sum.airline; $prev7_sum.total) * 100), private_jet: round1(share($prev7_sum.private_jet; $prev7_sum.total) * 100), general_aviation: round1(share($prev7_sum.general_aviation; $prev7_sum.total) * 100), other: round1(share($prev7_sum.other; $prev7_sum.total) * 100)},
        previous_7d_military_types: $prev7_subtypes,
        previous_7d_military_type_shares: subtype_share($prev7_subtypes; ($prev7_sum.military // 0))
      },
      anomalies: {
        total: {
          actual: $actual,
          baseline: $baseline_total,
          delta_pct: round1(pct($actual; $baseline_total)),
          z_robust: robust_z($actual; ($previous | map(eff_total(.; $selected_is_today)) | tail(28))),
          severity: severity(round1(pct($actual; $baseline_total)); robust_z($actual; ($previous | map(eff_total(.; $selected_is_today)) | tail(28))))
        }
      },
      enhancements: {
        hourly_profile: {
          selected: $selected_hourly,
          baseline_median: $baseline_hourly_median,
          baseline_p25: $baseline_hourly_p25,
          baseline_p75: $baseline_hourly_p75,
          cumulative_selected: cum24($selected_hourly),
          cumulative_baseline_median: cum24($baseline_hourly_median)
        },
        directional_flow: {top_routes: $route_flow},
        family_trends: {
          selected_counts: $selected_families,
          baseline_daily_avg: (reduce family_keys[] as $k ({}; .[$k] = round1($baseline_families_avg[$k])) )
        },
        confidence: {
          counts: $selected_confidence,
          score: $confidence_score,
          band: (if $confidence_score == null then "unknown" elif $confidence_score >= 80 then "high" elif $confidence_score >= 55 then "medium" else "low" end)
        },
        outliers: {
          peak_hour_utc: $peak_hour,
          peak_hour_count: $peak_hour_count,
          peak_hour_baseline_median: $peak_hour_baseline,
          top_category_share_shift: $top_share_shift
        },
        weekday_context: {
          selected: $actual,
          median: $mwd,
          p25: $weekday_p25,
          p75: $weekday_p75,
          delta_pct_vs_weekday_median: round1(pct($actual; $mwd))
        },
        alerts: {
          active: $alerts
        },
        new_aircraft: {
          count: $new_aircraft_count,
          pct_of_daily_total: (if $actual > 0 then round1(($new_aircraft_count * 100) / $actual) else 0 end),
          selected_unique_icao_count: ($selected_icao_map | length),
          previous_unique_icao_count: ($previous_icao_set | length),
          list: $new_aircraft_list
        }
      },
      limits: {daily_count_design_max: 5000, expected_typical_fraction_of_max: 0.25},
      dates_available: ($series | map(.date)),
      series: ($series | map(del(.hourly, .hourly_cutoff, .route_pairs, .route_pairs_cutoff, .type_families, .type_families_cutoff, .confidence, .confidence_cutoff, .icao_seen, .icao_seen_cutoff, .icao_items, .icao_items_cutoff))),
      rollups: {weekly: $weekly_rollup, monthly: $monthly_rollup}
    }
  ' "$series_file" 2>"$jq_err_file" || true)"

if [[ -z "$payload" ]]; then
  jq_err_line="$(head -n 1 "$jq_err_file" 2>/dev/null || true)"
  if [[ -n "$jq_err_line" ]]; then
    jq -cn --arg error "failed to aggregate insights data" --arg detail "$jq_err_line" '{error:$error, detail:$detail}'
  else
    printf '{"error":"failed to aggregate insights data"}\n'
  fi
  exit 0
fi

printf '%s\n' "$payload" > "$cache_file" 2>/dev/null || true
if [[ "$historical_cache_enabled" == true ]]; then
  printf '%s\n' "$payload" > "$historical_cache_file" 2>/dev/null || true
fi
printf '%s\n' "$payload"
