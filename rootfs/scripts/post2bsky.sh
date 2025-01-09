#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154,SC2001
# -----------------------------------------------------------------------------------
# Copyright 2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------

source /usr/share/planefence/persist/planefence.config
source /scripts/common

if (( ${#@} < 1 )); then
    "${s6wrap[@]}" echo "Usage: $0 <text> [image1] [image2] ..."
    exit 1
fi

# Set the default values
BLUESKY_API="${BLUESKY_API:-https://bsky.social/xrpc}"
BLUESKY_MAXLENGTH="${BLUESKY_MAXLENGTH:-300}"

mapurls=("${BLUESKY_MAPURLS[@]}")
if [[ -z "${mapurls[*]}" ]]; then
    mapurls=(adsbexchange flightradar24 planefinder opensky flightaware fr24 radarbox airnav airplanes.live adsb.lol adsb.fi wiki planefence)
fi

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
    "${s6wrap[@]}" echo "Error: Failed to authenticate with Bluesky. Returned response was $auth_response"
    exit 1
fi

# send pictures to Bluesky
unset cid size mimetype tagstart tagend urlstart urlend urluri
declare -A size mimetype tagstart tagend urlstart urlend urluri

for image in "${IMAGES[@]}"; do
     # skip if the image is not a file that exists or if it's greater than 1MB (max file size for BlueSky)
     if [[ -z "$image" ]] || [[ ! -f "$image" ]]; then
         continue
     fi
     # figure out what type the image is: jpeg, png, gif.
     mimetype_local="$(file --mime-type -b "$image")"

     if (( $(stat -c%s "$image") >= 1000000 )); then
         if [[ "$mimetype_local" == "image/jpeg" ]]; then
             jpegoptim -q -S950 -s "$image"	# if it's JPG and > 1 MB, we can optimize for it
         else
             continue # skip if it's > 1MB and not JPG
         fi
     fi

    #Send the image to Bluesky
    response="$(curl -s -X POST "$BLUESKY_API/com.atproto.repo.uploadBlob" \
       -H "Content-Type: $mimetype_local" \
       -H "Authorization: Bearer $access_jwt" \
       --data-binary "@$image")"

    cid_local="$(jq -r '.blob.ref."$link"' <<< "$response")"
    size_local="$(jq -r '.blob.size' <<< "$response")"
    if [[ -z "$cid_local" ]] || [[ "$cid_local" == "null" ]]; then
        "${s6wrap[@]}" echo "Error uploading image to BlueSky: $response"
    else
        cid+=("$cid_local")
        size["$cid_local"]="$size_local"
        mimetype["$cid_local"]="$mimetype_local"
        "${s6wrap[@]}" echo "Image uploaded to Bluesky: $cid_local"
    fi
done

# Clean up the text
# First extract and remove any URLs
readarray -t urls <<< "$(grep -ioE 'https?://\S*' <<< "${TEXT}")"   # extract URLs
post_text="$(sed -e 's|http[s]\?://\S*||g' -e '/^$/d' <<< "$TEXT")"  # remove URLs and empty lines

# further cleanup:
if [[ "${post_text: -3}" == " - " ]]; then post_text="${post_text:0:-3}"; fi  # remove trailing " - "

# extract hashtags
readarray -t hashtags <<< "$(grep -o '#[[:alnum:]]*' <<< "$post_text")"
# Iterate through hashtags to get their position and length and remove the "#" symbol
for tag in "${hashtags[@]}"; do
    tagstart[${tag:1}]="$(($(awk -v a="$post_text" -v b="$tag" 'BEGIN{print index(a,b)}') - 1))"   # get the position of the tag
    tagend[${tag:1}]="$((${tagstart[${tag:1}]} + ${#tag} - 1))" # get the length of the tag without the "#" symbol
    post_text="$(sed "0,/${tag}/s//${tag:1}/" <<< "$post_text")"    # remove the "#" symbol (from the first occurrence only)
    #echo "DEBUG: $tag - ${tagpos[${tag:1}]} - ${taglen[${tag:1}]} - tagtext ${post_text:${tagpos[${tag:1}]}:${taglen[${tag:1}]}} - newstring: $post_text"
done

# add links
linkcounter=0

for url in "${urls[@]}"; do
    urlfound=false
    for mapurl in "${mapurls[@]}"; do
        if [[ "$url" == *"$mapurl"* ]] && (( ${#post_text} + ${#mapurl} + 3 <= BLUESKY_MAXLENGTH )); then
            # We have a link to one of the map services. Add it to the post text
            post_text+=" - ${mapurl}"
            index="$mapurl$((linkcounter++))"
            urlstart["$index"]="$((${#post_text} - ${#mapurl}))"
            urlend["$index"]="${#post_text}"
            urluri["$index"]="$url"
            urlfound=true
            break
        fi
    done
    if ! $urlfound && (( ${#post_text} + 7 <= BLUESKY_MAXLENGTH )); then
        # We have a generic link. Add it to the post text
        post_text+=" - link"
        index="link$((linkcounter++))"
        urlstart["$index"]="$((${#post_text} - 4))"
        urlend["$index"]="${#post_text}"
        urluri["$index"]="$url"
        break
    fi
    if (( ${#post_text} + 7 > BLUESKY_MAXLENGTH )); then
        # we have reached the maximum length of the post text
        break
    fi
done

# echo "DEBUG: urlstart: ${urlstart[*]} for indices ${!urlstart[*]}"
# echo "DEBUG: urlend: ${urlend[*]} for indices ${!urlend[*]}"
# echo "DEBUG: urluri: ${urluri[*]} for indices ${!urluri[*]}"

post_text="${post_text:0:$BLUESKY_MAXLENGTH}"      # limit to 300 characters
post_text="${post_text//[[:cntrl:]]/\\n}"
#echo "DEBUG: post_text after URL/hashtag processing: $post_text"

# Prepare the post data
if (( ${#cid[@]} == 0 )); then
    # no images
    post_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.feed.post\",
        \"record\": {
            \"\$type\": \"app.bsky.feed.post\",
            \"text\": \"$post_text\",
            \"createdAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\""
    # add hashtags and links:
    if (( ${#hashtags[@]} + ${#urlstart[@]} > 0 )); then
        post_data+=",
            \"facets\": [
                "
        if (( ${#hashtags[@]} > 0 )); then
            for tag in "${hashtags[@]}"; do
                post_data+="
                    {
                        \"index\": {
                            \"byteStart\": ${tagstart[${tag:1}]},
                            \"byteEnd\": ${tagend[${tag:1}]}
                        },
                        \"features\": [{
                            \"\$type\": \"app.bsky.richtext.facet#tag\",
                            \"tag\": \"${tag:1}\"
                        }]
                    },"
            done
        fi
        if (( ${#urlstart[@]} > 0 )); then
            for url in "${!urlstart[@]}"; do
                post_data+="
                    {
                        \"index\": {
                            \"byteStart\": ${urlstart[${url}]},
                            \"byteEnd\": ${urlend[${url}]}
                        },
                        \"features\": [{
                            \"\$type\": \"app.bsky.richtext.facet#link\",
                            \"uri\": \"${urluri[${url}]}\"
                        }]
                    },"
            done
        fi
        post_data="${post_data%,}"  # remove last comma
        post_data+="
            ]"
    fi

    post_data+="
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
                    \"mimeType\": \"${mimetype["$img"]}\" ,
                    \"size\": ${size["$img"]}
                },
                \"alt\": \"\"
            },"
    done

    # Remove trailing comma and close the array and the rest of the post data
    post_data="${post_data%,}"  # remove last comma
    post_data+="
                ]
            }"

    # add hashtags and links:
    if (( ${#hashtags[@]} + ${#urlstart[@]} > 0 )); then
        post_data+=",
            \"facets\": [
                "
        if (( ${#hashtags[@]} > 0 )); then
            for tag in "${hashtags[@]}"; do
                post_data+="
                    {
                        \"index\": {
                            \"byteStart\": ${tagstart[${tag:1}]},
                            \"byteEnd\": ${tagend[${tag:1}]}
                        },
                        \"features\": [{
                            \"\$type\": \"app.bsky.richtext.facet#tag\",
                            \"tag\": \"${tag:1}\"
                        }]
                    },"
            done
        fi
        if (( ${#urlstart[@]} > 0 )); then
            for url in "${!urlstart[@]}"; do
                post_data+="
                    {
                        \"index\": {
                            \"byteStart\": ${urlstart[${url}]},
                            \"byteEnd\": ${urlend[${url}]}
                        },
                        \"features\": [{
                            \"\$type\": \"app.bsky.richtext.facet#link\",
                            \"uri\": \"${urluri[${url}]}\"
                        }]
                    },"
            done
        fi
        post_data="${post_data%,}"  # remove last comma
        post_data+="
            ]"
    fi

    post_data+="
            }
        }"

    post_data+="
        }
    }"
fi

#echo "DEBUG: post_data: $post_data"
#echo "$post_data" >> /tmp/bsky.json
#echo "-------------------------------------------------" >> /tmp/bsky.json

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