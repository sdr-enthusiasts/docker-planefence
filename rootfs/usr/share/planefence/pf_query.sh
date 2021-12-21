#!/bin/bash
#
# pf_php.sh -- Script to be called from PHP - returns REGEX subset of PlaneFence
#
# Usage: pf_php.sh [hex=<regex>] [call=<regex>] [start=<regex>] [end=<regex>] file=<inputfiles>
#        File argument is always required and at least 1 additional argument is required.
#
# Copyright 2021 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
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

# Parse command line into variables:
for i in "$@"
do
	[[ "${i:0:4}" == "hex=" ]] && hex="${i:4}"
	[[ "${i:0:5}" == "call=" ]] && call="${i:5}"
	[[ "${i:0:6}" == "start=" ]] && start="${i:6}"
	[[ "${i:0:4}" == "end=" ]] && end="${i:4}"
	[[ "${i:0:5}" == "file=" ]] && file="${i:5}"
done

# If the command line didn't include any valid args, or if the arg is --help or -?, then show them the way:
if [[ "$hex$call$start$end" == "" ]] || [[ "$file" == "" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-?" ]]
then
  echo "Usage: $0 [hex=<regex>] [call=<regex>] [start=<regex>] [end=<regex>] file=<inputfiles>"
  echo "The file argument is always required and at least 1 additional argument is required."
	echo "The arguments can contain plain text or be a regex that is used with the \`awk\` command."
	echo ""
	echo "The arguments can be passed in any order."
	echo ""
	echo "For example:"
	echo "$0 hex=\"^A[DE]\" file=\"*.csv\""
	echo "<br><br>$0 $@<br>"
  exit 1
else
#	echo  Now we get the data and print to the stdout:
#	echo "hex=$hex call=$call start=$start end=$end file=$file"
# printf "hex,call,start,end,alt,dist,url\n$(./pf_php.sh hex="^A[DE]" file="html/*.csv" call="^C" start="2021/12/1[345]")" | jq -Rs 'split("\n")|map(split(",")|to_entries)|.[0] as $header|.[1:]|map(reduce .[] as $item ({};.[$header[$item.key].value]=$item.value))'

	# Create the header string:
	# First few positions are fixed:
	header[0]="hex_id"
	header[1]="callsign"
	header[2]="start_time"
	header[3]="end_time"
	header[4]="min_alt"
	header[5]="min_dist"
	header[6]="adsbx_link"

	# Next header positions are variable, if they exist at all. We will take the first line of the first file to figure this out
	read -r LINE <<< $(cat html/*.csv | head -1)
	IFS=, read -ra RECORD <<< "$LINE"
	[[ "${RECORD[7]:0:1}" == "-" ]] &&  header[7]="audio_peak"
	[[ "${RECORD[8]:0:1}" == "-" ]] &&  header[8]="audio_1min_avg"
	[[ "${RECORD[9]:0:1}" == "-" ]] &&  header[9]="audio_5min_avg"
	[[ "${RECORD[10]:0:1}" == "-" ]] && header[10]="audio_10min_avg"
	[[ "${RECORD[11]:0:1}" == "-" ]] && header[11]="audio_60min_avg"
	[[ "${RECORD[1]:0:1}" == "@" ]] && [[ "${RECORD[7]:0:4}" == "http" ]] && header[7]="tweet_url"
	[[ "${RECORD[1]:0:1}" == "@" ]] && [[ "${RECORD[12]:0:4}" == "http" ]] && header[12]="tweet_url"

	# concatenate header:
	printf -v h "%s," "${header[@]}"
	header=${h:0:-1}

	# now AWK the required lines and convert the output to JSON using JQ:
	printf "$header\n$(awk -F ',' -v hex="$hex" -v call="$call" -v start="$start" -v end="$end" '$1~hex && $2~call && $3~start && $4~end' $file)" \
		| jq -Rs 'split("\n")|map(split(",")|to_entries)|.[0] as $header|.[1:]|map(reduce .[] as $item ({};.[$header[$item.key].value]=$item.value))'

fi
