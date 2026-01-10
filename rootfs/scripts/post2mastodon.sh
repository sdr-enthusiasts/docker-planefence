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

source /scripts/pf-common
DEBUG=true

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, but post2bsky is called from another script, and we don't want to polute the returns with info text

shopt -s extglob

if (( ${#@} < 1 )); then
  log_print ERR "Usage: $0 [pf|pa] <text> [image1] [image2] ..."
  exit 1
fi

# Extract info from the command line arguments
args=("$@")
mode="${args[0]}"
TEXT="${args[1]}"
IMAGES=("${args[2]}" "${args[3]}" "${args[4]}" "${args[5]}") # up to 4 images

if [[ -z "$TEXT" ]]; then
    log_print ERR "A post text must be included in the request to $0"
    exit 1
fi

if [[ ${mode,,} == "pf" ]]; then
  source /usr/share/planefence/planefence.conf
elif [[ ${mode,,} == "pa" ]]; then
  source /usr/share/planefence/plane-alert.conf
else
  log_print ERR "First argument must be either 'pf' (PlaneFence) or 'pa' (Plane Alert)"
  log_print ERR "You provided: '${args[*]}'"
  exit 1
fi

if [[ -z "${MASTODON_ACCESS_TOKEN}" ]]; then
    log_print ERR "MASTODON_ACCESS_TOKEN not defined. Cannot send a Mastodon notification"
    exit 1
fi
if [[ -z "${MASTODON_SERVER}" ]]; then
    log_print ERR "MASTODON_SERVER not defined. Cannot send a Mastodon notification"
    exit 1
fi

# Set the default values
MASTODON_POST_VISIBILITY="${MASTODON_POST_VISIBILITY:-unlisted}"
MASTODON_SERVER="https://${MASTODON_SERVER#http?(s)://}"
MASTODON_MAXLENGTH="${MASTODON_MAXLENGTH:-300}"


# truncate the text to the maximum length
TEXT="$(sed -e 's|\\n|\n|g' <<< "$TEXT")"
# test and correct if max toot length is exceeded
toot_length="$(sed 's/http[^ ]*/xxxxxxxxxxxxxxxxxxxxxxxx/g' <<<"${TEXT//$'\n'/ }" | wc -m)"
if (( toot_length >= 500 )); then
   new_length="$(( ${#TEXT} - toot_length + 496 ))"
   TEXT="${TEXT:0:$new_length}..."
   "${s6wrap[@]}" echo "[WARNING] Mastodon Notification Truncated: it was $(( toot_length - 499)) characters too long"
fi

# send pictures to Mastodon
for image in "${IMAGES[@]}"; do
  if [[ -z "$image" ]]; then continue; fi
  if [[ -f "$image" ]]; then
    response="$(curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "${MASTODON_SERVER}/api/v1/media" --form file="@$image")"
    [[ "$(jq '.id' <<< "${response}" | xargs)" != "null" ]] && mast_id="$(jq '.id' <<< "${response}" | xargs)" || mast_id=""
    if [[ -n "${mast_id}" ]]; then media_id+="${media_id:+ }-F media_ids[]=${mast_id}"; fi
    log_print DEBUG "image $image successfully uploaded to Mastodon"
  else
    log_print WARNING "no image available at $image"
  fi
done

# shellcheck disable=SC2086
response="$(curl -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -s "${MASTODON_SERVER}/api/v1/statuses" -X POST ${media_id} -F "status=${TEXT}" -F "language=en" -F "visibility=${MASTODON_POST_VISIBILITY}")"
# check if there was an error
if [[ "$(jq '.error' <<< "${response}"|xargs)" == "null" ]]; then
    jq '.url' <<< "${response}"|xargs
else
    log_print ERR "Mastodon post error: ${response//http/hxttp}"
    exit 1
fi
