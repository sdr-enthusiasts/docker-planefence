#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154,SC2001
# -----------------------------------------------------------------------------------
# Copyright 2025 Ramon F. Kolb, kx1t - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------

source /usr/share/planefence/persist/planefence.config
source /scripts/pf-common

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, butspost2bsky is called from another script, and we don't want to polute the returns with info text

shopt -s extglob

# Set the default values
BLUESKY_API="${BLUESKY_API:-https://bsky.social/xrpc}"
BLUESKY_MAXLENGTH="${BLUESKY_MAXLENGTH:-300}"
SPACE=$'\x1F'   # "special" space

if (( ${#@} < 1 )); then
  log_print ERR "Usage: $0 <text> [image1] [image2] ..."
  exit 1
fi

function get_rate_str() {
  if [[ ! -f /tmp/bsky.headers ]]; then return; fi
  ratelimit_reset="$(awk '{if ($2 == "ratelimit-reset:") {print $3; exit}}' < /tmp/bsky.headers)"
  ratelimit_limit="$(awk '{if ($2 == "ratelimit-limit:") {print $3; exit}}' < /tmp/bsky.headers)"
  ratelimit_remaining="$(awk '{if ($2 == "ratelimit-remaining:") {print $3; exit}}' < /tmp/bsky.headers)"
  ratelimit_str="Rate Limits: ${ratelimit_remaining//[^[:digit:]]/} of ${ratelimit_limit//[^[:digit:]]/}; $(if [[ -n "${ratelimit_reset//[^[:digit:]]/}" ]]; then date -d @"${ratelimit_reset//[^[:digit:]]/}" +"resets at %c"; fi)"
  rm -f /tmp/bsky.headers
}

function bsky_auth() {
  # function to authenticate with BlueSky

  local active=false
  local refresh_jwt auth_response

  # if we have previous authentication data stored, use that to refresh the token
  if [[ -f /tmp/bsky.auth ]]; then
    source /tmp/bsky.auth
    auth_response="$(curl -v -sL -X POST "$BLUESKY_API/com.atproto.server.refreshSession" \
      -H "Authorization: Bearer $refresh_jwt" 2>/tmp/bsky.headers)"
    access_jwt="$(jq -r '.accessJwt' <<< "$auth_response")"
    did="$(jq -r '.did' <<< "$auth_response")"
    refresh_jwt="$(jq -r '.refreshJwt' <<< "$auth_response")"
    active="$(jq -r '.active' <<< "$auth_response")"
    handle="$(jq -r '.handle' <<< "$auth_response")"
  fi

  # if that didn't work, create a new session
  if [[ -z "$active" ]] || ! $active || [[ "$active" == "null" ]] \
  || [[ -z "$access_jwt" ]] || [[ "$access_jwt" == "null" ]] \
  || [[ -z "$did" ]] || [[ "$did" == "null" ]] \
  || [[ -z "$refresh_jwt" ]] || [[ "$refresh_jwt" == "null" ]]; then
    auth_response="$(curl -v -sL -X POST "$BLUESKY_API/com.atproto.server.createSession" \
      -H "Content-Type: application/json" \
      -d "{\"identifier\":\"$BLUESKY_HANDLE\",\"password\":\"$BLUESKY_APP_PASSWORD\"}" 2>/tmp/bsky.headers)"
    access_jwt="$(jq -r '.accessJwt' <<< "$auth_response")"
    did="$(jq -r '.did' <<< "$auth_response")"
    refresh_jwt="$(jq -r '.refreshJwt' <<< "$auth_response")"
    active="$(jq -r '.active' <<< "$auth_response")"
    handle="$(jq -r '.handle' <<< "$auth_response")"
  fi

  get_rate_str

  # if that didn't work, give up
  if [[ -z "$access_jwt" || "$access_jwt" == "null" ]]; then
    log_print ERR "BlueSky Authentication Error: $auth_response. $ratelimit_str"
    { echo "{ \"title\": \"BlueSky Posting Error\""
      echo "  \"response\": $auth_response ,"
      echo "  \"ratelimit\": $ratelimit_str } ,"
    } >> /tmp/bsky.json
    err="$(</tmp/bsky.json)"; if [[ "${err: -1}" == "," ]]; then printf "%s\n" "${err:0:-1}" >/tmp/bsky.json; fi
    exit 1
  fi

  log_print INFO "BlueSky authentication OK. Welcome, $handle! Your $ratelimit_str";

  # write back the token info to the authentication file
  cat >/tmp/bsky.auth <<EOF
access_jwt="$access_jwt"
refresh_jwt="$refresh_jwt"
EOF

}

# Check if the required variables are set
if [[ -z "$BLUESKY_HANDLE" ]]; then
    log_print ERR "The BLUESKY_HANDLE environment variable must be set to something like \"xxxxx.bsky.social\""
    exit 1
fi
if [[ -z "$BLUESKY_APP_PASSWORD" ]]; then
    log_print ERR "The BLUESKY_APP_PASSWORD environment variable must be set to the app password"
    exit 1
fi

# Extract info from the command line arguments
args=("$@")
TEXT="${args[0]}"
IMAGES=("${args[1]}" "${args[2]}" "${args[3]}" "${args[4]}") # up to 4 images

if [[ -z "$TEXT" ]]; then
    log_print ERR "A post text must be included in the request to $0"
    exit 1
fi

# Authenticate with BlueSky
bsky_auth

# send pictures to Bluesky
unset cid size mimetype tagstart tagend urlstart urlend urluri
declare -A size mimetype tagstart tagend urlstart urlend urluri

for image in "${IMAGES[@]}"; do
  # skip if the image is not a file that exists or if it's greater than 1MB (max file size for BlueSky)
  if [[ -z "$image" ]] || [[ ! -f "$image" ]]; then
      continue
  fi

  # figure out what type the image is: jpeg, png, gif, and reduce size if necessary/possible.
  mimetype_local="$(file --mime-type -b "$image")"
  imgsize_org="$(stat -c%s "$image")"
  modtime_org="$(stat -c "%y" "$image")"

  if (( imgsize_org >= 950000 )); then
    if [[ "$mimetype_local" == "image/jpeg" ]]; then
      jpegoptim -q -S950 -s "$image"	# if it's JPG and > 1 MB, we can optimize for it
      # try again if still too big
      if (( $(stat -c%s "$image") >= 950000 )); then
          jpegoptim -q -S850 -s "$image"
      fi
    elif [[ "$mimetype_local" == "image/png" ]]; then
      pngquant -f -o "${image}.tmp" 64 "$image"	# if it's PNG and > 1 MB, we can optimize for it
      mv -f "${image}.tmp" "$image"
    else
      log_print WARN "Omitting image $image as it is too big ($imgsize)"
      continue # skip if it's not JPG or PNG
    fi
    touch -d "$modtime_org" "$image"    # restore original modification date of the image (for cache management purposes)
    log_print INFO "Image size of $image reduced from $imgsize_org to $(stat -c%s "$image")"
  fi
  if (( $(stat -c%s "$image") >= 950000 )); then
    log_print WARN "Omitting image $image as the size reduction was insufficient: before: $imgsize_org; now: $(stat -c%s "$image")"
    continue;
  fi # skip if it's still > 1MB

  #Send the image to Bluesky
  response="$(curl -v -sL -X POST "$BLUESKY_API/com.atproto.repo.uploadBlob" \
    -H "Content-Type: $mimetype_local" \
    -H "Authorization: Bearer $access_jwt" \
    --data-binary "@$image" 2>/tmp/bsky.headers)"
  #Get the CID, size, and official MIME type of the image. Need need this to correctly refer to it in the subsequent post
  cid_local="$(jq -r '.blob.ref."$link"' <<< "$response")"
  size_local="$(jq -r '.blob.size' <<< "$response")"
  get_rate_str
  if [[ -z "$cid_local" ]] || [[ "$cid_local" == "null" ]]; then
    log_print ERR "Error uploading $image to BlueSky: $response. $ratelimit_str. Local size is $(stat -c%s "$image"); reported blob size is $size_local."
    { echo "{ \"title\": \"BlueSky Image Upload Error\""
      echo "  \"response\": $response ,"
      echo "  \"ratelimit\": $ratelimit_str } ,"
    } >> /tmp/bsky.json
  else
    cid+=("$cid_local")
    size["$cid_local"]="$size_local"
    mimetype["$cid_local"]="$mimetype_local"
    log_print INFO "$image uploaded succesfully to BlueSky. $ratelimit_str"
  fi
done

log_print DEBUG "TEXT before cleanup: $TEXT"

# Clean up the text
# Extract and remove any URLs
readarray -t urls <<< "$(grep -ioE 'https?://\S*' <<< "${TEXT}")"   # extract URLs
post_text="$(sed -e 's|http[s]\?://\S*||g' -e '/^$/d' <<< "$TEXT")"  # remove URLs and empty lines
post_text="${post_text%%+([[:space:]])}"  # trim trailing spaces

# extract hashtags, store them, and find their start/end positions.
# This is necessary because BSky tags text portions as Facets, with a start/end position
readarray -t hashtags <<< "$(grep -o '#[^[:space:]#]*' <<< "$post_text" 2>/dev/null | sed 's/^\(.*\)[^[:alnum:]]\+$/\1/g' 2>/dev/null)"

# Iterate through hashtags to get their position and length and remove the "#" symbol
for tag in "${hashtags[@]}"; do
  if [[ -z "${tagstart[${tag:1}]}" ]]; then
    # first occurrence of the tag in the string
    tagstart[${tag:1}]="$(($(awk -v a="$post_text" -v b="$tag" 'BEGIN{print index(a,b)}') - 1))"   # get the position of the tag
    tagend[${tag:1}]="$((${tagstart[${tag:1}]} + ${#tag} - 1))" # get the length of the tag without the "#" symbol
  fi
  post_text="$(sed "0,/${tag}/s//${tag:1}/" <<< "$post_text")"    # remove the "#" symbol (from the first occurrence only)
done

# ${SPACE} is used as a token instead of spaces inside hashtags. Replace all ${SPACE} with a space
post_text="${post_text//${SPACE}/ }"

# add links
linkcounter=0

for url in "${urls[@]}"; do
  if (( ${#post_text} + 7 <= BLUESKY_MAXLENGTH )); then
    # We have a generic link. Add it to the post text
    basetext="$(extract_base "$url")"
    if [[ -z "$basetext" ]]; then basetext="link"; fi 
    post_text+="•$basetext"
    index="link$((linkcounter++))"
    urlstart["$index"]="$((${#post_text} - ${#basetext}))"
    urlend["$index"]="${#post_text}"
    urluri["$index"]="$url"
  fi
done

post_text="${post_text:0:$BLUESKY_MAXLENGTH}"      # limit to 300 characters
post_text="${post_text//[[:cntrl:]]/\\n}"

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
        if (( ${#tagstart[@]} > 0 )); then
            for tag in "${!tagstart[@]}"; do
                post_data+="
                    {
                        \"index\": {
                            \"byteStart\": ${tagstart[${tag}]},
                            \"byteEnd\": ${tagend[${tag}]}
                        },
                        \"features\": [{
                            \"\$type\": \"app.bsky.richtext.facet#tag\",
                            \"tag\": \"${tag}\"
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

        if (( ${#tagstart[@]} > 0 )); then
            for tag in "${!tagstart[@]}"; do
                post_data+="
                    {
                        \"index\": {
                            \"byteStart\": ${tagstart[${tag}]},
                            \"byteEnd\": ${tagend[${tag}]}
                        },
                        \"features\": [{
                            \"\$type\": \"app.bsky.richtext.facet#tag\",
                            \"tag\": \"${tag}\"
                        }]
                    },"
            done
        fi

        if (( ${#urlstart[@]} > 0 )); then
            for url in "${!urlstart[@]}"; do
                shortlink="$(curl -sSL -G --data-urlencode "url=${urluri[${url}]}" "https://is.gd/create.php?format=simple")" || true
                if [[ -n "$shortlink" && "${shortlink:0:4}" == "http" ]]; then urluri["$url"]="$shortlink"; fi
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
fi

# Send the post to Bluesky
response=$(curl -v -sL -X POST "$BLUESKY_API/com.atproto.repo.createRecord" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $access_jwt" \
  -d "$post_data" 2>/tmp/bsky.headers)

get_rate_str

if [[ "$(jq -r '.uri' <<< "$response")" != "null" ]]; then
  uri="$(jq -r '.uri' <<< "$response")"
  echo "https://bsky.app/profile/$handle/post/${uri##*/}"
else
  log_print ERR "BlueSky Posting Error: $response. $ratelimit_str"
  if [[ -f /tmp/bsky.json ]]; then
      err="$(</tmp/bsky.json)"
      if [[ "${err: -1}" != "," ]]; then echo " ," >>/tmp/bsky.json; fi
  fi
  { echo "{ \"title\": \"BlueSky Posting Error\" ,"
    echo "  \"response\": $response ,"
    echo "  \"ratelimit\": $ratelimit_str ,"
    echo "  \"postdata\": $post_data } ,"
  } >> /tmp/bsky.json
  err="$(</tmp/bsky.json)"; if [[ "${err: -1}" == "," ]]; then printf "%s\n" "${err:0:-1}" >/tmp/bsky.json; fi
  echo "$response"
  exit 1
fi
