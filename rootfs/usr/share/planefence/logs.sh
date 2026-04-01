#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154,SC2001,SC2034
# -----------------------------------------------------------------------------------
# Copyright 2026 Ramon F. Kolb, kx1t - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
# CGI endpoint for Planefence container logs (PF_WEBLOGS)
# Usage: curl .../cgi/logs.sh

set -eo pipefail

source /scripts/pf-common

get_qs_param() {
  local key="$1"
  local qs="${QUERY_STRING:-}"
  local part
  IFS='&' read -r -a _parts <<< "$qs"
  for part in "${_parts[@]}"; do
    [[ "$part" == "$key="* ]] || continue
    printf '%s' "${part#*=}"
    return 0
  done
  return 1
}

normalize_weblogs_mode() {
  local raw="$1"
  local lc="${raw,,}"
  if chk_disabled "$raw" || [[ "$lc" == "off" || "$lc" == "disabled" || "$lc" == "0" || "$lc" == "no" ]]; then
    printf 'off'
    return
  fi
  if [[ "$lc" == "main" ]]; then
    printf 'main'
    return
  fi
  printf 'config'
}

resolve_config_port() {
  local main_port="$1"
  local cfg_port="$2"
  [[ "$cfg_port" =~ ^[0-9]+$ ]] || cfg_port=9999
  if [[ "$cfg_port" -eq "$main_port" ]]; then
    cfg_port="$((main_port + 1))"
  fi
  printf '%s' "$cfg_port"
}

# Only allow GET
if [[ "$REQUEST_METHOD" != "GET" ]]; then
  echo "Status: 405 Method Not Allowed"
  echo "Content-Type: text/plain"
  echo
  echo "Method Not Allowed"
  exit 0
fi

# Output headers
printf 'Content-Type: text/plain\n\n'

# Default log file location (override if needed)
LOGFILE="/tmp/planefence.log"
PF_WEBLOGS="config"
PF_HTTP_PORT="80"
PF_CONFIG_HTTP_PORT="9999"

# If PF_LOG is set in config, use that
CONFIG="/usr/share/planefence/persist/planefence.config"
if [[ -f "$CONFIG" ]]; then
  set -o allexport
  source /usr/share/planefence/persist/planefence.config
  set +o allexport
  if [[ -n "$PF_LOG" ]]; then
    LOGFILE="$PF_LOG"
  fi
fi

# Only output if PF_WEBLOGS is enabled on this listener
MODE="$(normalize_weblogs_mode "${PF_WEBLOGS:-config}")"
MAIN_PORT="${PF_HTTP_PORT:-80}"
[[ "$MAIN_PORT" =~ ^[0-9]+$ ]] || MAIN_PORT=80
CONFIG_PORT="$(resolve_config_port "$MAIN_PORT" "${PF_CONFIG_HTTP_PORT:-9999}")"
REQ_PORT="${SERVER_PORT:-}"

if [[ "$MODE" == "off" ]]; then
  echo "Log web endpoint is disabled by PF_WEBLOGS"
  exit 0
fi

if [[ "$MODE" == "config" && -n "$REQ_PORT" && "$REQ_PORT" != "$CONFIG_PORT" ]]; then
  echo "Log web endpoint is not available on this listener"
  exit 0
fi

if [[ "$MODE" == "main" && -n "$REQ_PORT" && "$REQ_PORT" != "$MAIN_PORT" ]]; then
  echo "Log web endpoint is not available on this listener"
  exit 0
fi

# Output incremental lines if since=<line_count> is provided, else last 1000 lines.
if [[ ! -f "$LOGFILE" ]]; then
  echo "No log file found at $LOGFILE"
  exit 0
fi

total_lines="$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)"
[[ "$total_lines" =~ ^[0-9]+$ ]] || total_lines=0
echo "X-Log-Total-Lines: ${total_lines}"
echo

since_raw="$(get_qs_param since || true)"
if [[ "$since_raw" =~ ^[0-9]+$ ]] && [[ "$since_raw" -ge 0 ]] && [[ "$since_raw" -lt "$total_lines" ]]; then
  start_line="$((since_raw + 1))"
  sed -n "${start_line},${total_lines}p" "$LOGFILE"
  exit 0
fi

if [[ "$total_lines" -le 1000 ]]; then
  cat "$LOGFILE"
else
  start_line="$((total_lines - 999))"
  sed -n "${start_line},${total_lines}p" "$LOGFILE"
fi