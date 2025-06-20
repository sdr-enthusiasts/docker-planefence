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

source /scripts/common
source /usr/share/planefence/persist/planefence.config

if (( ${#@} < 1 )); then
  "${s6wrap[@]}" echo "Usage: $0 <text> [image1] [image2] ..."
  exit 1
fi

# Set the default values
TELEGRAM_API="${TELEGRAM_API:-https://api.telegram.org/bot}"
TELEGRAM_MAX_LENGTH="${TELEGRAM_MAX_LENGTH:-4096}"

# Check if the required variables are set
if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
  "${s6wrap[@]}" echo "Fatal: the TELEGRAM_BOT_TOKEN environment variable must be set"
  exit 1
fi
if [[ -z "$TELEGRAM_CHAT_ID" ]]; then
  "${s6wrap[@]}" echo "Fatal: the TELEGRAM_CHAT_ID environment variable must be set"
  exit 1
fi

if [[ "${TELEGRAM_CHAT_ID:0:4}" != "-100" ]]; then TELEGRAM_CHAT_ID="-100${TELEGRAM_CHAT_ID}"; fi

# Extract info from the command line arguments
args=("$@")
TEXT="${args[0]}"
IMAGES=("${args[1]}" "${args[2]}" "${args[3]}" "${args[4]}") # up to 4 images

if [[ -z "$TEXT" ]]; then
  "${s6wrap[@]}" echo "Fatal: a message text must be included in the request to $0"
  exit 1
fi

# Clean up the text
TEXT="${TEXT:0:$TELEGRAM_MAX_LENGTH}"      # limit to max characters
TEXT="${TEXT//[[:cntrl:]]/\n}"            # Replace control characters with newlines

# Send images to Telegram if available
has_images=false
for image in "${IMAGES[@]}"; do
    # Skip if the image is not a file that exists
    if [[ -z "$image" ]] || [[ ! -f "$image" ]]; then
      continue
    fi
    
    has_images=true
    
    # Send the photo with the message
    response="$(curl -s -X POST "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendPhoto" \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "photo=@${image}" \
        -F "caption=${TEXT}" \
        -F "parse_mode=HTML")"
    
    message_id="$(jq -r '.result.message_id' <<< "$response" 2>/dev/null)"
    
    if [[ -z "$message_id" ]] || [[ "$message_id" == "null" ]]; then
      "${s6wrap[@]}" echo "Error sending photo to Telegram: $response"
      { echo "{ \"title\": \"Telegram Photo Send Error\","
        echo "  \"response\": $response }"
      } >> /tmp/telegram.json
    else
      echo "https://t.me/c/${TELEGRAM_CHAT_ID}/${message_id}" > /tmp/telegram.link
      "${s6wrap[@]}" echo "Photo message sent successfully to Telegram; link: $(</tmp/telegram.link)"
      exit 0
    fi
done

# If no images or image sending failed, send text only
if ! $has_images; then
    response="$(curl -s -X POST "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "text=${TEXT}" \
        -F "parse_mode=HTML")"
    
    message_id="$(jq -r '.result.message_id' <<< "$response" 2>/dev/null)"
    
    if [[ -z "$message_id" ]] || [[ "$message_id" == "null" ]]; then
      "${s6wrap[@]}" echo "Error sending message to Telegram: $response"
      { echo "{ \"title\": \"Telegram Message Send Error\","
        echo "  \"response\": $response }"
      } >> /tmp/telegram.json
      exit 1
    else
      echo "https://t.me/c/${TELEGRAM_CHAT_ID}/${message_id}" > /tmp/telegram.link
      "${s6wrap[@]}" echo "Text message sent successfully to Telegram; link: $(</tmp/telegram.link)"
    fi
fi