#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1091,SC2154
# planefence-rss.sh
# A script to generate RSS feeds from PlaneFence CSV files
#
# Usage: ./planefence-rss.sh 
#
# This script is distributed as part of the PlaneFence package and is dependent
# on that package for its execution.
#
# Based on a script provided by @randomrobbie - https://github.com/sdr-enthusiasts/docker-planefence/issues/211
# Copyright 2024 @randomrobbie, Ramon F. Kolb (kx1t), and contributors - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence
#

source /scripts/common

# Set paths - use the same as planefence.sh
PLANEFENCEDIR=/usr/share/planefence
[[ -f "$PLANEFENCEDIR/planefence.conf" ]] && source "$PLANEFENCEDIR/planefence.conf"

# Get today's date in yymmdd format
FENCEDATE=$(date --date="today" '+%y%m%d')

# Site configuration - you can modify these
SITE_TITLE="PlaneFence Aircraft Detections"
SITE_DESC="Recent aircraft detected within range of our ADS-B receiver"
SITE_LINK="${RSS_SITELINK}"  # Replace with your actual URL
SITE_IMAGE="${RSS_FAVICONLINK}"  # Optional site image

#  If there is a site link, make sure it ends with a /
if [[ -n "$SITE_LINK" ]] && [[ "${SITE_LINK: -1}" != "/" ]]; then SITE_LINK="${SITE_LINK}/"; fi

# Function to encode special characters for XML
xml_encode() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

# Function to generate RSS feed for a specific CSV file
generate_rss() {
    local csv_file="$1"
    local rss_file="${csv_file%.csv}.rss"
    local date_str="${csv_file##*-}"
    date_str="${date_str%.csv}"
    
    echo "Generating RSS feed for $csv_file"
    
    # Create RSS header
    cat > "$rss_file" <<EOF
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
    <title>$(xml_encode "$SITE_TITLE - $date_str")</title>
    <description>$(xml_encode "$SITE_DESC")</description>
    <link>$(xml_encode "${SITE_LINK:-.}")</link>
    <lastBuildDate>$(date -R)</lastBuildDate>
    ${SITE_IMAGE:+<image>
        <url>$(xml_encode "$SITE_IMAGE")</url>
        <title>$(xml_encode "$SITE_TITLE")</title>
        <link>$(xml_encode "$SITE_LINK")</link>
    </image>}
    <atom:link href="$(xml_encode "${SITE_LINK}${rss_file##*/}")" rel="self" type="application/rss+xml" />
EOF

    # Process the CSV file in reverse order (newest first)
    if [[ -f "$csv_file" ]]; then
        while read -r pfrecord; do
            # CSVHEADERS=(icao flight firstseen lastseen minalt mindist link noisepeak noise1m noise5m noise10m noise1h)

            IFS=, read -r HEXCODE FLIGHT FIRSTSEEN LASTSEEN ALT DIST URL TWEET NOISE REST <<< "$pfrecord"
            # Skip empty lines and comments
            if [[ -z "$HEXCODE" || "${HEXCODE:0:1}" == "#" ]]; then continue; fi

            # Clean up TWEET and NOISE (if present)
            if [[ "$TWEET" =~ ^([0-9.-]+)$ ]]; then NOISE="$TWEET"; fi
            if [[ ! "$NOISE " =~ ^([0-9.-]+)$ ]]; then unset NOISE; fi
            
            # Clean up flight number (remove @ symbol if present)
            FLIGHT="${FLIGHT#@}"
            
            # Create title and description
            TITLE="Aircraft ${FLIGHT:-$HEXCODE} detected"
            DESC="Aircraft ${FLIGHT:-$HEXCODE} was detected within ${DIST}${DISTUNIT} of the receiver"
            DESC="${DESC} at altitude ${ALT}${ALTUNIT} from ${FIRSTSEEN} to ${LASTSEEN}"
            
            # Add noise data if available
            if [[ -n "$NOISE" ]]; then
                DESC="${DESC}, with peak noise level of ${NOISE} dBFS"
            fi
            
            # Create item link - use the tracking URL if available
            ITEM_LINK="${URL:-$SITE_LINK}"
            
            # Calculate pub date from LASTSEEN (assumed to be in format "yyyy-mm-dd hh:mm:ss")
            PUBDATE=$(date -R -d "$LASTSEEN")
            
            # Write RSS item
            cat >> "$rss_file" <<EOF
    <item>
        <title>$(xml_encode "$TITLE")</title>
        <description>$(xml_encode "$DESC")</description>
        <link>$(xml_encode "$ITEM_LINK")</link>
        <guid isPermaLink="false">$HEXCODE-$FIRSTSEEN</guid>
        <pubDate>$PUBDATE</pubDate>
    </item>
EOF
        done <<< "$(tac "$csv_file")"
    fi

    # Close the RSS feed
    cat >> "$rss_file" <<EOF
</channel>
</rss>
EOF

    # Set proper permissions
    chmod 644 "$rss_file"
    "${s6wrap[@]}" echo "RSS feed generated at $rss_file"
}

# Create/update symlink for today's feed
today_csv="$OUTFILEDIR/planefence-$FENCEDATE.csv"
if [[ -f "$today_csv" ]]; then
    generate_rss "$today_csv"
    
    # Create/update the symlink
    ln -sf "planefence-$FENCEDATE.rss" "$OUTFILEDIR/planefence.rss"
    # "${s6wrap[@]}" echo "Updated symlink planefence.rss to point to today's feed"
fi