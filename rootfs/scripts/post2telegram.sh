#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------

source /scripts/pf-common
source /usr/share/planefence/persist/planefence.config

# shellcheck disable=SC2034
DEBUG=false

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common


if (( ${#@} < 1 )); then
  log_print INFO "Usage: $0 <PF|PA> <text> [image1] [image2] ..."
  exit 1
fi

# Set the default values
TELEGRAM_API="${TELEGRAM_API:-https://api.telegram.org/bot}"
TELEGRAM_MAX_LENGTH="${TELEGRAM_MAX_LENGTH:-4096}"
if [[ "${1,,}" == "pf" ]]; then
  if [[ -z "${PF_TELEGRAM_CHAT_ID}" ]]; then
    log_print ERR "the PF_TELEGRAM_CHAT_ID environment variable must be set"
    exit 1
  fi
  TELEGRAM_CHAT_ID="${PF_TELEGRAM_CHAT_ID}"
elif [[ "${1,,}" == "pa" ]]; then
  # shellcheck disable=SC2153
  TELEGRAM_CHAT_ID="${PA_TELEGRAM_CHAT_ID}"
  if [[ -z "$TELEGRAM_CHAT_ID" ]]; then
    log_print ERR "the PA_TELEGRAM_CHAT_ID environment variable must be set"
    exit 1
  fi
else
  log_print ERR "you must specify either 'PF' or 'PA' as the first argument to $0"
  log_print ERR "Usage: $0 <PF|PA> <text> [image1] [image2] ..."
  exit 1
fi

# Check if the required variables are set
if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
  log_print ERR "the TELEGRAM_BOT_TOKEN environment variable must be set"
  exit 1
fi
if [[ -z "$TELEGRAM_CHAT_ID" ]]; then
  log_print ERR "the TELEGRAM_CHAT_ID environment variable must be set"
  exit 1
fi

if [[ "${TELEGRAM_CHAT_ID:0:4}" != "-100" ]]; then TELEGRAM_CHAT_ID="-100${TELEGRAM_CHAT_ID}"; fi

# Extract info from the command line arguments
args=("$@")
TEXT="${args[1]}"
IMAGES=("${args[2]}" "${args[3]}" "${args[4]}" "${args[5]}") # up to 4 images

if [[ -z "$TEXT" ]]; then
  log_print ERR "a message text must be included in the request to $0"
  log_print ERR "Usage: $0 <PF|PA> <text> [image1] [image2] ..."
  exit 1
fi

# log_print INFO "DEBUG: Invoking: $0 $1 $TEXT ${IMAGES[*]}"

# Clean up the text
TEXT="${TEXT:0:$TELEGRAM_MAX_LENGTH}"      # limit to max characters
TEXT="${TEXT//[[:cntrl:]]/$'\n'}"            # Replace control characters with newlines

# Send images to Telegram if available
image_count=0
for image in "${IMAGES[@]}"; do
  if [[ -n "$image" ]]; then
    image_count="$((image_count + 1))"  # only count non-empty image paths
  fi
done
image_counter=1
# shellcheck disable=SC2001

# shellcheck disable=SC2034
IFS=" " read -r header CALL TAIL TYPE ROUTE <<< "$(grep -i "^flt:" <<< "$TEXT")"
image_header=""
if [[ -n "$CALL" ]]; then image_header+="Flt ${CALL//#/} - "; fi
if [[ -n "$TAIL" ]]; then image_header+="Tail ${TAIL//#/} - "; fi
if [[ -n "$ICAO" ]]; then image_header+="ICAO ${ICAO//#/} - "; fi
if [[ -n "$ROUTE" && "$ROUTE" != "n/a" ]]; then image_header+="${ROUTE//#/} - "; fi

for image in "${IMAGES[@]}"; do
    # Skip if the image is not a file that exists
    if [[ -z "$image" ]] || [[ ! -f "$image" ]]; then
      continue
    fi
    if (( image_count > 1 )); then
      if ((image_counter == 1 )); then
        image_text="Image $image_counter of $image_count"
      else
        image_text="${image_header}Image $image_counter of $image_count"
      fi
    else
      image_text=""
    fi

    # Send the photo with the message
    if (( image_counter == 1 )); then
      printf -v curlcmd 'curl --max-time 30 -sSL -X POST %q -F %q -F %q -F %q -F %q' \
        "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendPhoto" \
        "chat_id=${TELEGRAM_CHAT_ID}" \
        "photo=@${image}" \
        "caption=${image_text}${image_text:+$'\n'}${TEXT}" \
        "parse_mode=HTML"
      # shellcheck disable=SC2090
      response="$(eval "$curlcmd")"
      message_id="$(jq -r '.result.message_id' <<< "$response" 2>/dev/null)"
    else
      printf -v curlcmd 'curl --max-time 30 -sSL -X POST %q -F %q -F %q -F %q -F %q' \
        "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendPhoto" \
        "chat_id=${TELEGRAM_CHAT_ID}" \
        "photo=@${image}" \
        "caption=${image_text}" \
        "parse_mode=HTML"
      # shellcheck disable=SC2090
      response="$(eval "$curlcmd")"
    fi

    if (( image_counter == 1)); then
      if [[ -z "$message_id" ]] || [[ "$message_id" == "null" ]]; then
        log_print ERR "Error sending photo message to Telegram: (original had http instead of hxttp):
        ${response//http/hxttp}
        Original command posted:
        ${curlcmd//http/hxttp}"
        exit 1
      else
        echo "https://t.me/c/${TELEGRAM_CHAT_ID}/${message_id}" 
        log_print DEBUG "Photo message sent successfully to Telegram (https://t.me/c/${TELEGRAM_CHAT_ID}/${message_id})"
      fi
    fi

    image_counter=$((image_counter + 1))
done

# If no images or image sending failed, send text only
if (( image_count == 0 )); then
    printf -v curlcmd 'curl --max-time 30 -sSL -X POST %q -F %q -F %q -F %q' \
      "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendMessage" \
      "chat_id=${TELEGRAM_CHAT_ID}" \
      "text=${TEXT}" \
      "parse_mode=HTML"
    # shellcheck disable=SC2090
    response="$(eval "$curlcmd")"
    message_id="$(jq -r '.result.message_id' <<< "$response" 2>/dev/null)"
    
    if [[ -z "$message_id" ]] || [[ "$message_id" == "null" ]]; then
      log_print ERR "Error sending text-only message to Telegram: (original had http instead of hxttp):
        ${response//http/hxttp}
        Original command posted:
        ${curlcmd//http/hxttp}"
        exit 1
    else
      echo "https://t.me/c/${TELEGRAM_CHAT_ID//-100/}/${message_id}"
      # log_print INFO "Text message sent successfully to Telegram (https://t.me/c/${TELEGRAM_CHAT_ID}/${message_id})"
    fi
fi
