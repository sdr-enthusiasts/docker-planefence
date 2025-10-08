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
# This script sends a BlueSky notification

source /scripts/common

VESSELDBFILE="${VESSELDBFILE:-/data/vessel.db}"
# load the databases:

source "/usr/share/vesselalert/load_databases"
IMAGECACHE="${VESSELDBFILE%/*}/imagecache"

if [[ -z "$1" ]]
then
    "${s6wrap[@]}" echo "[ERROR] $0 - send a BlueSky notification for a specific MMSI"
    "${s6wrap[@]}" echo "[ERROR] Usage: $0 mmsi"
    exit 1
else
    "${s6wrap[@]}" echo "[INFO] Attempting BlueSky notification for $1 (${VESSELS[$1:shipname]})"
fi

if [[ "${*:2}" =~ .*tropoalert=.* ]]
then
    notify_tropo=true
else
    unset notify_tropo
fi
if [[ -z "${BLUESKY_APP_PASSWORD}" ]] || [[ -z "$BLUESKY_HANDLE" ]]; then
    "${s6wrap[@]}" echo "[ERROR] BLUESKY_APP_PASSWORD or BLUESKY_HANDLE not defined. Cannot send a BlueSky notification"
    exit 1
fi

# First do some clean up
if [[ -n "${VESSELS[$1:shipname]}" ]]; then
    VESSELS[$1:shipname]="$(sed \
            -e 's|["'\''.]||g' \
            -e 's|[^A-Z0-9,\.\-]\+|_|g' \
            -e 's|_,|,|g' \
         <<< "${VESSELS[$1:shipname]}")"

fi
if [[ -n "${VESSELS[$1:destination]}" ]]; then
    VESSELS[$1:destination]="$(sed \
            -e 's|["'\''.]||g' \
            -e 's|[^A-Z0-9,\.\-\<\>]\+|_|g' \
            -e 's|_,|,|g' \
         <<< "${VESSELS[$1:destination]}")"
fi

# Build the message - create notification string
links=""
if chk_enabled "${BLUESKY_LINK_AISCATCHER:-on}"; then links+="https://aiscatcher.org/ship/details/${VESSELS[$1:mmsi]}\n"; fi
if chk_enabled "$BLUESKY_LINK_SHIPXPLORER"; then links+="https://www.shipxplorer.com/data/vessels/IMO-MMSI-${VESSELS[$1:mmsi]}\n"; fi
if chk_enabled "$BLUESKY_LINK_MARINETRAFFIC"; then links+="https://www.marinetraffic.com/en/ais/details/ships/${VESSELS[$1:mmsi]}\n"; fi
if chk_enabled "$BLUESKY_LINK_VESSELFINDER"; then links+="https://www.vesselfinder.com/vessels/details/${VESSELS[$1:mmsi]}\n"; fi

unset bsky_str

if [[ -n "$notify_tropo" ]]; then
    bsky_str="#${NOTIF_TERM[TROPOMAXDIST]} = $(printf "%.1f" "${VESSELS[$1:distance]}") nm\n"
fi

bsky_str+="#VesselAlert"
if [[ "${NOTIF_TERM[SHIP]}" != "Ship" ]]; then bsky_str+=" #${NOTIF_TERM[SHIP]}"; fi
if [[ -z "${VESSELS[$1:notification:last]}" ]]; then bsky_str+=" ${NOTIF_TERM[NEW]}"; fi
if [[ "${notify_distance}" == "true" ]]; then bsky_str+=" #${NOTIF_TERM[ONTHEMOVE]}"; fi
bsky_str+="\n"
if [[ -n "${VESSELS[$1:shipname]}" ]]; then bsky_str+="${NOTIF_TERM[SHIPNAME]}: #${VESSELS[$1:shipname]}\n"; fi
if [[ -n "${VESSELS[$1:mmsi]}" ]]; then bsky_str+="#MMSI: #${VESSELS[$1:mmsi]}\n"; fi
if [[ -n "${VESSELS[$1:callsign]}" ]]; then bsky_str+="${NOTIF_TERM[CALLSIGN]}: #${VESSELS[$1:callsign]}\n"; fi
if [[ -n "${VESSELS[$1:shiptype]}" ]] && [[ -n "${SHIPTYPE[${VESSELS[$1:shiptype]}]}" ]]; then bsky_str+="${NOTIF_TERM[SHIPTYPE]}: ${SHIPTYPE[${VESSELS[$1:shiptype]}]}\n"; fi

if [[ -n "${VESSELS[$1:country]}" ]]; then bsky_str+="#${NOTIF_TERM[FLAG]}: #${COUNTRY[${VESSELS[$1:country]}]}\n"; fi
# bsky_str+="${NOTIF_TERM[MSGS_RECVD]}: ${VESSELS[$1:count]}\n"
bsky_str+="${NOTIF_TERM[SEEN_ON]}: $(date -d @$(( $(date +%s) - ${VESSELS[$1:last_signal]} )) +"%d-%b-%Y %H:%M:%S %Z")\n"

if [[ -n "${VESSELS[$1:status]}" ]] && [[ -n "${SHIPSTATUS[${VESSELS[$1:status]}]}" ]]; then bsky_str+="${NOTIF_TERM[STATUS]}: ${SHIPSTATUS[${VESSELS[$1:status]}]}\n"; fi
if [[ -n "${VESSELS[$1:speed]}" ]] && [[ "${VESSELS[$1:speed]}" != "0" ]] && [[ "${VESSELS[$1:speed]}" != "null" ]]; then bsky_str+="${NOTIF_TERM[SPEED]}: $(printf "%.1f" "${VESSELS[$1:speed]}") kts\n"; fi
if [[ -n "${VESSELS[$1:heading]}" ]] && [[ "${VESSELS[$1:heading]}" != "0" ]] && [[ "${VESSELS[$1:heading]}" != "null" ]]; then bsky_str+="${NOTIF_TERM[HEADING]}: ${VESSELS[$1:heading]} deg\n"; fi
if chk_enabled "$USE_FRIENDLY_DESTINATION" && [[ -n "${VESSELS[$1:destination:friendly]}" ]]; then
    bsky_str+="${NOTIF_TERM[DESTINATION]}: ${VESSELS[$1:destination:friendly]}\n"
elif [[ -n "${VESSELS[$1:destination]}" ]]; then bsky_str+="${NOTIF_TERM[DESTINATION]}: ${VESSELS[$1:destination]}\n"; fi

if [[ -n "${VESSELS[$1:lat]}" ]] && [[ -n "${VESSELS[$1:lon]}" ]] && [[ -n "$LAT" ]] && [[ -n "$LON" ]]; then
    distance="$(bc -l <<< "scale=1; $(distance "${VESSELS[$1:lat]}" "${VESSELS[$1:lon]}" "$LAT" "$LON") / 1")"
    bsky_str+="${NOTIF_TERM[DISTANCE]}: $distance nm\n"
fi

bsky_str+="${NOTIF_TERM[SIGNAL]} #RSSI: $(printf "%.1f dBFS" "${VESSELS[$1:level]}")\n"

if [[ -n "${NOTIFICATION_MAPURL}" ]] && [[ "${NOTIFICATION_MAPURL:0:4}" != "http" ]]; then bsky_str+="${AIS_URL}?mmsi=${VESSELS[$1:mmsi]}\n"; fi
if [[ -n "${NOTIFICATION_MAPURL}" ]] && [[ "${NOTIFICATION_MAPURL:0:4}" == "http" ]]; then bsky_str+="${NOTIFICATION_MAPURL}?mmsi=${VESSELS[$1:mmsi]}\n"; fi
if [[ -n "${links}" ]]; then bsky_str+="${links}\n"; fi

bsky_str+="\n"

if [[ -n "$BLUESKY_CUSTOM_FIELD" ]]; then bsky_str+="$BLUESKY_CUSTOM_FIELD\n"; fi

bsky_str+="#${NOTIF_TERM[SHIP]} #AIS #VesselAlert © #kx1t https://sdr-e.com/docker-vesselalert"

#shellcheck disable=SC2001
bsky_str="$(sed -e 's|\\n|\n|g' <<< "$bsky_str")"

# Collect images to be sent to BlueSky:
img_str=()

if [[ -f "$IMAGECACHE/${VESSELS[$1:mmsi]}.jpg" ]]; then img_str+=("$IMAGECACHE/${VESSELS[$1:mmsi]}.jpg"); fi
if [[ -f "${IMAGECACHE}/screenshots/${VESSELS[$1:mmsi]}.jpg" ]]; then img_str+=("${IMAGECACHE}/screenshots/${VESSELS[$1:mmsi]}.jpg"); fi

# Now send the BSky Notification:
#shellcheck disable=SC2086

if "${s6wrap[@]}" /scripts/post2bsky.sh "$bsky_str" "${img_str[@]}"; then
    # Update the Assoc Array with the latest values:
    VESSELS[$1:notification:lat]="${VESSELS[$1:lat]}"
    VESSELS[$1:notification:lon]="${VESSELS[$1:lon]}"
    VESSELS[$1:notification:last]="$(date +%s)"
    if [[ -f /tmp/bsky-notif.txt ]]; then
        VESSELS[$1:notification:bluesky]="$(</tmp/bsky-notif.txt)"
        rm -f /tmp/bsky-notif.txt
    else
        VESSELS[$1:notification:bluesky]="true"
    fi
    source /usr/share/vesselalert/save_databases
fi
