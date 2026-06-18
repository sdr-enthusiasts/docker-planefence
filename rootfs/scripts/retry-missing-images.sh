#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2154

set -euo pipefail

# Prefer explicit request path first, then current repository runtime path.
if [[ -f /scripts/pf-common.sh ]]; then
  source /scripts/pf-common.sh
else
  source /scripts/pf-common
fi

source /usr/share/planefence/planefence.conf

TODAY="${TODAY:-$(date +%y%m%d)}"
PA_FILE="$(GET_PARAM pa PLANEFILE)"
PA_FILE="${PA_FILE:-/usr/share/planefence/persist/.internal/plane-alert-db.txt}"

GET_PA_IMAGE_LINK() {
  # Usage: GET_PA_IMAGE_LINK ICAO
  # Returns first image-looking HTTP(S) URL in the matching PA_FILE row.
  local lookup="${1^^}" pa_link

  [[ -n "$lookup" && -f "$PA_FILE" ]] || return 1

  pa_link="$(awk -F',' -v key="$lookup" '
    function trimq(s) {
      gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", s)
      return s
    }
    BEGIN { IGNORECASE=1 }
    NR > 1 {
      row_icao = trimq($1)
      if (toupper(row_icao) != toupper(key)) next
      for (i = 2; i <= NF; i++) {
        v = trimq($i)
        if (v !~ /^https?:\/\//) continue
        base = tolower(v)
        sub(/[?#].*$/, "", base)
        if (match(base, /\.([a-z0-9]{2,8})$/, m)) {
          ext = m[1]
          if (ext ~ /^(jpg|jpeg|png|gif|bmp|webp|tiff?|heic|heif|avif|svg|ico)$/) {
            print v
            exit
          }
        }
      }
      exit
    }
  ' "$PA_FILE" 2>/dev/null)"

  [[ -n "$pa_link" ]] || return 1
  printf '%s\n' "$pa_link"
}

GET_PS_PHOTO() {
  # Usage: GET_PS_PHOTO ICAO [image|link|thumblink]
  local icao="$1" returntype json link thumb pa_link CACHETIME
  local got_photo=false prefer_pa_db=false na_fresh=false

  returntype="${2:-link}"
  returntype="${returntype,,}"

  case "$returntype" in
    image|link|thumblink) ;;
    *) return 1 ;;
  esac

  chk_enabled "$SHOWIMAGES" || return 0

  CACHETIME=$((3 * 24 * 3600))

  local dir="/usr/share/planefence/persist/planepix/cache"
  local jpg="$dir/$icao.jpg"
  local lnk="$dir/$icao.link"
  local tlnk="$dir/$icao.thumb.link"
  local na="$dir/$icao.notavailable"

  case "$returntype" in
    image)     if [[ -f "$jpg"  ]] && (( $(date +%s) - $(stat -c %Y -- "$jpg") < CACHETIME )); then printf '%s\n' "$jpg";  return 0; fi ;;
    link)      if [[ -f "$lnk"  ]] && (( $(date +%s) - $(stat -c %Y -- "$lnk") < CACHETIME )); then cat "$lnk"; return 0; fi ;;
    thumblink) if [[ -f "$tlnk" ]] && (( $(date +%s) - $(stat -c %Y -- "$tlnk") < CACHETIME )); then cat "$tlnk"; return 0; fi ;;
  esac

  if [[ -f "$na" ]] && (( $(date +%s) - $(stat -c %Y -- "$na") < CACHETIME )); then
    na_fresh=true
  fi

  if chk_enabled "$PREFER_PA_DB_FOR_PHOTOS"; then
    prefer_pa_db=true
  fi

  if ! $prefer_pa_db; then
    if ! $na_fresh; then
      if json="$(planespotters_fetch_json "$icao" 30)" && \
         link="$(jq -r 'try .photos[].link | select(. != null) | .' <<<"$json" | head -n1)" && \
         thumb="$(jq -r 'try .photos[].thumbnail_large.src | select(. != null) | .' <<<"$json" | head -n1)" && \
         [[ -n "$link" && -n "$thumb" ]]; then
        got_photo=true
      fi
    fi
    if ! $got_photo && pa_link="$(GET_PA_IMAGE_LINK "$icao")"; then
      link="$pa_link"
      thumb="$pa_link"
      got_photo=true
    fi
  else
    if pa_link="$(GET_PA_IMAGE_LINK "$icao")"; then
      link="$pa_link"
      thumb="$pa_link"
      got_photo=true
    elif ! $na_fresh && \
         json="$(planespotters_fetch_json "$icao" 30)" && \
         link="$(jq -r 'try .photos[].link | select(. != null) | .' <<<"$json" | head -n1)" && \
         thumb="$(jq -r 'try .photos[].thumbnail_large.src | select(. != null) | .' <<<"$json" | head -n1)" && \
         [[ -n "$link" && -n "$thumb" ]]; then
      got_photo=true
    fi
  fi

  if $got_photo; then
    curl -m 30 -fsSL --fail "$thumb" > "$jpg" 2>/dev/null || :
    printf '%s\n' "$link" > "$lnk"
    printf '%s\n' "$thumb" > "$tlnk"

    case "$returntype" in
      image)     printf '%s\n' "$jpg" ;;
      link)      printf '%s\n' "$link" ;;
      thumblink) printf '%s\n' "$thumb" ;;
    esac
  else
    rm -f "$dir/$icao".* 2>/dev/null || :
    touch "$na"
  fi

  find "$dir" -type f '(' -name '*.jpg' -o -name '*.link' -o -name '*.thumb.link' -o -name '*.notavailable' ')' \
    -mmin +"$(( CACHETIME / 60 ))" -delete 2>/dev/null || :
}

is_missing_image() {
  local prefix="$1"
  [[ -z "${prefix:image:thumblink}" && -z "${prefix:image:link}" && -z "${prefix:image:file}" ]]
}

has_valid_image_ext() {
  # Returns 0 (true) if the URL ends with a known image extension (case-insensitive).
  local url="${1,,}"    # lowercase
  url="${url%%[?#]*}"   # strip query string and fragment
  [[ "$url" =~ \.(jpg|jpeg|png|gif|bmp|webp|tiff?|heic|heif|avif|svg|ico)$ ]]
}

process_pf() {
  local idx icao thumblink link file result lastseen existing_link cache_dir
  cache_dir="/usr/share/planefence/persist/planepix/cache"

  for (( idx=0; idx<=records[maxindex]; idx++ )); do
    [[ -n "${records["$idx":icao]:-}" ]] || continue
    lastseen="${records["$idx":time:lastseen]:-0}"
    [[ "$lastseen" =~ ^[0-9]+$ ]] || lastseen=0
    (( lastseen >= TODAY_EPOCH )) || continue
    icao="${records["$idx":icao]}"

    existing_link="${records["$idx":image:link]:-}"
    if [[ -n "$existing_link" ]] && ! has_valid_image_ext "$existing_link"; then
      rm -f "$cache_dir/$icao.jpg" "$cache_dir/$icao.link" "$cache_dir/$icao.thumb.link" 2>/dev/null || :
      records["$idx":image:link]=""
      records["$idx":image:thumblink]=""
      records["$idx":image:file]=""
      records["$idx":checked:image]=""
      printf 'PF,%s,%s,cleared-bad-link,%s,\n' "$idx" "$icao" "$existing_link"
    fi

    if [[ -z "${records["$idx":image:thumblink]:-}" && -z "${records["$idx":image:link]:-}" && -z "${records["$idx":image:file]:-}" ]]; then
      thumblink="$(GET_PS_PHOTO "$icao" thumblink || true)"
      link="$(GET_PS_PHOTO "$icao" link || true)"
      file="$(GET_PS_PHOTO "$icao" image || true)"

      if [[ -n "$thumblink" || -n "$link" || -n "$file" ]]; then
        records["$idx":image:thumblink]="$thumblink"
        records["$idx":image:link]="$link"
        records["$idx":image:file]="$file"
        records["$idx":checked:image]=true
        records[HASIMAGES]=true
        PF_NEW_IMAGES=$((PF_NEW_IMAGES + 1))
        result="retrieved"
      else
        result="still-missing"
      fi

      printf 'PF,%s,%s,%s,%s,%s\n' "$idx" "$icao" "$result" "${link:-}" "${thumblink:-}"
    fi
  done
}

process_pa() {
  local idx icao thumblink link file result lastseen existing_link cache_dir
  cache_dir="/usr/share/planefence/persist/planepix/cache"

  for (( idx=0; idx<=pa_records[maxindex]; idx++ )); do
    [[ -n "${pa_records["$idx":icao]:-}" ]] || continue
    lastseen="${pa_records["$idx":time:lastseen]:-0}"
    [[ "$lastseen" =~ ^[0-9]+$ ]] || lastseen=0
    (( lastseen >= TODAY_EPOCH )) || continue
    icao="${pa_records["$idx":icao]}"

    existing_link="${pa_records["$idx":image:link]:-}"
    if [[ -n "$existing_link" ]] && ! has_valid_image_ext "$existing_link"; then
      rm -f "$cache_dir/$icao.jpg" "$cache_dir/$icao.link" "$cache_dir/$icao.thumb.link" 2>/dev/null || :
      pa_records["$idx":image:link]=""
      pa_records["$idx":image:thumblink]=""
      pa_records["$idx":image:file]=""
      pa_records["$idx":checked:image]=""
      printf 'PA,%s,%s,cleared-bad-link,%s,\n' "$idx" "$icao" "$existing_link"
    fi

    if [[ -z "${pa_records["$idx":image:thumblink]:-}" && -z "${pa_records["$idx":image:link]:-}" && -z "${pa_records["$idx":image:file]:-}" ]]; then
      thumblink="$(GET_PS_PHOTO "$icao" thumblink || true)"
      link="$(GET_PS_PHOTO "$icao" link || true)"
      file="$(GET_PS_PHOTO "$icao" image || true)"

      if [[ -n "$thumblink" || -n "$link" || -n "$file" ]]; then
        pa_records["$idx":image:thumblink]="$thumblink"
        pa_records["$idx":image:link]="$link"
        pa_records["$idx":image:file]="$file"
        pa_records["$idx":checked:image]=true
        pa_records[HASIMAGES]=true
        PA_NEW_IMAGES=$((PA_NEW_IMAGES + 1))
        records[HASIMAGES]=true
        result="retrieved"
      else
        result="still-missing"
      fi

      printf 'PA,%s,%s,%s,%s,%s\n' "$idx" "$icao" "$result" "${link:-}" "${thumblink:-}"
    fi
  done
}

main() {
  PF_NEW_IMAGES=0
  PA_NEW_IMAGES=0
  TODAY_EPOCH="$(date -d "$(date +%F) 00:00:00" +%s)"

  printf 'MODE,INDEX,ICAO,RESULT,LINK,THUMBLINK\n'

  READ_RECORDS ignore-lock

  process_pf
  process_pa

  if (( PF_NEW_IMAGES + PA_NEW_IMAGES > 0 )); then
    records[HASIMAGES]=true
    WRITE_RECORDS ""
  fi

  printf 'SUMMARY,pf_new_images=%d,pa_new_images=%d\n' "$PF_NEW_IMAGES" "$PA_NEW_IMAGES"
}

main "$@"
