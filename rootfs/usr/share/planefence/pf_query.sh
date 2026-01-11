#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2034,SC2154,SC2174
#
# pf_query.sh -- Script to be called from PHP - returns REGEX subset of Plane-Alert
#
# Usage: pf_query.sh [hex=<regex>] [call=<regex>] [start=<regex>] [end=<regex>] file=<inputfiles>
#        File argument is always required and at least 1 additional argument is required.
#
# Copyright 2021-2026 Ramon F. Kolb - licensed under the terms and conditions
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

# shellcheck disable=SC1091
source /scripts/pf-common
DEBUG=false
# Parse command line into variables:
for i in "$@"; do
	i="${i//\'/}"	# remove any single quotes
	[[ "${i:0:6}" == "index=" ]] && index="${i:6}"
	[[ "${i:0:4}" == "hex=" ]] && hex="${i:4}"
	[[ "${i:0:5}" == "tail=" ]] && tail="${i:5}"
	[[ "${i:0:5}" == "name=" ]] && name="${i:5}"
	[[ "${i:0:10}" == "equipment=" ]] && equip="${i:10}"
	[[ "${i:0:10}" == "timestamp=" ]] && timestamp="${i:10}"
	[[ "${i:0:5}" == "call=" ]] && call="${i:5}"
	[[ "${i:0:4}" == "lat=" ]] && lat="${i:4}"
	[[ "${i:0:4}" == "lon=" ]] && lon="${i:4}"
  [[ "${i:0:5}" == "type=" ]] && output_type="${i:5}"
done

# echo "args received: index=${index} hex=${hex} tail=${tail} name=${name} equipment=${equip} timestamp=${timestamp} call=${call} lat=${lat} lon=${lon} output_type=${output_type}.TZ=${TZ}, date=$(date)"

# If the command line didn't include any valid args, or if the arg is --help or -?, then show them the way:
if [[ "$index$hex$tail$name$equip$timestamp$call$lat$lon" == "" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-?" ]]
then
  echo "Usage: $0 [index=<regex>] [hex=<regex>] [tail=<regex>] [name=<regex>] [equipment=<regex>] [timestamp=<regex>] [call=<regex>] [lat=<regex>] [lon=<regex>] [type=csv|json]"
  echo "The file argument is always required and at least 1 additional argument is required."
	echo "The arguments can contain plain text or be a regex that is used with the \`awk\` command."
	echo ""
	echo "The arguments can be passed in any order."
	echo ""
	echo "For example:"
	echo "$0 hex=\"^A[DE]\" type=\"*.csv\""
	echo ""
	# shellcheck disable=SC2145
	echo "Command line was: $0 ${@}"
  exit 1
else
	#	echo  Now we get the data and print to the stdout:
	READ_RECORDS ignore-lock
	shopt -s nocasematch
	csv=""
	for ((idx=${records[maxindex]}; idx>=0; idx--)); do
		if [[ $idx =~ ${index:-xxxxxx} || \
				${records["$idx":icao]} =~ ${hex:-xxxxxx} || \
				${records["$idx":tail]} =~ ${tail:-xxxxxx} || \
				${records["$idx":owner]} =~ ${name:-xxxxxx} || \
				${records["$idx":type]} =~ ${equip:-xxxxxx} || \
				${records["$idx":time:time_at_mindist]} =~ ${timestamp:-xxxxxx} || \
				${records["$idx":callsign]} =~ ${call:-xxxxxx} || \
				${records["$idx":lat]} =~ ${lat:-xxxxxx} || \
				${records["$idx":lon]} =~ ${lon:-xxxxxx} ]]; then
			readarray -t headers < <(printf '%s\n' "${!records[@]}" | sed -n "s/^${idx}:\(.*\)$/\1/p" | LC_ALL=C sort)
			
			# Build the CSV line:
			line="index=${idx},"
			for h in "${headers[@]}"; do
				line+="$(printf '%s=%s,' "$h" "${records["$idx:$h"]//,/ }")"
			done
			line=${line%,}
			line+=$'\n'
			csv+="$line"
		fi
	done
	if [[ "$output_type" == "csv" ]]; then
		# Print the CSV:
		printf "%s" "$csv"
	else
		# Convert CSV to JSON using JQ (split by newline, one object per line)
		jq -sR '
		  [ split("\n")[]
		    | select(length>0)
		    | split(",")
		    | map(select(length>0))
		    | map(split("=") | { (.[0]): .[1] })
		    | add
		  ]
		' <<< "$csv"
	fi
fi
