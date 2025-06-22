#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154

source /scripts/common
# -----------------------------------------------------------------------------------
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
# fix for malformed csv file
# note, this is a bandaid to correct the output of a buggy routine
# and not a fix for the bug itself.
# The issue it attempts to correct is that sometimes there is no URL
# field written to the csv record causing it to collapse a field
# This script corrects that.
#
# The desired CSV file layout is:
# 0-ICAO,1-[@][Flight],2-date/time_first_heard,3-date/time_last_heard,
# 4-min_alt,5-min_dist,6-webservicelink,7-[loudness],8-[peak_dB],9-[1min_dB],
# 10-[5min_dB],11-[10min_dB],11-[1hr_dB],12-[tweetlink]

# get inputfile

[[ ! -f "$1" ]] && CSV=/usr/share/planefence/html/planefence-$(date +%y%m%d).csv || CSV="$1"

source /usr/share/planefence/planefence.conf
[[ -f "$CSV.tmp" ]] && rm -f "$CSV.tmp"

# if there are no entries, exit
[[ ! -f "$CSV" ]] && exit

# find array length
numrec=0
while IFS= read -r l
do
	IFS=, read -ra r <<< "$l"
	[[ ${#r[@]} -gt $numrec ]] && numrec=${#r[@]}
done < "$CSV"

while read -r l
do
	IFS=, read -ra r <<< "$l"

	# check for http link in field 6. If it doesn't exist, insert it
	if [[ "${r[6]::4}" != "http" ]]
	then
		#we got a problem
		# IFS=, echo was: "$l"
		for (( i=numrec; i>=6; i-- ))
		do
			r[i]=${r[i-1]}
		done

		d=$(date -d "${l[2]}" +%s)
		utcdate=$(date -u -d @"$d" +%Y-%m-%d)
		printf -v url "http://globe.adsbexchange.com/?icao=%s&lat=%s&lon=%s&zoom=13&showTrace=%s" "${r[0]}" "$LAT" "$LON" "$utcdate"

		r[6]="$url"
		l=""
		for (( i=0; i<=numrec; i++ ))
		do
			printf -v l "%s,%s" "$l" "${r[i]}"
		done
		l="${l:1}"
		l="${l%,}"
		#echo now: $l
	fi

	# there are less than 13 fields, then it's possible we have to relocate the twitter ID
	# which may have been written into field 7-11
	for i in {7..11}
	do
		if [[ "${r[i]::13}" == "https://t.co/" ]]
		then
			r[12]="${r[i]}"
			for ((j=i; j<12; j++))
			do
				r[j]=""
			done
		fi
	done

	# fix an issue where there's no audio and somehow it fills up the audio fields with -999. This has probably to do
	# with the planefence.sh algorithm that tries to find the right time range for the spectrogram or noiseplot.
	# It's easier to just fix it here...

	for a in {7..11}
	do
		[[ "${r[a]}" == "-999" ]] && r[a]=""
	done

	# Now, a bunch of routines that help determine a flight or tail number if none is available:

    # If there is no flight or tail number, let's see if there's one in one of the socket30003 dump files:
	if [[ "${r[1]#@}" == "" ]]
	then
		r[1]+="$(awk -F "," -v icao="${r[0]}" '($1 == icao && $12 != "") {print $12;exit;}' "$LOGFILEBASE"*.txt 2>/dev/null)"
		if [[ "${r[1]#@}" != "" ]] && [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "updated ${r[0]} = ${r[1]#@} (from socket30003 data)"; fi
	fi

    # Look up the ICAO in the mictronics database (local copy) if we have it downloaded:
	if [[ "${r[1]#@}" == "" ]]
	then
		r[1]+="$(grep -i -w "${r[0]}" /run/planefence/icao2plane.txt 2>/dev/null | head -1 | awk -F "," '{print $2}')"
		# note - we could have done this with only an awk command, but that takes about 4x longer to execute
		# awk command wouldve been: awk -F "," -v icao="${r[1]#@}" '($1 == icao) {print $2;exit;}' /run/planefence/icao2plane.txt
		if [[ "${r[1]#@}" != "" ]] && [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "updated ${r[0]} = ${r[1]#@} (from mictronic database cache)"; fi
	fi

	# If the ICAO starts with "A" and there is no flight or tail number, let's algorithmically determine the tail number
	if [[ -z "${r[1]#@}" ]] && [[ "${r[0]:0:1}" == "A" ]]; then
		r[1]+=$(/usr/share/planefence/icao2tail.py "${r[0]}")
		if [[ -n "${r[1]#@}" ]] && [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "updated ${r[0]} = ${r[1]#@} (from US Hex ID)"; fi
	fi

	# strip off trailing spaces
	a=${r[1]}
	r[1]="${a%"${a##*[![:space:]]}"}"

	# finally, write everything back into $l and write the string to a temp file:
	printf -v l '%s,' "${r[@]}"
	l="${l%,}"
	echo "$l" >> "$CSV.tmp"

done < "$CSV"

mv -f "$CSV.tmp" "$CSV"
