#!/bin/bash
# fix for malformed csv file
# note, this is a bandaid to correct the output of a buggy routine
# and not a fix for the bug itself.
# The issue it attempts to correct is that sometimes there is no URL
# field written to the csv record causing it to collapse a field
# This script corrects that.

# get inputfile
[[ ! -f "$1" ]] && CSV=/usr/share/planefence/html/planefence-$(date +%y%m%d).csv || CSV="$1"

source /usr/share/planefence/planefence.conf
[[ -f "$CSV.tmp" ]] && rm -f "$CSV.tmp"

# if there are no entries, exit
[[ ! -f "$CSV" ]] && exit

# find array length
numrec=0
while read -r l
do
	IFS=, read -ra r <<< "$l"
	[[ ${#r[@]} -gt $numrec ]] && numrec=${#r[@]}
done < "$CSV"

while read -r l
do
	IFS=, read -ra r <<< "$l"
	if [[ "${r[6]::4}" != "http" ]]
	then
		#we got a problem
		IFS=, echo was: $l
		for (( i=$numrec; i>=6; i-- ))
		do
			r[i]=${r[i-1]}
		done

		d=$(date -d "${l[2]}" +%s)
                utcdate=$(date -u -d @"$d" +%Y-%m-%d)

                printf -v url "http://globe.adsbexchange.com/?icao=%s&lat=%s&lon=%s&zoom=13&showTrace=%s" "${r[0]}" "$LAT" "$LON" "$utcdate"

		r[6]=$url
		l=""
		for (( i=0; i<=$numrec; i++ ))
		do
			printf -v l "%s,%s" "$l" "${r[i]}"
		done
		l="${l:1}"
		l="${l%,}"
		echo now: $l
	fi
	echo $l >> "$CSV.tmp"

done < "$CSV"

mv -f "$CSV.tmp" "$CSV"
