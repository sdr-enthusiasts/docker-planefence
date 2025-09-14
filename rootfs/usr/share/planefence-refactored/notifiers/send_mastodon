#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2164,SC1090,SC1091,SC2154,SC2001
#---------------------------------------------------------------------------------------------
# Copyright (C) 2022-2025, Ramon F. Kolb (kx1t)
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
#---------------------------------------------------------------------------------------------
# This script sends a Mastodon notification (toot)

source /scripts/common

VESSELDBFILE="${VESSELDBFILE:-/data/vessel.db}"

# load the notification JSON from the template:
source "/usr/share/vesselalert/load_databases"

MASTODON_POST_VISIBILITY="${MASTODON_POST_VISIBILITY:-unlisted}"
IMAGECACHE="${VESSELDBFILE%/*}/imagecache"
MASTODON_SERVER="${MASTODON_SERVER,,}"
MASTODON_SERVER="${MASTODON_SERVER:-airwaves.social}"
if [[ "${MASTODON_SERVER:0:7}" == "http://" ]]; then MASTODON_SERVER="${MASTODON_SERVER:7}"; fi
if [[ "${MASTODON_SERVER:0:8}" == "https://" ]]; then MASTODON_SERVER="${MASTODON_SERVER:8}"; fi
MASTODON_SERVER="https://${MASTODON_SERVER}"


if [[ -z "$1" ]]
then
    "${s6wrap[@]}" echo "[ERROR] $0 - send a Mastodon notification for a specific MMSI"
    "${s6wrap[@]}" echo "[ERROR] Usage: $0 mmsi"
    exit 1
else
    "${s6wrap[@]}" echo "[INFO] Attempting Mastodon notification for $1 (${VESSELS[$1:shipname]})"
fi

if [[ "${*:2}" =~ .*tropoalert=.* ]]
then
    notify_tropo=true
else
    unset notify_tropo
fi
if [[ -z "${MASTODON_ACCESS_TOKEN}" ]]
then
    "${s6wrap[@]}" echo "[ERROR] MASTODON_ACCESS_TOKEN not defined. Cannot send a Mastodon notification"
    exit 1
fi

# First do some clean up
if [[ -n "${VESSELS[$1:shipname]}" ]]; then VESSELS[$1:shipname]="$(sed -e ':a;s/^\(\([^"]*[,.]\?\|"[^",.]*"[,.]\?\)*"[^",.]*\)[,.]/\1 /;ta' -e 's|["'\''.]||g' -e 's|[^A-Z0-9,\.\-]\+|_|g' -e 's|_,|,|g' <<< "${VESSELS[$1:shipname]}")"; fi
if [[ -n "${VESSELS[$1:destination]}" ]]; then VESSELS[$1:destination]="$(sed -e ':a;s/^\(\([^"]*[,.]\?\|"[^",.]*"[,.]\?\)*"[^",.]*\)[,.]/\1 /;ta' -e 's|["'\''.]||g' -e 's|[^A-Z0-9,\.\-\<\>]\+|_|g' -e 's|_,|,|g' <<< "${VESSELS[$1:destination]}")"; fi

# Build the message - create notification string

links=""
chk_enabled "${MASTODON_LINK_AISCATCHER:-on}" && links+="https://aiscatcher.org/ship/details/${VESSELS[$1:mmsi]}\n" || true
chk_enabled "$MASTODON_LINK_SHIPXPLORER" && links+="https://www.shipxplorer.com/data/vessels/IMO-MMSI-${VESSELS[$1:mmsi]}\n" || true
chk_enabled "$MASTODON_LINK_MARINETRAFFIC" && links+="https://www.marinetraffic.com/en/ais/details/ships/${VESSELS[$1:mmsi]}\n" || true
chk_enabled "$MASTODON_LINK_VESSELFINDER" && links+="https://www.vesselfinder.com/vessels/details/${VESSELS[$1:mmsi]}\n" || true

unset mast_str

if [[ -n "$notify_tropo" ]]; then
    mast_str="#${NOTIF_TERM[TROPOMAXDIST]} = $(printf "%.1f" "${VESSELS[$1:distance]}") nm\n"
fi

mast_str+="#VesselAlert"
if [[ "${NOTIF_TERM[SHIP]}" != "Ship" ]]; then mast_str+=" #${NOTIF_TERM[SHIP]}"; fi
if [[ -z "${VESSELS[$1:notification:last]}" ]]; then mast_str+=" ${NOTIF_TERM[NEW]}"; fi
if [[ "${notify_distance}" == "true" ]]; then mast_str+=" #${NOTIF_TERM[ONTHEMOVE]}"; fi
mast_str+="\n"
if [[ -n "${VESSELS[$1:shipname]}" ]]; then mast_str+="${NOTIF_TERM[SHIPNAME]}: #${VESSELS[$1:shipname]}\n"; fi
if [[ -n "${VESSELS[$1:mmsi]}" ]]; then mast_str+="#MMSI: #${VESSELS[$1:mmsi]}\n"; fi
if [[ -n "${VESSELS[$1:callsign]}" ]]; then mast_str+="${NOTIF_TERM[CALLSIGN]}: #${VESSELS[$1:callsign]}\n"; fi
if [[ -n "${VESSELS[$1:shiptype]}" ]] && [[ -n "${SHIPTYPE[${VESSELS[$1:shiptype]}]}" ]]; then mast_str+="${NOTIF_TERM[SHIPTYPE]}: ${SHIPTYPE[${VESSELS[$1:shiptype]}]}\n"; fi

if [[ -n "${VESSELS[$1:country]}" ]]; then mast_str+="#${NOTIF_TERM[FLAG]}: #${COUNTRY[${VESSELS[$1:country]}]}\n"; fi
mast_str+="${NOTIF_TERM[MSGS_RECVD]}: ${VESSELS[$1:count]}\n"
mast_str+="${NOTIF_TERM[SEEN_ON]}: $(date -d @$(( $(date +%s) - ${VESSELS[$1:last_signal]} )) +"%d-%b-%Y %H:%M:%S %Z")\n"

if [[ -n "${VESSELS[$1:status]}" ]] && [[ -n "${SHIPSTATUS[${VESSELS[$1:status]}]}" ]]; then mast_str+="${NOTIF_TERM[STATUS]}: ${SHIPSTATUS[${VESSELS[$1:status]}]}\n"; fi
if [[ -n "${VESSELS[$1:speed]}" ]] && [[ "${VESSELS[$1:speed]}" != "0" ]] && [[ "${VESSELS[$1:speed]}" != "null" ]]; then mast_str+="${NOTIF_TERM[SPEED]}: $(printf "%.1f" "${VESSELS[$1:speed]}") kts\n"; fi
if [[ -n "${VESSELS[$1:heading]}" ]] && [[ "${VESSELS[$1:heading]}" != "0" ]] && [[ "${VESSELS[$1:heading]}" != "null" ]]; then mast_str+="${NOTIF_TERM[HEADING]}: ${VESSELS[$1:heading]} deg\n"; fi

if chk_enabled "$USE_FRIENDLY_DESTINATION" && [[ -n "${VESSELS[$1:destination:friendly]}" ]]; then
    mast_str+="${NOTIF_TERM[DESTINATION]}: ${VESSELS[$1:destination:friendly]}\n"
elif [[ -n "${VESSELS[$1:destination]}" ]]; then
    mast_str+="${NOTIF_TERM[DESTINATION]}: ${VESSELS[$1:destination]}\n"
fi

if [[ -n "${VESSELS[$1:destination]}" ]]; then mast_str+="${NOTIF_TERM[DESTINATION]}: ${VESSELS[$1:destination]}\n"; fi

if [[ -n "${VESSELS[$1:lat]}" ]] && [[ -n "${VESSELS[$1:lon]}" ]] && [[ -n "$LAT" ]] && [[ -n "$LON" ]]; then
    distance="$(bc -l <<< "scale=1; $(distance "${VESSELS[$1:lat]}" "${VESSELS[$1:lon]}" "$LAT" "$LON") / 1")"
    mast_str+="${NOTIF_TERM[DISTANCE]}: $distance nm\n"
fi

mast_str+="${NOTIF_TERM[SIGNAL]} #RSSI: $(printf "%.1f dBFS" "${VESSELS[$1:level]}")\n"

if [[ -n "${NOTIFICATION_MAPURL}" ]] && [[ "${NOTIFICATION_MAPURL:0:4}" != "http" ]]; then mast_str+="${NOTIF_TERM[LOCATION]}: ${AIS_URL}?mmsi=${VESSELS[$1:mmsi]}\n"; fi
if [[ -n "${NOTIFICATION_MAPURL}" ]] && [[ "${NOTIFICATION_MAPURL:0:4}" == "http" ]]; then mast_str+="${NOTIF_TERM[LOCATION]}: ${NOTIFICATION_MAPURL}?mmsi=${VESSELS[$1:mmsi]}\n"; fi
if [[ -n "${links}" ]]; then mast_str+="${links}\n"; fi

mast_str+="\n"

if [[ -n "$MASTODON_CUSTOM_FIELD" ]]; then mast_str+="$MASTODON_CUSTOM_FIELD\n"; fi

mast_str+="#${NOTIF_TERM[SHIP]} #AIS #VesselAlert © 2022-2025 #kx1t"

#shellcheck disable=SC2001
mast_str="$(sed -e 's|\\n|\n|g' <<< "$mast_str")"

# test and correct if max toot length is exceeded
toot_length="$(sed 's/http[^ ]*/xxxxxxxxxxxxxxxxxxxxxxxx/g' <<<"${mast_str//$'\n'/ }" | wc -m)"
if (( toot_length >= 500 )); then
   new_length="$(( ${#mast_str} - toot_length + 496 ))"
   mast_str="${mast_str:0:$new_length}..."
   "${s6wrap[@]}" echo "[WARNING] Mastodon Notification Truncated: it was $(( toot_length - 499)) characters too long"
fi

# Now we have the notification string, lets upload an image if one exists:

# If the image still exists, then upload it to Mastodon:
if [[ -f "$IMAGECACHE/${VESSELS[$1:mmsi]}.jpg" ]]
then
    response="$(curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "${MASTODON_SERVER}/api/v1/media" --form file="@$IMAGECACHE/${VESSELS[$1:mmsi]}.jpg")"
    [[ "$(jq '.id' <<< "${response}" | xargs)" != "null" ]] && mast_id="$(jq '.id' <<< "${response}" | xargs)" || mast_id=""
    if [[ -n "${mast_id}" ]]; then media_id="-F media_ids[]=${mast_id} "; fi
    "${s6wrap[@]}" echo "[INFO] image for ${VESSELS[$1:mmsi]} (${VESSELS[$1:shipname]}) uploaded to Mastodon"
else
    "${s6wrap[@]}" echo "[WARNING] no image available for ${VESSELS[$1:mmsi]} (${VESSELS[$1:shipname]})"
fi

# If a screenshot exists, then upload it to Mastodon:
if [[ -f "${IMAGECACHE}/screenshots/${VESSELS[$1:mmsi]}.jpg" ]]
then
    response="$(curl -s -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -H "Content-Type: multipart/form-data" -X POST "${MASTODON_SERVER}/api/v1/media" --form file="@${IMAGECACHE}/screenshots/${VESSELS[$1:mmsi]}.jpg")"
    [[ "$(jq '.id' <<< "${response}" | xargs)" != "null" ]] && mast_id="$(jq '.id' <<< "${response}" | xargs)" || mast_id=""
    if [[ -n "${mast_id}" ]]; then media_id+="-F media_ids[]=${mast_id} "; fi
fi

# Now send the toot:
#shellcheck disable=SC2086

response="$(curl -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" -s "${MASTODON_SERVER}/api/v1/statuses" -X POST ${media_id} -F "status=${mast_str}" -F "language=${LANGUAGE:0:2}" -F "visibility=${MASTODON_POST_VISIBILITY}")"
# check if there was an error
if [[ "$(jq '.error' <<< "${response}"|xargs)" == "null" ]]
then
    "${s6wrap[@]}" echo "[INFO] Mastodon post for ${VESSELS[$1:mmsi]} (${VESSELS[$1:shipname]}) generated successfully with visibility ${MASTODON_POST_VISIBILITY}. Mastodon post available at: $(jq '.url' <<< "${response}"|xargs)"
    if [[ -z "${VESSELS[$1:notification:last]}" ]]; then "${s6wrap[@]}" echo -n "[INFO] #NEW "; fi
    #shellcheck disable=SC2154
if     [[ "${notify_timing}" == "true" ]] && [[ -n "${VESSELS[$1:notification:last]}" ]]; then echo -n "#OLD "; fi
    if [[ "${notify_distance}" == "true" ]]; then echo -n "#ONTHEMOVE"; fi
    echo ""

    # Update the Assoc Array with the latest values:
    VESSELS[$1:notification:lat]="${VESSELS[$1:lat]}"
    VESSELS[$1:notification:lon]="${VESSELS[$1:lon]}"
    VESSELS[$1:notification:last]="$(date +%s)"
    VESSELS[$1:notification:mastodon]="true"

    source /usr/share/vesselalert/save_databases
else
    "${s6wrap[@]}" echo "[ERROR] Mastodon post error for ${VESSELS[$1:mmsi]} (${VESSELS[$1:shipname]}). Mastodon returned this error: ${response}"
fi
