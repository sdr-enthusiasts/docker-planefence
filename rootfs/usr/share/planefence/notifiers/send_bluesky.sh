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
# This script sends a Bsky notification
shopt -s extglob

source /scripts/pf-common
source /usr/share/planefence/planefence.conf

# shellcheck disable=SC2034
DEBUG=true
declare -a INDEX STALE

log_print INFO "Hello. Starting Bsky notification run"

# ----------------------
# Functions
# ----------------------

# Fast builder: outputs INDEX (eligible) and STALE (stale) as numeric id arrays.
# Assumes:
#   - records[...] assoc with keys: "<id>:lastseen|bsky:notified|complete|screenshot:checked"
#   - CONTAINERSTARTTIME (epoch, integer)
#   - screenshots (0/1 or truthy string)
build_index_and_stale() {
  local -n _INDEX=$1
  local -n _STALE=$2
  _INDEX=(); _STALE=()

  # Optional numeric ceiling from records[maxindex]
  local MAXIDX
  MAXIDX=${records[maxindex]}

  # Capture gawk output once, then demux without subshells
  local out
  out="$(
    {
      local k id field
      for k in "${!records[@]}"; do
        [[ $k == +([0-9]):* ]] || continue
        id=${k%%:*}
        [[ -n "$MAXIDX" && $id -gt $MAXIDX ]] && continue
        field=${k#*:}
        # Only pass fields we care about to reduce awk work
        case $field in
          lastseen|bsky:notified|complete|screenshot:checked)
            printf '%s\t%s\t%s\n' "$id" "$field" "${records[$k]}"
            ;;
        esac
      done
    } | gawk -v CST="${CONTAINERSTARTTIME:-0}" -v SS="${screenshots:-0}" '
      BEGIN { FS="\t" }
      {
        id=$1; key=$2; val=$3
        if (key=="lastseen")                 { lastseen[id]=val+0; ids[id]=1 }
        else if (key=="bsky:notified")    notified[id]=val
        else if (key=="complete")            complete[id]=val
        else if (key=="screenshot:checked")  schecked[id]=val
      }
      END {        
        CSTN = CST+0
        # Evaluate only ids that have lastseen
        for (id in ids) {
          n  = (id in notified)? notified[id] : ""
          ls = lastseen[id]
          # stale first
          if (ls < CSTN && n == "") { stale[id]=1; continue }
          # eligibility checks
          c  = (id in complete)? complete[id] : ""
          if (!enabled(c)) continue
          if (enabled(n)) continue
          if (n=="error") continue
          if (SS && !enabled((id in schecked)? schecked[id] : "")) continue
          ok[id]=1
        }
        # Print lists (tagged), numerically sorted
        ni=asorti(ok, oi, "@ind_num_asc"); for (i=1;i<=ni;i++) printf "I\t%s\n", oi[i]
        ns=asorti(stale, os, "@ind_num_asc"); for (i=1;i<=ns;i++) printf "S\t%s\n", os[i]
      }
      function enabled(x, y){ y=tolower(x); return (x!="" && x!="0" && y!="false" && y!="no") }
    '
  )"

  local tag id
  while IFS=$'\t' read -r tag id; do
    [[ -z "$tag" ]] && continue
    if [[ "$tag" == I ]]; then _INDEX+=("$id"); else _STALE+=("$id"); fi
  done <<< "$out"
}


# Load a bunch of stuff and determine if we should notify

if [[ -z "$BLUESKY_HANDLE" || -z "$BLUESKY_APP_PASSWORD" ]]; then
  log_print INFO "Bluesky notifications not enabled. Exiting."
  exit
fi

if [[ -f "/usr/share/planefence/notifiers/bluesky.template" ]]; then
  template="$(</usr/share/planefence/notifiers/bluesky.template)"
else
  log_print ERR "No Bluesky template found at /usr/share/planefence/notifiers/bluesky.template. Aborting."
  exit 1
fi

if CHK_SCREENSHOT_ENABLED; then
  screenshots=1
else
  screenshots=0
fi

debug_print "Reading records for Bsky notification"

READ_RECORDS

debug_print "Getting indices of records ready for Bsky notification and stale records"
build_index_and_stale INDEX STALE

if (( ${#INDEX[@]} )); then
  debug_print "Records ready for Bsky notification: ${INDEX[*]}"
else
  debug_print "No records ready for Bsky notification"
fi
if (( ${#STALE[@]} )); then
  debug_print "Stale records (no notification will be sent): ${STALE[*]}"
else
  debug_print "No stale records"
fi
if (( ${#INDEX[@]} == 0 && ${#STALE[@]} == 0 )); then
  log_print INFO "No records eligible for Bsky notification. Exiting."
  exit 0
fi

# deal with stale records first
for idx in "${STALE[@]}"; do
  records["$idx":bsky:notified]=stale
done

template_clean="$(</usr/share/planefence/notifiers/bluesky.template)"

for idx in "${INDEX[@]}"; do
  debug_print "Preparing Bsky notification for ${records["$idx":tail]}"

  # reset the template cleanly after each notification
  template="$template_clean"

  # Set strings:
  squawk="${records["$idx:squawk"]}"
  if [[ -n "$squawk" ]]; then
    template="$(template_replace "||SQUAWK||" "#Squawk: $squawk$'\n'" "$template")"
    if [[ "$squawk" =~ ^(7500|7600|7700)$ ]]; then
      template="$(template_replace "||EMERGENCY||" "#Emergency: #${records["$idx:squawk:description"]} " "$template")"
    else
      template="$(template_replace "||EMERGENCY||" "" "$template")"
    fi
  else
    template="$(template_replace "||SQUAWK||" "" "$template")"
    template="$(template_replace "||EMERGENCY||" "" "$template")"
  fi
  
  template="$(template_replace "||ICAO||" "${records["$idx:icao"]}" "$template")"
  template="$(template_replace "||CALLSIGN||" "${records["$idx:callsign"]}" "$template")"
  template="$(template_replace "||TAIL||" "${records["$idx:tail"]}" "$template")"
  template="$(template_replace "||TYPE||" "${records["$idx:type"]}" "$template")"
  if [[ "${records["$idx:route"]}" != "n/a" ]]; then 
    template="$(template_replace "||ROUTE||" "#${records["$idx:route"]}" "$template")"
  else
    template="$(template_replace "||ROUTE||" "" "$template")"
  fi
  template="$(template_replace "||TIME||" "$(date -d "@${records["$idx":time_at_mindist]}" "+${NOTIF_DATEFORMAT:-%H:%M:%S %Z}")" "$template")"
  template="$(template_replace "||ALT||" "${records["$idx:altitude"]} $ALTUNIT" "$template")"
  template="$(template_replace "||DIST||" "${records["$idx:distance"]} $DISTUNIT (${records["$idx":angle]}°)" "$template")"
  if [[ -n ${records["$idx":sound:loudness]} ]]; then
    template="$(template_replace "||LOUDNESS||" "Loudness: ${records["$idx":sound:loudness]} dB" "$template")"
  else
    template="$(template_replace "||LOUDNESS||" "" "$template")"
  fi
  template="$(template_replace "||ATTRIB||" "$ATTRIB " "$template")"

  links="${records["$idx:map:link"]}${records["$idx:map:link"]:+ }"
  links+="${records["$idx:fa:link"]}${records["$idx:fa:link"]:+ }"
  links+="${records["$idx:faa:link"]}"
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
  debug_print "Posting to Bsky: ${records["$idx:tail"]} (${records["$idx:icao"]})"
echo "$template" > /tmp/bsky.tmplt

  # shellcheck disable=SC2068,SC2086
  if posturl="$(/scripts/post2bsky.sh $template ${img_array[@]})" && [[ "${posturl:0:4}" == "http" ]]; then
    log_print INFO "Bsky notification successful for ${records["$idx:tail"]} (${records["$idx:icao"]}): $posturl"
    records["$idx":bsky:notified]=true
    records["$idx":bsky:link]="$posturl"
  else
    log_print ERR "Bsky notification failed for ${records["$idx:tail"]} (${records["$idx:icao"]})"
    log_print ERR "Bsky notification error details: $posturl"
    records["$idx":bsky:notified]="error"
  fi
done

# Save the records again
debug_print "Saving records after Bsky notifications"
WRITE_RECORDS
log_print INFO "Bsky notifications run completed."
