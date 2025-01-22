#!/bin/bash
#
# pf_php.sh -- Script to be called from PHP - returns REGEX subset of PlaneFence
#
# Usage: pf_php.sh [hex=<regex>] [call=<regex>] [start=<regex>] [end=<regex>] file=<inputfiles>
#        File argument is always required and at least 1 additional argument is required.
#
# Copyright 2021-2025 Ramon F. Kolb - licensed under the terms and conditions
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

CSVFILE=/usr/share/planefence/html/plane-alert/plane-alert.csv

# Parse command line into variables:
for i in "$@"
do
	[[ "${i:0:4}" == "hex=" ]] && hex="${i:4}"
	[[ "${i:0:5}" == "tail=" ]] && tail="${i:5}"
	[[ "${i:0:5}" == "name=" ]] && name="${i:5}"
	[[ "${i:0:10}" == "equipment=" ]] && equip="${i:10}"
	[[ "${i:0:10}" == "timestamp=" ]] && timestamp="${i:10}"
	[[ "${i:0:5}" == "call=" ]] && call="${i:5}"
	[[ "${i:0:4}" == "lat=" ]] && lat="${i:4}"
	[[ "${i:0:4}" == "lon=" ]] && lon="${i:4}"
	# [[ "${i:0:5}" == "file=" ]] && file="${i:5}" # not supported, always the same file for PA
  [[ "${i:0:5}" == "type=" ]] && output_type="${i:5}"
done

# If the command line didn't include any valid args, or if the arg is --help or -?, then show them the way:
if [[ "$hex$tail$name$equip$timestamp$call$lat$lon" == "" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-?" ]]
then
  echo "Usage: $0 [hex=<regex>] [tail=<regex>] [name=<regex>] [equipment=<regex>] [timestamp=<regex>] [call=<regex>] [lat=<regex>] [lon=<regex>] type=csv|json"
  echo "The file argument is always required and at least 1 additional argument is required."
	echo "The arguments can contain plain text or be a regex that is used with the \`awk\` command."
	echo ""
	echo "The arguments can be passed in any order."
	echo ""
	echo "For example:"
	echo "$0 hex=\"^A[DE]\" file=\"*.csv\""
	echo ""
	echo "Command line was: $0 $@"
  exit 1
else
#	echo  Now we get the data and print to the stdout:
#	echo "hex=$hex call=$call start=$start end=$end file=$file"
# printf "hex,call,start,end,alt,dist,url\n$(./pf_php.sh hex="^A[DE]" file="html/*.csv" call="^C" start="2021/12/1[345]")" | jq -Rs 'split("\n")|map(split(",")|to_entries)|.[0] as $header|.[1:]|map(reduce .[] as $item ({};.[$header[$item.key].value]=$item.value))'

	# Create the header string:
	# First few positions are fixed:
	header[0]="hex_id"
	header[1]="tail"
	header[2]="name"
	header[3]="equipment"
	header[4]="date"
	header[5]="time"
	header[6]="lat"
	header[7]="lon"
	header[8]="call"
	header[9]="adsbx_link"

	# concatenate header:
	printf -v h "%s," "${header[@]}"
	header=${h:0:-1}

	# now AWK the required lines and optionally convert the output to JSON using JQ:
  if [[ "$output_type" == "csv" ]]
  then
    printf "$header\n$(awk -F ',' -v "IGNORECASE=1" -v hex="$hex" -v tail="$tail" -v name="$name" -v equip="$equip" -v timestamp="$timestamp" -v call="$call" -v lat="$lat" -v lon="$lon" '$1~hex && $2~tail && $3~name && $4~equip && $5" "$6~timestamp && $9~call && $7~lat && $8~lon' $CSVFILE | sed 's|,*\r*$||')"
  else
	   printf "$header\n$(awk -F ',' -v "IGNORECASE=1" -v hex="$hex" -v tail="$tail" -v name="$name" -v equip="$equip" -v timestamp="$timestamp" -v call="$call" -v lat="$lat" -v lon="$lon" '$1~hex && $2~tail && $3~name && $4~equip && $5" "$6~timestamp && $9~call && $7~lat && $8~lon' $CSVFILE | sed 's|,*\r*$||')" \
		   | jq -Rs 'split("\n")|map(split(",")|to_entries)|.[0] as $header|.[1:]|map(reduce .[] as $item ({};.[$header[$item.key].value]=$item.value))'
  fi
fi
