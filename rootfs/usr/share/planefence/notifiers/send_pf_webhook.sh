#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2164,SC1090,SC2154,SC1091
#---------------------------------------------------------------------------------------------
# Copyright (C) 2022-2026, Ramon F. Kolb (kx1t) and contributors
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
#---------------------------------------------------------------------------------------------
# This script sends a generic HTTP webhook notification for Planefence
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/planefence.conf

# Resolve webhook-common.sh next to this script, else absolute path
if [[ -f "${BASH_SOURCE[0]%/*}/webhook-common.sh" ]]; then
  # shellcheck source=/usr/share/planefence/notifiers/webhook-common.sh
  source "${BASH_SOURCE[0]%/*}/webhook-common.sh"
else
  source /usr/share/planefence/notifiers/webhook-common.sh
fi

# shellcheck disable=SC2034
DEBUG="${DEBUG:-false}"
WEBHOOK_CURL_CONNECT_TIMEOUT="${WEBHOOK_CURL_CONNECT_TIMEOUT:-10}"
WEBHOOK_CURL_MAX_TIME="${WEBHOOK_CURL_MAX_TIME:-45}"
WEBHOOK_CURL_RETRY="${WEBHOOK_CURL_RETRY:-1}"

declare -a INDEX STALE link delivery_errors

if ! chk_enabled "$WEBHOOK_ENABLED"; then
  log_print DEBUG "HTTP webhook notifications not enabled."
  exit 0
fi

log_print DEBUG "Hello. Starting Planefence HTTP webhook notification run"

if [[ -z "$WEBHOOK_URLS" ]]; then
  log_print ERR "No webhook URLs defined (WEBHOOK_URLS / PF_WEBHOOK_URLS). Aborting."
  exit 1
fi

format="${WEBHOOK_FORMAT,,}"
case "$format" in
  text|json) ;;
  *)
    log_print WARNING "WEBHOOK_FORMAT='$WEBHOOK_FORMAT' is not text|json; using text"
    format=text
    ;;
esac

template_path="/usr/share/planefence/persist/webhook.pf.${format}.template"
headers_path="/usr/share/planefence/persist/webhook.pf.headers"

if [[ ! -f "$template_path" ]]; then
  log_print ERR "Webhook template missing at $template_path. Aborting."
  exit 1
fi
template_clean="$(<"$template_path")"

pf_notification_init_language >/dev/null
pf_notification_log_language_warning

export LC_ALL=C

# Pin records date/file for the entire run to avoid midnight rollover races.
TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/run/planefence}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"

log_print DEBUG "Reading records for HTTP webhook notification"
READ_RECORDS

log_print DEBUG "Getting indices of records ready for webhook notification and stale records"
build_index_and_stale INDEX STALE webhook

if (( ${#INDEX[@]} )); then
  log_print DEBUG "Records ready for webhook notification: ${INDEX[*]}"
else
  log_print DEBUG "No records ready for webhook notification"
fi
if (( ${#STALE[@]} )); then
  log_print DEBUG "Stale records (no notification will be sent): ${STALE[*]}"
else
  log_print DEBUG "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print DEBUG "No records eligible for webhook notification."
  exit 0
fi

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing webhook notification for ${records["$idx":tail]}"

  # --- composed placeholders ---
  aircraft_text="${records["$idx":owner]:-${records["$idx":callsign]}} (${records["$idx":tail]})"
  title_text="$(pf_notification_format_string "notify.text.title.pf" "{aircraft} is at {altitude} above {location}" "aircraft" "$aircraft_text" "altitude" "${records["$idx":altitude:value]} $ALTUNIT" "location" "${records["$idx":nominatim]}")"

  emergency=""
  squawk="${records["$idx":squawk:value]}"
  if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
    emergency="$(pf_notification_format_string "notify.text.emergencyPrefix" "Emergency: Squawk {squawk} - " "squawk" "$squawk")"
  fi

  # Short multi-line human summary (readable for ntfy and similar)
  msg_lines=()
  [[ -n "${records["$idx":icao]}" ]] && msg_lines+=("ICAO: ${records["$idx":icao]}")
  [[ -n "${records["$idx":tail]}" ]] && msg_lines+=("Tail: ${records["$idx":tail]}")
  [[ -n "${records["$idx":callsign]}" ]] && msg_lines+=("Callsign: ${records["$idx":callsign]}")
  [[ -n "${records["$idx":type]}" ]] && msg_lines+=("Type: ${records["$idx":type]}")
  [[ -n "${records["$idx":owner]}" ]] && msg_lines+=("Owner: ${records["$idx":owner]}")
  [[ -n "${records["$idx":route]}" && "${records["$idx":route]}" != "n/a" ]] && msg_lines+=("Route: ${records["$idx":route]}")
  [[ -n "${records["$idx":altitude:value]}" ]] && msg_lines+=("Min Alt: ${records["$idx":altitude:value]} $ALTUNIT")
  if [[ -n "${records["$idx":distance:value]}" ]]; then
    dist_line="Min Dist: ${records["$idx":distance:value]} $DISTUNIT"
    if [[ -n "${records["$idx":angle:value]}" ]]; then
      dist_line+=" (${records["$idx":angle:value]}°${records["$idx":angle:name]:+ ${records["$idx":angle:name]}})"
    fi
    msg_lines+=("$dist_line")
  fi
  [[ -n "${records["$idx":groundspeed:value]}" ]] && msg_lines+=("Gnd Speed: ${records["$idx":groundspeed:value]} $SPEEDUNIT")
  [[ -n "${records["$idx":track:value]}" ]] && msg_lines+=("Track: ${records["$idx":track:value]}°")
  [[ -n "$squawk" ]] && msg_lines+=("Squawk: $squawk")
  [[ -n "${records["$idx":sound:loudness]}" ]] && msg_lines+=("Loudness: ${records["$idx":sound:loudness]} dB")
  message=""
  if ((${#msg_lines[@]})); then
    message="$(printf '%s\n' "${msg_lines[@]}")"
  fi

  links=""
  if [[ -n "${records["$idx":link:map]}" ]]; then
    links="${records["$idx":link:map]}"
  fi
  if [[ -n "${records["$idx":link:fa]}" ]]; then
    links+="${links:+$'\n'}${records["$idx":link:fa]}"
  fi
  if [[ -n "${records["$idx":link:faa]}" ]]; then
    links+="${links:+$'\n'}${records["$idx":link:faa]}"
  fi

  # message may contain newlines; substitute before pair-based expand (pair format is line-oriented).
  # For json body, escape so newlines/quotes become \n / \" inside the template's string literals.
  # Headers stay plain text — flatten CR/LF in all header substitution values (never inject raw multiline message).
  template="$template_clean"
  msg_for_body="$(webhook_pair_value "$message" "$format")"
  msg_repl_body="$(_webhook_escape_repl "$msg_for_body")"
  template="${template//||message||/${msg_repl_body}}"

  # Body pairs use $'\x1e' record separators so multiline values (e.g. links) stay intact.
  composed_pairs=""
  composed_pairs+="title"$'\x1f'"$(webhook_pair_value "$title_text" "$format")"$'\x1e'
  composed_pairs+="links"$'\x1f'"$(webhook_pair_value "$links" "$format")"$'\x1e'
  composed_pairs+="emergency"$'\x1f'"$(webhook_pair_value "$emergency" "$format")"$'\x1e'
  composed_pairs+="alt_unit"$'\x1f'"$(webhook_pair_value "${ALTUNIT}" "$format")"$'\x1e'
  composed_pairs+="dist_unit"$'\x1f'"$(webhook_pair_value "${DISTUNIT}" "$format")"$'\x1e'
  composed_pairs+="speed_unit"$'\x1f'"$(webhook_pair_value "${SPEEDUNIT}" "$format")"$'\x1e'

  # Plain composed pairs for HTTP headers — all values flattened to a single line
  composed_pairs_hdr=""
  composed_pairs_hdr+="title"$'\x1f'"$(webhook_flatten_header_value "$title_text")"$'\x1e'
  composed_pairs_hdr+="message"$'\x1f'"$(webhook_flatten_header_value "$message")"$'\x1e'
  composed_pairs_hdr+="links"$'\x1f'"$(webhook_flatten_header_value "$links")"$'\x1e'
  composed_pairs_hdr+="emergency"$'\x1f'"$(webhook_flatten_header_value "$emergency")"$'\x1e'
  composed_pairs_hdr+="alt_unit"$'\x1f'"$(webhook_flatten_header_value "${ALTUNIT}")"$'\x1e'
  composed_pairs_hdr+="dist_unit"$'\x1f'"$(webhook_flatten_header_value "${DISTUNIT}")"$'\x1e'
  composed_pairs_hdr+="speed_unit"$'\x1f'"$(webhook_flatten_header_value "${SPEEDUNIT}")"$'\x1e'

  # --- record pairs from records keys matching "$idx:"* ---
  # Body record pair values must be single-line (pair format is newline-separated).
  # Header pairs flatten CR/LF instead of skipping.
  record_pairs=""
  record_pairs_hdr=""
  for k in "${!records[@]}"; do
    [[ "$k" == "$idx:"* ]] || continue
    suffix="${k#"$idx":}"
    # Skip noisy internal keys
    [[ "$suffix" == checked:* ]] && continue
    [[ "$suffix" == *:notified ]] && continue
    val="${records[$k]}"
    record_pairs_hdr+="$suffix"$'\x1f'"$(webhook_flatten_header_value "$val")"$'\x1e'
    if [[ "$val" == *$'\n'* || "$val" == *$'\r'* ]]; then
      log_print DEBUG "Skipping multiline record field '$suffix' for webhook body pairs"
      continue
    fi
    record_pairs+="$suffix"$'\x1f'"$(webhook_pair_value "$val" "$format")"$'\x1e'
  done

  body="$(webhook_expand_placeholders "$template" "$record_pairs" "$composed_pairs")"
  if [[ "$format" == "text" ]]; then
    body="$(webhook_collapse_blank_lines "$body")"
  elif [[ "$format" == "json" ]]; then
    if ! jq -e . >/dev/null 2>&1 <<<"$body"; then
      log_print ERR "Webhook body is not valid JSON after template expansion for #$idx ${records["$idx":tail]} (${records["$idx":icao]}); not delivering"
      delivery_errors[idx]=true
      continue
    fi
  fi

  # --- headers: parse, expand (flattened values only), sanitize, default Content-Type ---
  headers_src=""
  if [[ -f "$headers_path" ]]; then
    headers_src="$(webhook_parse_headers_file "$headers_path")"
  fi
  headers_expanded="$(webhook_expand_placeholders "$headers_src" "$record_pairs_hdr" "$composed_pairs_hdr")"
  headers_expanded="$(webhook_sanitize_headers "$headers_expanded")"
  if [[ "$(webhook_headers_have_content_type "$headers_expanded")" != "yes" ]]; then
    headers_expanded+=$'\n'"Content-Type: $(webhook_default_content_type "$format")"
  fi
  mapfile -t curl_header_args < <(webhook_build_curl_header_args "$headers_expanded")

  # --- POST to each URL ---
  readarray -td, webhooks <<<"${WEBHOOK_URLS}"
  any_success=false

  for url in "${webhooks[@]}"; do
    url="${url//$'\n'/}"
    url="${url#"${url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"
    [[ -z "$url" ]] && continue

    url_suffix="${url: -8}"
    tmpbody="$(mktemp)"
    tmperr="$(mktemp)"
    http_code="$(curl -sS -L \
      --connect-timeout "$WEBHOOK_CURL_CONNECT_TIMEOUT" \
      --max-time "$WEBHOOK_CURL_MAX_TIME" \
      --retry "$WEBHOOK_CURL_RETRY" \
      --retry-delay 1 \
      -o "$tmpbody" \
      -w '%{http_code}' \
      "${curl_header_args[@]}" \
      --data-binary "$body" \
      "$url" 2>"$tmperr")"
    curl_rc=$?
    body_snip="$(tr '\n\r' '  ' <"$tmpbody" | head -c 200)"
    err_snip="$(webhook_sanitize_curl_stderr "$(tr '\n\r' '  ' <"$tmperr" | head -c 400)" "$url")"
    err_snip="${err_snip:0:200}"
    rm -f "$tmpbody" "$tmperr"

    if (( curl_rc != 0 )); then
      log_print WARNING "Webhook notification failed at URL ending in ${url_suffix} for #$idx ${records["$idx":tail]} (${records["$idx":icao]}). curl rc=${curl_rc}: ${err_snip}"
      delivery_errors[idx]=true
      continue
    fi
    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      log_print WARNING "Webhook notification failed at URL ending in ${url_suffix} for #$idx ${records["$idx":tail]} (${records["$idx":icao]}). HTTP ${http_code}: ${body_snip}"
      delivery_errors[idx]=true
      continue
    fi
    log_print INFO "Webhook notification successful at URL ending in ${url_suffix} for #$idx ${records["$idx":tail]} (${records["$idx":icao]}) (HTTP ${http_code})"
    any_success=true
  done

  if $any_success; then
    link[idx]=true
  elif [[ -z "${delivery_errors[idx]:-}" ]]; then
    # No URLs after trim — treat as error
    delivery_errors[idx]=true
  fi
done

# Save the records again
log_print DEBUG "Updating records after webhook notifications"

LOCK_RECORDS
READ_RECORDS ignore-lock

if [[ ${#link[@]} -gt 0 || ${#delivery_errors[@]} -gt 0 ]]; then records[HASNOTIFS]=true; fi

for idx in "${STALE[@]}"; do
  records["$idx":webhook:notified]="stale"
done

for idx in "${!delivery_errors[@]}"; do
  records["$idx":webhook:notified]="error"
done

# Successes win over partial delivery_errors (same as Discord)
for idx in "${!link[@]}"; do
  records["$idx":webhook:notified]=true
done

log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "HTTP webhook notifications run completed."