#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1091,SC2154,SC2034
# send_rss.sh
# A script to generate RSS feeds from Planefence CSV files
#
# Usage: ./send_rss.sh 
#
# This script is distributed as part of the Planefence package and is dependent
# on that package for its execution.
#
# Based on a script provided by @randomrobbie - https://github.com/sdr-enthusiasts/docker-planefence/issues/211
# Copyright 2024-2026 @randomrobbie, Ramon F. Kolb (kx1t), and contributors - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#

# Set paths - use the same as planefence.sh
source "/usr/share/planefence/plane-alert.conf"
source /scripts/pf-common

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
set -eo pipefail
#DEBUG=true

# Get today's date in yymmdd format
TODAY=$(date --date="today" '+%y%m%d')

# Site configuration - you can modify these
SITE_TITLE="Plane-Alert Aircraft Detections"
SITE_DESC="Interesting aircraft detected within range of our ADS-B receiver"
SITE_LINK="${RSS_SITELINK}"  # Base URL for your site
SITE_IMAGE="${RSS_FAVICONLINK}"  # Optional site image
#rss_file="${OUTFILEDIR:-/usr/share/planefence/html}/plane-alert-$TODAY.rss"
rss_file="/run/planefence/plane-alert-$TODAY.rss"
OUTFILEDIR="/usr/share/planefence/html"

#  If there is a site link, make sure it ends with a /
if [[ -n "$SITE_LINK" ]] && [[ "${SITE_LINK: -1}" != "/" ]]; then SITE_LINK="${SITE_LINK}/"; fi

# define the RECORDSFILE with the records assoc array
source /scripts/pf-common

# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------

# Faster xml escape using pure-bash (no sed/subshell). Handles & < > " '
xml_escape() {
  local s=${1-}
  # Short-circuit for empty
  [[ -z "$s" ]] && { printf '%s' "$s"; return 0; }
  # Use parameter expansion to replace characters
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  s=${s//\"/&quot;}
  s=${s//\'/&apos;}
  printf '%s' "$s"
}

# Function to generate RSS feed for a specific CSV file (optimized)
generate_rss() {
  READ_RECORDS

  # Precompute some values to avoid repeated expansions
  local site_link="${SITE_LINK}"
  local feed_link
  local site_title="${SITE_TITLE:-Plane-Alert Aircraft Detections}"
  local site_desc="${SITE_DESC:-Interesting aircraft detected within range of our ADS-B receiver}"
  local site_image="$SITE_IMAGE"
  local last_build_date
  last_build_date=$(date -R)

  # Ensure site_link has trailing slash if it's set (defensive check)
  if [[ -n "$site_link" ]] && [[ "${site_link: -1}" != "/" ]]; then
    site_link="${site_link}/"
  fi

  # Always derive FEED_LINK from SITE_LINK
  # If SITE_LINK is not set, use relative path from docroot
  if [[ -n "$site_link" ]]; then
    # Construct full URL: SITE_LINK + filename
    feed_link="${site_link}plane-alert.rss"
  else
    # Default to docroot (relative path) - use "/" for channel link
    site_link="/"
    feed_link="/plane-alert.rss"
  fi

  # Write header once using printf to avoid many subshells
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" ?>'
    printf '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
    printf '<channel>\n'
    printf '<title>%s</title>\n' "$(xml_escape "$site_title - $TODAY")"
    printf '<description>%s</description>\n' "$(xml_escape "$site_desc")"
    printf '<link>%s</link>\n' "$(xml_escape "$site_link")"
    printf '<lastBuildDate>%s</lastBuildDate>\n' "$last_build_date"
    if [[ -n "$site_image" ]]; then
      printf '<image>\n'
      printf '  <url>%s</url>\n' "$(xml_escape "$site_image")"
      printf '  <title>%s</title>\n' "$(xml_escape "$site_title")"
      printf '  <link>%s</link>\n' "$(xml_escape "$site_link")"
      printf '</image>\n'
    fi
    printf '<atom:link href="%s" rel="self" type="application/rss+xml" />\n' "$(xml_escape "$feed_link")"
  } > "$rss_file"

  # Cache max index
  local maxidx
  maxidx=${pa_records[maxindex]:--1}
  local idx=0

  # Loop numeric indices; cache commonly used fields into locals once per iteration
  for (( idx=0; idx<=maxidx; idx++ )); do
    # Access associative array keys minimally
    local icao key_callsign callsign distance_value distance_unit alt_val firstseen lastseen sound_peak link_map ITEM_LINK

    icao=${pa_records["$idx":icao]:-}
    [[ -n "$icao" ]] || continue

    callsign=${pa_records["$idx":callsign]:-}
    key_callsign=${callsign:-$icao}
    distance_value=${pa_records["$idx":distance:value]:-}
    distance_unit=${pa_records["$idx":distance:unit]:-}
    alt_val=${pa_records["$idx":altitude:value]:-}
    firstseen=${pa_records["$idx":time:firstseen]:-}
    lastseen=${pa_records["$idx":time:lastseen]:-}
    sound_peak=${pa_records["$idx":sound:peak]:-}
    link_map=${pa_records["$idx":link:map]:-}

    # Build title and description
    local title desc pubdate guid
    title="Aircraft $key_callsign detected"
    desc="Aircraft $key_callsign was detected within $distance_value $distance_unit of the receiver"
    desc+=" at altitude $alt_val ${ALTUNIT:-m} from $(date -d "@$firstseen" '+%c') to $(date -d "@$lastseen" '+%c')"
    if [[ -n "$sound_peak" ]]; then
      desc+=", with peak noise level of $sound_peak dBFS"
    fi

    pubdate=$(date -R -d "@$lastseen")
    guid="$icao-$firstseen"
    ITEM_LINK=${link_map:-$site_link}

    # Append item (escape title and description once)
    {
      printf '<item>\n'
      printf '  <title>%s</title>\n' "$(xml_escape "$title")"
      printf '  <description>%s</description>\n' "$(xml_escape "$desc")"
      printf '  <link>%s</link>\n' "$(xml_escape "$ITEM_LINK")"
      printf '  <guid isPermaLink="false">%s</guid>\n' "$guid"
      printf '  <pubDate>%s</pubDate>\n' "$pubdate"
      printf '</item>\n'
    } >> "$rss_file"
  done

  # Close feed
  {
    printf '</channel>\n'
    printf '</rss>\n'
  } >> "$rss_file"

  chmod u=rw,go=r "$rss_file"
}

log_print DEBUG "Hello. Starting generation of RSS feed"

# Create/update symlink for today's feed
if generate_rss; then
  ln -sf "$rss_file" "$OUTFILEDIR/plane-alert.rss"
  log_print DEBUG "RSS feed generated at $rss_file"
else
  log_print ERR "RSS feed generation failed!"
fi
