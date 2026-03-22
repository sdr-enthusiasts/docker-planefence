#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091

set -eo pipefail

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Pragma: no-cache\r\n'
printf 'Expires: 0\r\n'
printf 'X-Content-Type-Options: nosniff\r\n'
printf '\r\n'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
insights_script="${script_dir}/insights.sh"

if [[ ! -x "$insights_script" ]]; then
  printf '{"error":"insights endpoint not executable"}\n'
  exit 0
fi

json="$(INSIGHTS_RAW=1 "$insights_script" "$@" 2>/dev/null || true)"
if [[ -z "$json" ]]; then
  printf '{"error":"failed to retrieve insights payload"}\n'
  exit 0
fi

jq '{
  mode,
  generated_utc,
  history_days,
  selected_date,
  limits,
  rollups
}' <<< "$json" 2>/dev/null || printf '{"error":"failed to parse insights payload"}\n'
