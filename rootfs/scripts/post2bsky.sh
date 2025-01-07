#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------

if [[ -f /usr/share/planefence/persist/planefence.config ]]; then
    source /usr/share/planefence/persist/planefence.config
fi

source /scripts/common

if (( ${#@} < 1 )); then
    "${s6wrap[@]}" echo "Usage: $0 <text> [image1] [image2] ..."
    exit 1
fi

# Set the default values
BLUESKY_API="${BLUESKY_API:-https://bsky.social/xrpc}"

# Check if the required variables are set
if [[ -z "$BLUESKY_HANDLE" ]]; then
    "${s6wrap[@]}" echo "Fatal: the BLUESKY_HANDLE environment variable must be set to something like \"xxxxx.bsky.social\""    
    exit 1
fi
if [[ -z "$BLUESKY_APP_PASSWORD" ]]; then
    "${s6wrap[@]}" echo "Fatal: the BLUESKY_APP_PASSWORD environment variable must be set to the app password"
    exit 1
fi

# Extract info from the command line arguments
args=("$@")
TEXT="${args[0]}"
IMAGES=("${args[1]}" "${args[2]}" "${args[3]}" "${args[4]}") # up to 4 images

# First get an auth token
auth_response=$(curl -s -X POST "$BLUESKY_API/com.atproto.server.createSession" \
    -H "Content-Type: application/json" \
    -d "{\"identifier\":\"$BLUESKY_HANDLE\",\"password\":\"$BLUESKY_APP_PASSWORD\"}")

access_jwt=$(echo "$auth_response" | jq -r '.accessJwt')
did=$(echo "$auth_response" | jq -r '.did')

if [[ -z "$access_jwt" || "$access_jwt" == "null" ]]; then
    echo "[$(date)][$APPNAME] Error: Failed to authenticate with Bluesky"
    exit 1
fi

# send pictures to Bluesky
unset cid size
declare -A size

for image in "${IMAGES[@]}"; do
    # skip if the image is not a file that exists
    if [[ -z "$image" ]] || [[ ! -f "$image" ]]; then
        continue
    fi

    #Send the image to Bluesky
    response="$(curl -s -X POST "$BLUESKY_API/com.atproto.repo.uploadBlob" \
       -H "Content-Type: image/jpeg" \
       -H "Authorization: Bearer $access_jwt" \
       --data-binary "@$image")"


    # response="$(curl -X POST "https://bsky.social/xrpc/com.atproto.repo.createRecord" \
    #  -H "Authorization: Bearer $access_jwt" \
    #  -F "image=@$image")"

    cid_local="$(jq -r '.blob.ref."$link"' <<< "$response")"
    size_local="$(jq -r '.blob.size' <<< "$response")"
    if [[ -z "$cid_local" ]] || [[ "$cid_local" == "null" ]]; then
        "${s6wrap[@]}" echo "Error uploading image to BlueSky: $response"
    else
        cid+=("$cid_local")
        size["$cid_local"]="$size_local"
        "${s6wrap[@]}" echo "Image uploaded to Bluesky: $cid_local"
    fi
done

# Clean up the text
post_text="${TEXT//[[:cntrl:]]/ }"  # remove control characters
post_text="${post_text:0:300}"      # limit to 300 characters

# Prepare the post data
if (( ${#cid[@]} == 0 )); then
    # no images
    post_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.feed.post\",
        \"record\": {
            \"\$type\": \"app.bsky.feed.post\",
            \"text\": \"$post_text\",
            \"createdAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\"
        }
    }"
else
    post_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.feed.post\",
        \"record\": {
            \"\$type\": \"app.bsky.feed.post\",
            \"text\": \"$post_text\",
            \"createdAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
            \"embed\": {
                \"\$type\": \"app.bsky.embed.images\",
                \"images\": ["

    # Loop through CIDs if there are multiple images
    for img in "${cid[@]}"; do
        post_data+="
            { 
                \"image\": {
                    \"\$type\": \"blob\",
                    \"ref\": { \"\$link\": \"$img\" }, 
                    \"mimeType\": \"image/jpeg\" ,
                    \"size\": ${size["$img"]}
                },
                \"alt\": \"\" 
            },"
    done

    # Remove trailing comma and close the array and the rest of the post data
    post_data="${post_data%,}"  # remove last comma
    post_data+="
                ]
            }
        }
    }"
fi

# Send the post to Bluesky
response=$(curl -s -X POST "$BLUESKY_API/com.atproto.repo.createRecord" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $access_jwt" \
    -d "$post_data")

if [[ "$(jq -r '.uri' <<< "$response")" != "null" ]]; then
	"${s6wrap[@]}" echo "BlueSky Post successful. Post available at $(jq -r '.uri' <<< "$response")"
else
	"${s6wrap[@]}" echo "BlueSky Posting Error: $response"
fi

