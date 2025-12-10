#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2164,SC1090,SC2154,SC1091
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
# This script sends a Mastodonnotification
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/planefence.conf

exec 2>/dev/stderr  # we need to do this because stderr is redirected to &1 in /scripts/pfcommon <-- /scripts/common
                    # Normally this isn't an issue, but post2bsky is called from another script, and we don't want to polute the returns with info text


# shellcheck disable=SC2034
DEBUG=false
declare -a INDEX STALE
declare -a link

#SPACE=$'\x1F'   # "special" space
SPACE="_"   # Mastodon does not allow special spaces in hashtags, so use underscore instead

log_print INFO "Hello. Starting Mastodon notification run"


# Load a bunch of stuff and determine if we should notify

if [[ -z "$MASTODON_ACCESS_TOKEN" || -z "$MASTODON_SERVER" ]]; then
  log_print INFO "Mastodon notifications not enabled. Exiting."
  exit
fi

if [[ -f "/usr/share/planefence/notifiers/mastodon.pf.template" ]]; then
  template_clean="$(</usr/share/planefence/notifiers/mastodon.pf.template)"
else
  log_print ERR "No Mastodon template found at /usr/share/planefence/notifiers/mastodon.pf.template. Aborting."
  exit 1
fi

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  # shellcheck disable=SC2034
  screenshots=0
fi

log_print DEBUG "Reading records for Mastodon notification"

READ_RECORDS

log_print DEBUG "Getting indices of records ready for Mastodon notification and stale records"
build_index_and_stale INDEX STALE mastodon pf

if (( ${#INDEX[@]} )); then
  log_print DEBUG "Records ready for Mastodon notification: ${INDEX[*]}"
else
  log_print DEBUG "No records ready for Mastodon notification"
fi
if (( ${#STALE[@]} )); then
  log_print DEBUG "Stale records (no notification will be sent): ${STALE[*]}"
else
  log_print DEBUG "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print INFO "No records eligible for Mastodon notification. Exiting."
  exit 0
fi

for idx in "${INDEX[@]}"; do
  log_print DEBUG "Preparing Mastodon notification for ${records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  squawk="${records["$idx":squawk:value]}"
  if [[ -n "$squawk" ]]; then
    template="$(template_replace "||SQUAWK||" "#Squawk: $squawk\n" "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      template="$(template_replace "||EMERGENCY||" "#Emergency: #${records["$idx":squawk:description]// /${SPACE}} " "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi
  if [[ -n "${records["$idx":owner]}" ]]; then
    template="$(template_replace "||OWNER||" "Owner: #${records["$idx":owner]// /${SPACE}}" "$template")" # replace spaces in the owner name by the special ${SPACE} to keep them together in a hashtag
  else
    template="$(template_replace "||OWNER||" "" "$template")"
  fi
  template="$(template_replace "||ICAO||" "${records["$idx":icao]}" "$template")"
  template="$(template_replace "||CALLSIGN||" "${records["$idx":callsign]//-/}" "$template")"
  template="$(template_replace "||TAIL||" "$([[ "${records["$idx":tail]//-/}" != "${records["$idx":callsign]//-/}" ]] && echo "#${records["$idx":tail]//-/}" || true)" "$template")"
  template="$(template_replace "||TYPE||" "${records["$idx":type]}" "$template")"
  if [[ "${records["$idx":route]}" != "n/a" ]]; then 
    template="$(template_replace "||ROUTE||" "#${records["$idx":route]}" "$template")"
  else
    template="$(template_replace "||ROUTE||" "" "$template")"
  fi
  template="$(template_replace "||TIME||" "$(date -d "@${records["$idx":time:time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")" "$template")"
  template="$(template_replace "||ALT||" "${records["$idx":altitude:value]} $ALTUNIT" "$template")"
  template="$(template_replace "||DIST||" "${records["$idx":distance:value]} $DISTUNIT (${records["$idx":angle:value]}° ${records["$idx":angle:name]})" "$template")"
  if [[ -n ${records["$idx":sound:loudness]} ]]; then
    template="$(template_replace "||LOUDNESS||" "Loudness: ${records["$idx":sound:loudness]} dB" "$template")"
  else
    template="$(template_replace "||LOUDNESS||" "" "$template")"
  fi
  template="$(template_replace "||ATTRIB||" "$ATTRIB " "$template")"

  links="${records["$idx":link:map]}${records["$idx":link:map]:+ }"
  links+="${records["$idx":link:fa]}${records["$idx":link:fa]:+ }"
  links+="${records["$idx":link:faa]}"
  template="$(template_replace "||LINKS||" "$links" "$template")"

  # Handle images
  img_array=()
  if [[ -n "${records["$idx":image:file]}" && -f "${records["$idx":image:file]}" ]]; then
    img_array+=("${records["$idx":image:file]}")
  fi
  if [[ -n "${records["$idx":screenshot:file]}" && -f "${records["$idx":screenshot:file]}" ]]; then
    img_array+=("${records["$idx":screenshot:file]}")
  fi

  # Post to Bsky
  log_print DEBUG "Posting to Bsky: ${records["$idx":tail]} (${records["$idx":icao]})"

  # shellcheck disable=SC2068,SC2086
  posturl="$(/scripts/post2mastodon.sh pf "$template" ${img_array[@]})" || true
  if url="$(extract_url "$posturl")"; then
    log_print INFO "Mastodon notification successful for #$idx ${records["$idx":tail]} (${records["$idx":icao]}): $url"
  else
    log_print ERR "Mastodon notification failed for #$idx ${records["$idx":tail]} (${records["$idx":icao]})"
    log_print ERR "Mastodon notification error details: $posturl"
  fi
  link[idx]="$url"
done

# read, update, and thensave the records:
log_print DEBUG "Updating records after Mastodon notifications"
LOCK_RECORDS
READ_RECORDS ignore-lock

for idx in "${STALE[@]}"; do
  records["$idx":mastodon:notified]="stale"
done
for idx in "${!link[@]}"; do
  if [[ "${link[idx]:0:4}" == "http" ]]; then
    records["$idx":mastodon:notified]=true
    records["$idx":mastodon:link]="${link[idx]}"
  else
    records["$idx":mastodon:notified]="error"
  fi
done

# Save the records again
log_print DEBUG "Saving records..."
WRITE_RECORDS ignore-lock
log_print INFO "Mastodon notifications run completed."
