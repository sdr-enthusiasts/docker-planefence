#!/bin/bash
#set -x
# airlinename.sh - a Bash shell script to return an airline or owner name based on the aircraft's flight or tail number
#
# Usage: ./airlinename.sh <flight_or_tail_number> [<Hex_ID>]
#
# For example:
# $ ./airlinename.sh AAL1000
# American Airlines
# $ ./airlinename.sh n85km
# KODA LOGISTICS
#
# 3-letter airline to name lookup is done in from a table in a file determined by $AIRLINECODES
# For now, we can only do "N" number lookups at the FAA. These are retained in a cache file
# for a period determined by $OWNERDBCACHE in days
#
# In the future, we may add lookups for other countries (UK, Germany, Australia) too if
# there is a relatively easy API to access this data.
#
# This package is part of https://github.com/kx1t/docker-planefence/ and may not work or have any
# value outside of this repository.
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
#
CACHEFILE="/usr/share/planefence/persist/.internal/planeownerscache.txt"
#
# get the plane-alert configuration before the planefence configuration
# so that any values redefined in planefence prevail over plane-alert
[[ -f "/usr/share/plane-alert/plane-alert.conf" ]] && source "/usr/share/plane-alert/plane-alert.conf"
# get the planefence.conf configuration:
if [ -f "/usr/share/planefence/planefence.conf" ]
then
    source "/usr/share/planefence/planefence.conf"
else
        echo $/usr/share/planefence/planefence.conf is missing. We need it to run $0!
        exit 2
fi

if [[ ! -f "$AIRLINECODES" ]]
then
        echo "Cannot stat $AIRLINECODES. $0 exiting."
        exit 2
fi

if [[ "$1" == "" ]]
then
        echo Missing argument
        echo "Usage: $0 <flight_or_tail_number> [<ICAO>]"
        exit 2
fi

[[ "$OWNERDBCACHE" == "" ]] && OWNERDBCACHE=7           # time in days
[[ "$REMOTEMISSCACHE" == "" ]] && REMOTEMISSCACHE=3600  # time in seconds
MUSTCACHE=0

# Cache Cleanup Script
# Syntax: CLEANUP_CACHE <cachefile> <max age in days>
CLEANUP_CACHE ()
{
        [[ "$2" -gt "0" ]] && CACHETIME="$2" || CACHETIME=7
        if [[ -f "$1" ]]
        then
                # we could probably combine these, but... first remove the items that have expired in the cache
                awk -F ',' -v a="$(date -d "-$CACHETIME days" +%s)" -v b="$(date -d "-$REMOTEMISSCACHE seconds" +%s)" '{if ( ( $3 >= a && $2 != "#NOTFOUND") || ( $3 >= b && $2 == "#NOTFOUND")){print $1 "," $2 "," $3}}' $1 >/tmp/namecache 2>/dev/null
                mv -f /tmp/namecache $1 2>/dev/null
        fi
}

# First, let's try to see if it's a regular airline by looking up the argument in our own database:
a="$1"  # get the flight number or tail number from the command line argument
a="${a#@}"      # strip off any leading "@" signs - this is a Planefence feature

[[ "$2" != "" ]] && c="$2" || c="" # C is optional ICAO

#echo "debug: called $0 $1=$a $2=$c"
# add a few exceptions:
[[ "${a:0:4}" == "HMED" ]] && b=" Medevac Bristol"
[[ "${a:0:4}" == "NATO" ]] && b=" NATO"

# Airlinecodes has the 3-character code in field 1 and the full name in field 2
# to prevent false hits when the tall number starts with 3 letters
# (common outside the US), only call this if the input looks like a flight number
[[ "$b" == "" ]] && echo $a | grep -e '^[A-Za-z]\{3\}[0-9][A-Za-z0-9]*' >/dev/null && b="$(awk -F ',' -v a="${a:0:3}" '{IGNORECASE=1; if ($1 == a){print $2;exit;}}' $AIRLINECODES)" # Print flight number if we can find it
[[ "$b" != "" ]] && [[ "$q" == "" ]] && q="aln"

# Now, if we got nothing, then let's try the Plane-Alert database.
# The Plane-Alert db has the tail number in field 2 and the full name in field 3:
[[ "$b" == "" ]] && [[ -f "$PLANEFILE" ]] && b="$(awk -F ',' -v a="$a" '{IGNORECASE=1; if ($2 == a){print $3;exit;}}' $PLANEFILE)"
[[ "$b" != "" ]] && [[ "$q" == "" ]] && q="pa-file"

# Still nothing? Let's see if there is a cache, and if so, if there's a match in our cache
# The cache has the search item (probably tail number) field 1 and the full name in field 2. (Field 3 contains the time added to cache):
[[ "$b" == "" ]] && [[ -f "$CACHEFILE" ]] && echo $a | grep -e '^[A-Za-z]\{3\}[0-9][A-Za-z0-9]*' >/dev/null && b="$(awk -F ',' -v a="${a:0:3}" '{IGNORECASE=1; if ($1 ~ "^"a){print $2;exit;}}' $CACHEFILE)"

[[ "$b" != "" ]] && [[ "$q" == "" ]] && q="ca-a"


[[ "$b" == "" ]] && [[ -f "$CACHEFILE" ]] && b="$(awk -F ',' -v a="$a" '{IGNORECASE=1; if ($1 == a){print $2;exit;}}' $CACHEFILE)"
[[ "$b" != "" ]] && [[ "$q" == "" ]] && q="ca-n"


# Nothing? Then do an FAA DB lookup
if [[ "$b" == "" ]] && [[ "${a:0:1}" == "N" ]]
then
        b="$(timeout 3 curl --compressed -s https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt=$a | grep 'data-label=\"Name\"'|head -1 | sed 's|.*>\(.*\)<.*|\1|g')"
        # If we got something, make sure it will get added to the cache:
        [[ "$b" != "" ]] && MUSTCACHE=1
        [[ "$b" != "" ]] && [[ "$q" == "" ]] && q="faa"


fi

if [[ "$b" == "" ]]
then
  # check OpenSky DB -- this is a bit of a Last Resort as the OS database isn't too accurate
  if [[ -f /run/OpenSkyDB.csv ]]
  then
    b="$(awk -F ","  -v p="${a,,}" '{IGNORECASE=1; gsub("-",""); gsub("\"",""); if(tolower($2)==p) {print $14;exit}}' /run/OpenSkyDB.csv)"
    [[ "$b" != "" ]] && MUSTCACHE=1
    [[ "$b" != "" ]] && [[ "$q" == "" ]] && q="OpenSky"
  fi
fi

# Add additional database lookups in the future here:
# ---------------------------------------------------

# ---------------------------------------------------

# Still nothing - if it looks like an flight number, then try the Planefence server as a last resort
if [[ "$CHECKREMOTEDB" == "ON" ]] && [[ "$b" == "" ]] && [[ "$(echo $a | grep -e '^[A-Za-z]\{3\}[0-9][A-Za-z0-9]*' >/dev/null ; echo $?)" == "0" ]]
then
    b="$(curl -L -s "$REMOTEURL/?flight=$a&icao=$c")"
    [[ "${b:0:1}" == "#" ]] && b="#NOTFOUND" # results starting with # are errors or not-founds
    MUSTCACHE=2 # 2 means only cache the airline prefix
elif [[ "$CHECKREMOTEDB" == "ON" ]] && [[ "$b" == "" ]] && [[ "${a:0:4}" == "HMED" ]]
then
    b="$(curl -L -s "$REMOTEURL/?flight=$a&icao=$c")"
    [[ "${b:0:1}" == "#" ]] && b="#NOTFOUND" # results starting with # are errors or not-founds
    MUSTCACHE=2 # 2 means only cache the airline prefix
fi

[[ "$b" != "" ]] && [[ "$q" == "" ]] && q="rdb"



# Clean up the results
if [[ "$b" != "" ]]
then
        b="$(echo $b|xargs -0)" #clean up extra spaces
        b="${b% [A-Z0-9]}" #clean up single letters/numbers at the end, so "KENNEDY JOHN F" becomes "KENNEDY JOHN"
        b="${b% DBA}" #clean up some undesired suffices, mostly corporate entity names
    b="${b% TRUSTEE}"
    b="${b% OWNER}"
        b="${b% INC}"
        b="${b% LTD}"
        b="${b% PTY}"
        b="${b% \& CO KG}"
        b="${b% AG}"
        b="${b% AB}"
        b="${b% VOF}"
        b="${b% CO}"
        b="${b% CORP}"
        b="${b% LLC}"
        b="${b% GMBH}"
        b="${b% BV}"
        b="${b% NV}"
        b="${b/Government of/Govt}"
        b="${b/Ministry of Finance/MinFinance}"
        b="$(xargs -0 <<< "${b/&/}")"   # remove any ampersands from the name

fi

# Write back to cache if needed
[[ "$MUSTCACHE" == "1" ]] && printf "%s,%s,%s\n" "$a" "$b" "$(date +%s)" >> "$CACHEFILE"
[[ "$MUSTCACHE" == "2" ]] && printf "%s,%s,%s\n" "${a:0:4}" "$b" "$(date +%s)" >> "$CACHEFILE"
[[ "$MUSTCACHE" != "0" ]] && CLEANUP_CACHE $CACHEFILE $OWNERDBCACHE

# prune dupes from cache
if [[ "$MUSTCACHE" != "0" ]] && [[ "$(awk -F',' 'seen[$1]++' $CACHEFILE 2>/dev/null |wc -l)" != "0" ]]
then
        awk -F',' '!seen[$1]++' "$CACHEFILE" >/tmp/airlinecache
        mv -f /tmp/airlinecache "$CACHEFILE"
fi

# so.... if we got no reponse from the remote server, then remove it now:
[[ "$b" == "#NOTFOUND" ]] && b=""

# Lookup is done - return the result
echo "$b"
