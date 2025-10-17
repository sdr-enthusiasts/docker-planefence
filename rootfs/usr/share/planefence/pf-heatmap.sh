#!/command/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034,SC2154,SC2155,SC2030,SC2031
#
# #-----------------------------------------------------------------------------------
# PF-HEATMAP.SH
# Create an insertable heatmap
#
# Copyright 2020-2025 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# Summary of License Terms
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see https://www.gnu.org/licenses/.
# -----------------------------------------------------------------------------------

source /scripts/pf-common
source /usr/share/planefence/planefence.conf

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
## DEBUG stuff:
# DEBUG=true

## initialization:
source /scripts/pf-common
source /usr/share/planefence/planefence.conf
echo "$" > /run/planefence.pid

# -----------------------------------------------------------------------------------
# Config and initialization
# -----------------------------------------------------------------------------------
RECORDSDIR="${RECORDSDIR:-/usr/share/planefence/persist/records}"
HTMLDIR="${OUTFILEDIR:-/usr/share/planefence/html}"
mkdir -p "$HTMLDIR"

TODAY="$(date +%y%m%d)"
YESTERDAY="$(date -d "yesterday" +%y%m%d)"
NOWTIME="$(date +%s)"

TODAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${TODAY}.txt" -print | sort | head -n 1)"
YESTERDAYFILE="$(find /run/socket30003 -type f -name "dump1090-*-${YESTERDAY}.txt" -print | sort | head -n 1)"

RECORDSFILE="$RECORDSDIR/planefence-records-${TODAY}.gz"
YESTERDAYRECORDSFILE="$RECORDSDIR/planefence-records-${YESTERDAY}.gz"

CSVOUT="$HTMLDIR/planefence-${TODAY}.csv"
JSONOUT="$HTMLDIR/planefence-${TODAY}.json"

# Precompute midnight of today only once:
midnight_epoch=$(date -d "$(date +%F) 00:00:00" +%s)
today_ymd=$(date +%Y/%m/%d)
yesterday_epoch=$(date -d yesterday +%s)

# Determine the user visible longitude and latitude based on the "fudge" factor we need to add:
printf -v LATFUDGED "%.${FUDGELOC:-3}f" "$LAT"
printf -v LONFUDGED "%.${FUDGELOC:-3}f" "$LON"

# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------

# First define a bunch of functions:

# Function to create the Heatmap
CREATEHEATMAP () {
	# Disable the heatmap in the template if $PLANEHEAT is not enabled
	if ! chk_enabled "$PLANEHEAT"; then
		template="$(sed -z 's/<!--PLANEHEAT||>.*<||PLANEHEAT-->//g' <<< "$template")"
		return
	else
		template="$(template_replace "<!--PLANEHEAT||>" "" "$template")"
		template="$(template_replace "<||PLANEHEAT-->" "" "$template")"
	fi

	# If OpenAIP is enabled, include it. If not, exclude it.
	if chk_enabled "$OPENAIP_LAYER"; then
		template="$(template_replace "<!--OPENAIP||>" "" "$template")"
		template="$(template_replace "<||OPENAIP-->" "" "$template")"
		template="$(template_replace "||OPENAIPKEY||" "$OPENAIPKEY" "$template")"
	else
		template="$(sed -z 's/<!--OPENAIP||>.*<||OPENAIP-->//g' <<< "$template")"
	fi

	# Replace the other template values:
# Determine the zoom level for the heatmap
	template="$(template_replace "||LATFUDGED||" "$LATFUDGED" "$template")"
	template="$(template_replace "||LONFUDGED||" "$LONFUDGED" "$template")"
	template="$(template_replace "||HEATMAPZOOM||" "$HEATMAPZOOM" "$template")"
	template="$(template_replace "||HEATMAPWIDTH||" "$HEATMAPWIDTH" "$template")"
	template="$(template_replace "||HEATMAPHEIGHT||" "$HEATMAPHEIGHT" "$template")"
	template="$(template_replace "||DISTMTS||" "$DISTMTS" "$template")"

	# Create the heatmap data
	{ printf "var addressPoints = [\n"
		for i in "${!heatmap[@]}"; do
				printf "[ %s,%s ],\n" "$i" "${heatmap["$i"]}"
		done
		printf "];\n"
	} > "$OUTFILEDIR/js/planeheatdata-$TODAY.js"

  # That's all for the heatmap

}


log_print INFO "Hello. Starting $0"

# Load the template into a variable that we can manipulate:
if ! template=$(<"$PLANEFENCEDIR/pf-heatmap.template"); then
	log_print ERR "Failed to load template"
	exit 1
fi

# Load the records
READ_PF_RECORDS
if (( records[maxindex] < 0 )); then
	log_print WARN "No records found. Exiting"
	exit 0
fi



# Get the altitude reference:
if [[ -n "$ALTCORR" ]]; then ALTREF="AGL"; else ALTREF="MSL"; fi
# "DIST is $DIST ${records["$idx":distance:unit]}; Conv to meters is $TO_METER"
DISTMTS="$(awk "BEGIN{print int($DIST * $TO_METER)}")"

# -----------------------------------------------------------------------------------
#      MODIFY THE TEMPLATE
# -----------------------------------------------------------------------------------

log_print DEBUG "Adding heatmap (if enabled)"
CREATEHEATMAP
log_print DEBUG "Done updating the template"

# ---------------------------------------------------------------------------
#      FINALIZE AND WRITE THE FILES
# ---------------------------------------------------------------------------
log_print INFO "Writing HTML file"
echo "$template" > "$OUTFILEDIR/heatmap-$TODAY.html"

log_print INFO "Done - Wrote HTML file to $OUTFILEDIR/heatmap-$TODAY.html"
