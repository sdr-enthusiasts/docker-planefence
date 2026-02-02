#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154,SC2001
# -----------------------------------------------------------------------------------
# Copyright 2026 Ramon F. Kolb, kx1t - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------

source /scripts/pf-common

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, but post2bsky is called from another script, and we don't want to polute the returns with info text

shopt -s extglob

SPACE=$'\x1F'   # "special" space

DEBUG=false   # set to true to enable debug output to /tmp/bsky.debug

# helpers to keep facet offsets correct when the text contains multi-byte characters
function utf8_byte_len() {
  LC_ALL=C printf '%s' "$1" | wc -c | tr -d '[:space:]'
}

function utf8_first_byte_offset() {
  local haystack="$1" needle="$2" out
  out="$(grep -b -o -m1 -- "$needle" <<< "$haystack" 2>/dev/null)" || { printf '%s\n' -1; return; }
  printf '%s\n' "${out%%:*}"
}

if (( ${#@} < 1 )); then
  log_print ERR "Usage: $0 [pf|pa] <text> [image1] [image2] ..."
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

  log_print DEBUG "BlueSky authentication OK. Welcome, $handle! Your $ratelimit_str";

  # write back the token info to the authentication file
  cat >/tmp/bsky.auth <<EOF
access_jwt="$access_jwt"
refresh_jwt="$refresh_jwt"
EOF

}

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

# Set the default values
BLUESKY_API="${BLUESKY_API:-https://bsky.social/xrpc}"
BLUESKY_MAXLENGTH="${BLUESKY_MAXLENGTH:-300}"

# Check if the required variables are set
if [[ -z "$BLUESKY_HANDLE" ]]; then
    log_print ERR "The BLUESKY_HANDLE environment variable must be set to something like \"xxxxx.bsky.social\""
    exit 1
fi
if [[ -z "$BLUESKY_APP_PASSWORD" ]]; then
    log_print ERR "The BLUESKY_APP_PASSWORD environment variable must be set to the app password"
    exit 1
fi

# Normalize the text so it's all 1-byte characters:
TEXT="$(printf '%b\n' "$TEXT" | awk '{ for(i=1; i<=length($0); i++) printf("%c", substr($0,i,1)); printf("\n") }')"

# Authenticate with BlueSky
bsky_auth

# send pictures to Bluesky
unset cid size mimetype tagstart tagend urlstart urlend urluri urllabel
declare -A size mimetype tagstart tagend urlstart urlend urluri urllabel

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
    log_print DEBUG "Image size of $image reduced from $imgsize_org to $(stat -c%s "$image")"
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
    log_print DEBUG "$image uploaded succesfully to BlueSky. $ratelimit_str"
  fi
done

log_print DEBUG "TEXT before cleanup: $TEXT"

# Clean up the text
# Extract and remove any URLs
readarray -t urls <<< "$(grep -ioE 'https?://\S*' <<< "${TEXT}")"   # extract URLs
post_text="$(sed -e 's|http[s]\?://\S*||g' -e '/^$/d' <<< "$TEXT")"  # remove URLs and empty lines
post_text="${post_text%%+([[:space:]])}"  # trim trailing spaces
post_text="${post_text//[[:cntrl:]]/\\n}"  # replace control characters with newlines

# extract hashtags (raw, with #)
readarray -t hashtags <<< "$(grep -o '#[^[:space:]#]*' <<< "$post_text" 2>/dev/null)"

# ${SPACE} is used as a token instead of spaces inside hashtags. Replace all ${SPACE} with a space
post_text="${post_text//${SPACE}/ }"

# Remove the # symbol from hashtags in the text (first occurrence of each)
for tag in "${hashtags[@]}"; do
  tag="${tag//${SPACE}/ }"
  tag_key="${tag:1}"
  [[ -z "$tag_key" ]] && continue
  # escape tag for safe sed replacement
  esc_tag="$(printf '%s\n' "$tag" | sed 's/[.[\*^$]/\\&/g')"
  post_text="$(sed "0,/${esc_tag}/s//${tag_key}/" <<< "$post_text")"
done

# add links
linkcounter=0

for url in "${urls[@]}"; do
  if (( ${#post_text} + 7 <= BLUESKY_MAXLENGTH )); then
    # We have a generic link. Add it to the post text
    basetext="$(extract_base "$url")"
    if [[ -z "$basetext" ]]; then basetext="link"; fi 
    post_text+="•$basetext"
    index="link$((linkcounter++))"
    urllabel["$index"]=" $basetext"
    urluri["$index"]="$url"
  fi
done

post_text="${post_text:0:$BLUESKY_MAXLENGTH}"      # limit to 300 characters
post_text_raw="$post_text"                        # keep unescaped text for facet math

# Recalculate facets on the finalized post_text (byte offsets, UTF-8 safe)
unset tagstart tagend urlstart urlend
declare -A tagstart tagend urlstart urlend
post_len_bytes="$(utf8_byte_len "$post_text_raw")"

for tag in "${hashtags[@]}"; do
  tag="${tag//${SPACE}/ }"
  tag_key="${tag:1}"
  [[ -z "$tag_key" ]] && continue
  [[ -n "${tagstart[$tag_key]+x}" ]] && continue
  start_pos="$(utf8_first_byte_offset "$post_text_raw" "$tag_key")"
  [[ "$start_pos" -lt 0 ]] && continue
  end_pos="$((start_pos + $(utf8_byte_len "$tag_key")))"
  (( end_pos > post_len_bytes )) && continue
  tagstart[$tag_key]="$start_pos"
  tagend[$tag_key]="$end_pos"
done

for url in "${!urllabel[@]}"; do
  label="${urllabel[$url]}"
  basetext="${label#•}"
  start_label="$(utf8_first_byte_offset "$post_text_raw" "$label")"
  if (( start_label < 0 )); then continue; fi
  start_pos="$((start_label + $(utf8_byte_len "-")))"
  end_pos="$((start_pos + $(utf8_byte_len "$basetext")))"
  (( end_pos > post_len_bytes )) && continue
  urlstart[$url]="$start_pos"
  urlend[$url]="$end_pos"
done

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
response=$(curl -sSL -X POST "$BLUESKY_API/com.atproto.repo.createRecord" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $access_jwt" \
  -d "$post_data")

get_rate_str

if [[ "$(jq -r '.uri' <<< "$response")" != "null" ]]; then
  uri="$(jq -r '.uri' <<< "$response")"
  echo "https://bsky.app/profile/$handle/post/${uri##*/}"
else
  log_print ERR "BlueSky Posting Error: $ratelimit_str; response was (original had http instead of hxttp):\n${response//http/hxttp}\nOriginal:\n${post_data//http/hxttp}"
  exit 1
fi


#debug:
if chk_enabled "$DEBUG"; then
  {
    echo "---------------------"
    echo "POST DATA SENT TO BLUESKY:"
    echo "$post_data"
    echo "RESPONSE FROM BLUESKY:"
    echo "$response"
  } >> /tmp/bsky.debug
fi
