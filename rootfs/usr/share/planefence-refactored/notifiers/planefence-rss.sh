#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1091,SC2154
# planefence-rss.sh
# A script to generate RSS feeds from Planefence CSV files
#
# Usage: ./planefence-rss.sh 
#
# This script is distributed as part of the Planefence package and is dependent
# on that package for its execution.
#
# Based on a script provided by @randomrobbie - https://github.com/sdr-enthusiasts/docker-planefence/issues/211
# Copyright 2024-2025 @randomrobbie, Ramon F. Kolb (kx1t), and contributors - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#

# Set paths - use the same as planefence.sh
source "/usr/share/planefence/planefence.conf"

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
HTMLDIR=/tmp
OUTFILEDIR=/tmp
set -eo pipefail
DEBUG=true

# Get today's date in yymmdd format
TODAY=$(date --date="today" '+%y%m%d')

# Site configuration - you can modify these
SITE_TITLE="Planefence Aircraft Detections"
SITE_DESC="Recent aircraft detected within range of our ADS-B receiver"
SITE_LINK="${RSS_SITELINK}"  # Replace with your actual URL
SITE_IMAGE="${RSS_FAVICONLINK}"  # Optional site image

#  If there is a site link, make sure it ends with a /
if [[ -n "$SITE_LINK" ]] && [[ "${SITE_LINK: -1}" != "/" ]]; then SITE_LINK="${SITE_LINK}/"; fi

# define the RECORDSFILE with the records assoc array
RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"
source /scripts/common



# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------


debug_print() {
    local currenttime
    if [[ -z "$execstarttime" ]]; then
      execstarttime="$(date +%s.%3N)"
      execlaststeptime="$execstarttime"
    fi
    currenttime="$(date +%s.%3N)"
    if chk_enabled "$DEBUG"; then 
      "${s6wrap[@]}" printf "[DEBUG] %s (%s secs, total time elapsed %s secs)\n" "$1" "$(bc -l <<< "$currenttime - $execlaststeptime")" "$(bc -l <<< "$currenttime - $execstarttime")" >&2
    fi
    execlaststeptime="$currenttime"
}

# Function to encode special characters for XML
xml_encode() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

# Function to generate RSS feed for a specific CSV file
generate_rss() {
    local rec_file="$1"
    local rss_file="$OUTFILEDIR/planefence-$TODAY.rss"
    
    # Create RSS header
    cat > "$rss_file" <<EOF
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
    <title>$(xml_encode "$SITE_TITLE - $TODAY")</title>
    <description>$(xml_encode "$SITE_DESC")</description>
    <link>$(xml_encode "${SITE_LINK:-.}")</link>
    <lastBuildDate>$(date -R)</lastBuildDate>
    ${SITE_IMAGE:+<image>
        <url>$(xml_encode "$SITE_IMAGE")</url>
        <title>$(xml_encode "$SITE_TITLE")</title>
        <link>$SITE_LINK</link>
    </image>}
    <atom:link href="$(xml_encode "${SITE_LINK}${rss_file##*/}")" rel="self" type="application/rss+xml" />
EOF

    # Process the records file in reverse order (newest first)
    if [[ -f "$rec_file" ]]; then
        # shellcheck disable=SC1090
        source "$rec_file"  # read the records array from file

        # Get DISTANCE unit:
        DISTUNIT="mi"
        ALTUNIT="ft"
        if [[ -f "$SOCKETCONFIG" ]]; then
            case "$(grep "^distanceunit=" "$SOCKETCONFIG" |sed "s/distanceunit=//g")" in
                nauticalmile)
                DISTUNIT="nm"
                ;;
                kilometer)
                DISTUNIT="km"
                ;;
                mile)
                DISTUNIT="mi"
                ;;
                meter)
                DISTUNIT="m"
            esac
            case "$(grep "^altitudeunit=" "$SOCKETCONFIG" |sed "s/altitudeunit=//g")" in
                feet)
                ALTUNIT="ft"
                ;;
                meter)
                ALTUNIT="m"
            esac
        fi

        # Now loop through the detected aircraft:
        for ((idx=0; idx <= records[maxindex]; idx++)); do

            if [[ -z "${records["$idx":icao]}" ]]; then continue; fi
            
            # Create title and description
            TITLE="Aircraft ${records["$idx":callsign]:-${records["$idx":icao]}} detected"
            DESC="Aircraft ${records["$idx":callsign]:-${records["$idx":icao]}} was detected within ${records["$idx":distance]} ${DISTUNIT} of the receiver"
            DESC="${DESC} at altitude ${records["$idx":altitude]} ${ALTUNIT} from $(date -d "@${records["$idx":firstseen]}") to $(date -d "@${records["$idx":lastseen]}")"
            
            # Add noise data if available
            if [[ -n "${records["$idx":sound_peak]}" ]]; then
                DESC="${DESC}, with peak noise level of ${records["$idx":sound_peak]} dBFS"
            fi
            
            # Create item link - use the tracking URL if available
            ITEM_LINK="${records["$idx":map_link]:-$SITE_LINK}"
            
            # Calculate pub date from LASTSEEN 
            PUBDATE=$(date -R -d "@${records["$idx":lastseen]}")
            
            # Write RSS item
            cat >> "$rss_file" <<EOF
    <item>
        <title>$(xml_encode "$TITLE")</title>
        <description>$(xml_encode "$DESC")</description>
        <link>$ITEM_LINK</link>
        <guid isPermaLink="false">${records["$idx":icao]}-${records["$idx":firstseen]}</guid>
        <pubDate>$PUBDATE</pubDate>
    </item>
EOF
        done
    fi

    # Close the RSS feed
    cat >> "$rss_file" <<EOF
</channel>
</rss>
EOF

    # Set proper permissions
    chmod u=rw,go=r "$rss_file"
    debug_print "RSS feed generated at $rss_file"
}


debug_print "Starting generation of RSS feed"

# Create/update symlink for today's feed
if [[ -f "$RECORDSFILE" ]]; then
    generate_rss "$RECORDSFILE"
    
    # Create/update the symlink
    ln -sf "planefence-$TODAY.rss" "$OUTFILEDIR/planefence.rss"
    # "${s6wrap[@]}" echo "Updated symlink planefence.rss to point to today's feed"
fi
