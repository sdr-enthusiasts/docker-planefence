#!/bin/bash
#shellcheck shell=bash disable=SC2015,SC2001
#
# Usage: nominatim.sh lat=xxxx lon=yyyy
# Returns
#
# -----------------------------------------------------------------------------------
# This package is part of https://github.com/kx1t/docker-planefence/ and may not work or have any
# value outside of this repository.
#
# Copyright 2023 Ramon F. Kolb - licensed under the terms and conditions
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

# read command line params and extract lat and long from it

for arg in "$@"
do
    arg=${arg,,}
    [[ "${arg%%=*}" == "--lat" ]] && lat="${arg#*=}" || true
    [[ "${arg%%=*}" == "--lon" ]] && lon="${arg#*=}" || true
    [[ "${arg%%=*}" == "--raw" ]] && raw=true || unset raw
done

if [[ -z "$lat" || -z "$lon" ]]
then
    echo "Missing argument. Usage: $0 --lat=xx.xxxx --lon=yy.yyyy"
    exit 1
fi

if ! result="$(curl -sSL "https://nominatim.openstreetmap.org/reverse?format=xml&lat=$lat&lon=$lon")"
then
    echo "Error fetching nominatim results - bad format"
    exit 1
fi

if grep "<error>" >/dev/null 2>&1 <<< "$result"
then
    if grep "Unable to geocode" >/dev/null 2>&1 <<< "$result"
    then
        # nothing to return - no location name found
        exit 0
    else
        echo -n "Error fetching nominatim results:"
        sed 's|.*<error>\(.*\)</error>.*|\1|g' <<< "$result"
        exit 1
    fi
fi

if [[ $raw == true ]]
then
    echo "$result"
    exit 0
fi

# fetch elements:
city="$(sed -n 's|.*<city>\(.*\)</city>.*|\1|p' <<< "$result")"
town="$(sed -n 's|.*<town>\(.*\)</town>.*|\1|p' <<< "$result")"
municipality="$(sed -n 's|.*<municipality>\(.*\)</municipality>.*|\1|p' <<< "$result")"
state="$(sed -n 's|.*<state>\(.*\)</state>.*|\1|p' <<< "$result")"
country="$(sed -n 's|.*<country>\(.*\)</country>.*|\1|p' <<< "$result")"
county="$(sed -n 's|.*<county>\(.*\)</county>.*|\1|p' <<< "$result")"
country_code="$(sed -n 's|.*<country_code>\(.*\)</country_code>.*|\1|p' <<< "$result")"
postcode="$(sed -n 's|.*<postcode>\(.*\)</postcode>.*|\1|p' <<< "$result")"
# do some parsing based on country
if [[ "${country_code,,}" == "de" ]]
then
    county=""
fi
if [[ "${country_code,,}" == "be" ]]
then
    state=""
fi
if [[ "${country_code,,}" == "fr" ]]
then
    state=""
    county="$county (${postcode:0:2})"
fi
[[ -n "$city" ]] && returnstr="$city, " || true
[[ -z "$returnstr" ]] && [[ -n "$town" ]] && returnstr="$town, " || true
[[ -z "$returnstr" ]] && [[ -n "$municipality" ]] && returnstr="$municipality, " || true
[[ -n "$county" ]] && returnstr+="$county, " || true
[[ -n "$state" ]] && returnstr+="$state, " || true
[[ -n "$country_code" ]] && returnstr+="${country_code^^}" || true
echo "$returnstr"
