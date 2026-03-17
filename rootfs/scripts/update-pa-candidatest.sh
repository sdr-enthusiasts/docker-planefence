#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC1091,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2020-2026 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence4docker/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
#
source /scripts/pf-common

DEBUG="${DEBUG:-false}"

file="${1:-plane-alert-candidates.txt}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

log_print INFO "Adding ImageLinks to $file. This should be a one-time process that can take a few minutes"

get_imagelink() {
  local icao="$1" json image_link
  json="$(curl -m 20 -fsSL --fail "https://api.planespotters.net/pub/photos/hex/$icao" 2>/dev/null || true)"
  image_link="$(jq -r 'try .photos[].thumbnail_large.src | select(. != null) | .' <<<"$json" 2>/dev/null | head -n1 || true)"
  printf '%s' "$image_link"
}

IFS= read -r header < "$file"

imgcol="$(
  awk -F',' '
    NR==1{for(i=1;i<=NF;i++) if($i=="ImageLink"){print i; exit}}
  ' <<<"$header"
)"

if [[ -z "${imgcol:-}" ]]; then
  header_out="${header},,,,ImageLink"
  imgcol="$(awk -F',' '{print NF}' <<<"$header_out")"
  log_print DEBUG "Header: added ',,,,ImageLink' (ImageLink column=$imgcol)"
else
  header_out="$header"
  log_print DEBUG "Header: ImageLink already present (column=$imgcol)"
fi

printf '%s\n' "$header_out" > "$tmp"

n=1
updated=0
skipped=0
passed=0

tail -n +2 "$file" | while IFS= read -r line; do
  n=$((n+1))

  if [[ "$line" == \#* ]]; then
    passed=$((passed+1))
    printf '%s\n' "$line" >> "$tmp"
    continue
  fi

  IFS=',' read -r -a f <<<"$line"
  while ((${#f[@]} < imgcol)); do f+=(""); done

  icao="${f[0]#\#}"
  tailno="${f[1]:-}"
  oper="${f[2]:-}"

  if [[ -n "${f[imgcol-1]}" ]]; then
    skipped=$((skipped+1))
    log_print DEBUG "Line $n: skip (already has ImageLink) ICAO=$icao Tail=$tailno Operator=$oper"
  else
    link="$(get_imagelink "$icao")"
    f[imgcol-1]="$link"
    updated=$((updated+1))
    log_print INFO "Line $n: set ImageLink ICAO=$icao Tail=$tailno Operator=$oper Link=${link:-<empty>}"
  fi

  (IFS=','; printf '%s\n' "${f[*]}") >> "$tmp"
done

mv -f "$tmp" "$file"
trap - EXIT

log_print INFO "Done. Updated=$updated Skipped=$skipped PassedThrough=$passed Output=$file"
