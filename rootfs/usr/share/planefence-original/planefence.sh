#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC2001,SC2015,SC1091,SC2129,SC2154,SC2155
#
# PLANEFENCE - a Bash shell script to render a HTML and CSV table with nearby aircraft
#
# Usage: ./planefence.sh
#
# Copyright 2020-2025 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
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
# Only change the variables below if you know what you are doing.

# all errors will show a line number and the command used to produce the error
source /scripts/common

# We need to define the directory where the config file is located:

[[ "$BASETIME" != "" ]] && echo "0. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- started Planefence" || true

PLANEFENCEDIR=/usr/share/planefence

# Let's see if we must reload the parameters
if [[ -f "/run/planefence/last-config-change" ]] && [[ -f "/usr/share/planefence/persist/planefence.config" ]]; then
	# if... the date-last-changed of config file on the exposed volume ... is newer than the last time we read it ... then ... rerun the prep routine (which will update the last-config-change)
	[[ "$(stat -c %Y /usr/share/planefence/persist/planefence.config)" -gt "$(</run/planefence/last-config-change)" ]] && /usr/share/planefence/prep-planefence.sh
fi
# FENCEDATE will be the date [yymmdd] that we want to process Planefence for.
# The default value is 'today'.

if [[ -n "$1" ]] && [[ "$1" != "reset" ]]; then # $1 contains the date for which we want to run Planefence
FENCEDATE=$(date --date="$1" '+%y%m%d')
else
	FENCEDATE=$(date --date="today" '+%y%m%d')
fi

[[ "$TRACKSERVICE" != "flightaware" ]] && TRACKSERVICE="flightaware" || true

# -----------------------------------------------------------------------------------
# Compare the original config file with the one in use, and call
#
#
# -----------------------------------------------------------------------------------
# Read the parameters from the config file
if [[ -f "$PLANEFENCEDIR/planefence.conf" ]]; then
	source "$PLANEFENCEDIR/planefence.conf"
else
	echo $PLANEFENCEDIR/planefence.conf is missing. We need it to run Planefence!
	exit 2
fi

# -----------------------------------------------------------------------------------
# Ensure that there's an '/tmp/add_delete.uuid' file, or update it if needed
# -----------------------------------------------------------------------------------
if [[ ! -f /tmp/add_delete.uuid ]] || ( [[ -f /tmp/add_delete.uuid.used ]] && (( $(date +%s) - $(</tmp/add_delete.uuid.used) > 300 )) ); then
	# UUID file needs to be updated. This is done to prevent replay attacks.
	# This is done if the UUID was used more than 300 seconds ago, or if the file doesn't exist.
	cat /proc/sys/kernel/random/uuid > /tmp/add_delete.uuid
	touch /tmp/.force_pa_webpage_update	# this is used to force a Plane-Alert webpage update upon change of parameters
	rm -f /tmp/add_delete.uuid.used
fi

uuid="$(</tmp/add_delete.uuid)"

# first get DISTANCE unit:
DISTUNIT="mi"
#DISTCONV=1
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
fi

# get ALTITUDE unit:
ALTUNIT="ft"
if [[ -f "$SOCKETCONFIG" ]]; then
	case "$(grep "^altitudeunit=" "$SOCKETCONFIG" |sed "s/altitudeunit=//g")" in
		feet)
		ALTUNIT="ft"
		;;
		meter)
		ALTUNIT="m"
	esac
fi

# Figure out if NOISECAPT is active or not. REMOTENOISE contains the URL of the NoiseCapt container/server
# and is configured via the $PF_NOISECAPT variable in the .env file.
# Only if REMOTENOISE contains a URL and we can get the noise log file, we collect noise data
# replace wget by curl to save memory space. Was: [[ "x$REMOTENOISE" != "x" ]] && [[ "$(wget -q -O /tmp/noisecapt-$FENCEDATE.log $REMOTENOISE/noisecapt-$FENCEDATE.log ; echo $?)" == "0" ]] && NOISECAPT=1 || NOISECAPT=0
if [[ -n "$REMOTENOISE" ]]; then
	if curl --fail -s "$REMOTENOISE/noisecapt-$FENCEDATE.log" > "/tmp/noisecapt-$FENCEDATE.log"; then
		NOISECAPT=1
	else
		NOISECAPT=0
	fi
fi
#
#
# Determine the user visible longitude and latitude based on the "fudge" factor we need to add:
if [[ "$FUDGELOC" != "" ]]; then
	if [[ "$FUDGELOC" == "0" ]]; then
		printf -v LON_VIS "%.0f" "$LON"
		printf -v LAT_VIS "%.0f" "$LAT"
	elif [[ "$FUDGELOC" == "1" ]]; then
		printf -v LON_VIS "%.1f" "$LON"
		printf -v LAT_VIS "%.1f" "$LAT"
	elif [[ "$FUDGELOC" == "2" ]]; then
		printf -v LON_VIS "%.2f" "$LON"
		printf -v LAT_VIS "%.2f" "$LAT"
	else
		# If $FUDGELOC != "" but also != "2", then assume it is "3"
		printf -v LON_VIS "%.3f" "$LON"
		printf -v LAT_VIS "%.3f" "$LAT"
	fi
	# clean up the strings:
else
	# let's not print more than 5 digits
	printf -v LON_VIS "%.5f" "$LON"
	printf -v LAT_VIS "%.5f" "$LAT"
fi
# shellcheck disable=SC2001
LON_VIS="$(sed 's/^00*\|00*$//g' <<< "$LON_VIS")"	# strip any trailing zeros - "41.10" -> "41.1", or "41.00" -> "41."
LON_VIS="${LON_VIS%.}"		# If the last character is a ".", strip it - "41.1" -> "41.1" but "41." -> "41"
# shellcheck disable=SC2001
LAT_VIS="$(sed 's/^00*\|00*$//g' <<< "$LAT_VIS")" 	# strip any trailing zeros - "41.10" -> "41.1", or "41.00" -> "41."
LAT_VIS="${LAT_VIS%.}" 		# If the last character is a ".", strip it - "41.1" -> "41.1" but "41." -> "41"
if (( ALTCORR != 0 )); then ALTREFERENCE="AGL"; else ALTREFERENCE="MSL"; fi
#
#
# Functions
#
# Function to write to the log
LOG ()
{
	# This reads a string from stdin and stores it in a variable called IN. This enables things like 'echo hello world > LOG'
	while [[ -n "$1" ]] || read -r IN; do
		if [[ -n "$1" ]]; then
			IN="$1"
		fi
		if [[ "$VERBOSE" != "" ]]; then
			if [[ "$LOGFILE" == "logger" ]]; then
				printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$IN" | logger
			else
				printf "%s-%s[%s]v%s: %s\n" "$(date +"%Y%m%d-%H%M%S")" "$PROCESS_NAME" "$CURRENT_PID" "$VERSION" "$IN" >> "$LOGFILE"
			fi
		fi
		if [[ -n "$1" ]]; then
			break
		fi
	done
}

GET_ROUTE () {
		# function to get a route by callsign. Must have a callsign - ICAO won't work
		# Usage: GET_ROUTE <callsign>
		# Uses the adsb.lol API to retrieve the route

		local route
		
		# first let's see if it's in the cache
		if [[ -f /usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt ]]; then
			route="$(awk -F, -v callsign="${1^^}" '$1 == callsign {print $2; exit}' "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt")"
			if [[ -n "$route" ]]; then
				if  [[ "$route" != "unknown" ]]; then echo "$route"; fi
				return
			fi
		fi

		if route="$(curl -sSL -X 'POST' 'https://api.adsb.lol/api/0/routeset' \
		                      -H 'accept: application/json' \
													-H 'Content-Type: application/json' \
													-d '{"planes": [{"callsign": "'"${1^^}"'","lat": '"$LAT"',"lng": '"$LON"'}] }' \
								| jq -r '.[]._airport_codes_iata')" \
				&& [[ -n "$route" ]] && [[ "$route" != "unknown" ]] && [[ "$route" != "null" ]]
		then
			echo "${1^^},$route" >> "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt"
			echo "$route"
		elif [[ "${route,,}" == "unknown" ]] || [[ "${route,,}" == "null" ]]; then
			echo "${1^^},unknown" >> "/usr/share/planefence/persist/.internal/routecache-$(date +%y%m%d).txt"
		fi
}

GET_PS_PHOTO () {
	# Function to get a photo from PlaneSpotters.net
	# Usage: GET_PS_PHOTO ICAO [image|link|thumblink]
	# if [image|link|thumblink] is omitted, "link" is assumed
	# image: the path to the thumbnail image on disk
	# link: a link to the planespotters.net image page (not the image itself!)
	# thumblink: a link to the thumbnail image at planespotters.net's CDN

	local link
	local json
	local returntype
	local thumb

	returntype="${2:-link}"
	returntype="${returntype,,}"

#echo "returntype=$returntype"

	# shellcheck disable=SC2076
	if [[ ! " image link thumblink " =~ " $returntype " ]]; then
		return 1
	fi

	if ! $SHOWIMAGES; then return 0; fi

	if [[ -f "/usr/share/planefence/persist/planepix/cache/$1.notavailable" ]]; then
		return 0
	fi
	
	if [[ "$returntype" == "image" ]] && [[ -f "/usr/share/planefence/persist/planepix/cache/$1.jpg" ]]; then
		#echo in cache
		echo "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		return 0
	elif [[ "$returntype" == "link" ]] && [[ -f "/usr/share/planefence/persist/planepix/cache/$1.link" ]]; then
		#echo in cache
		echo "$(<"/usr/share/planefence/persist/planepix/cache/$1.link")"
		return 0
	elif [[ "$returntype" == "thumblink" ]] && [[ -f "/usr/share/planefence/persist/planepix/cache/$1.thumb.link" ]]; then
		#echo in cache
		echo "$(<"/usr/share/planefence/persist/planepix/cache/$1.thumb.link")"
		return 0
	fi

	# If we don't have a cached file, let's see if we can get one from PlaneSpotters.net
	if json="$(curl -ssL --fail "https://api.planespotters.net/pub/photos/hex/$1")" && \
					link="$(jq -r 'try .photos[].link | select( . != null )' <<< "$json")" && \
          thumb="$(jq -r 'try .photos[].thumbnail_large.src | select( . != null )' <<< "$json")" && \
				  [[ -n "$link" ]] && [[ -n "$thumb" ]]; then
		# If we have a link, let's download the photo
		curl -ssL --fail --clobber "$thumb" -o "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		echo "$link" > "/usr/share/planefence/persist/planepix/cache/$1.link"
		echo "$thumb" > "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
		touch -d "+$((HISTTIME+1)) days" "/usr/share/planefence/persist/planepix/cache/$1.link" "/usr/share/planefence/persist/planepix/cache/$1.thumb.link"
		#echo newly obtained
		if returntype="image"; then echo "/usr/share/planefence/persist/planepix/cache/$1.jpg"
		elif returntype="link"; then echo "$link"
		elif returntype="thumblink"; then echo "$thumb"
		fi
		return 0
	else
		# If we don't have a link, let's clear the cache and return an empty string
		rm -f "/usr/share/planefence/persist/planepix/cache/$1.*"
		touch "/usr/share/planefence/persist/planepix/cache/$1.notavailable"
	fi
}

CREATE_NOISEPLOT () {
	# usage: CREATE_NOISEPLOT <callsign> <starttime> <endtime> <icao>
  
  if [[ -z "$REMOTENOISE" ]]; then return; fi
  
  local STARTTIME="$2"
	local ENDTIME="$3"
	local TITLE="Noise plot for $1 at $(date -d "@$2" +"%y%m%d-%H%M%S")"
	local NOWTIME="$(date +%s)"
	local NOISEGRAPHFILE="$OUTFILEDIR"/"noisegraph-$(date -d "@${STARTTIME}" +"%y%m%d-%H%M%S")-$4.png"
	# if the timeframe is less than 30 seconds, extend the ENDTIME to 30 seconds
	if (( ENDTIME - STARTTIME < 15 )); then ENDTIME=$(( STARTTIME + 15 )); fi
	STARTTIME=$(( STARTTIME - 15))
	# check if there are any noise samples
	if (( (NOWTIME - ENDTIME) > (ENDTIME - STARTTIME) )) && \
			[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log" ]] && \
			[[ "$(awk -v s="$STARTTIME" -v e="$ENDTIME" '$1>=s && $1<=e' /usr/share/planefence/persist/.internal/noisecapt-"$FENCEDATE".log | wc -l)" -gt "0" ]]
	then
		gnuplot -e "offset=$(echo "$(date +%z) * 36" | sed 's/+[0]\?//g' | bc); start=$STARTTIME; end=$ENDTIME; infile='/usr/share/planefence/persist/.internal/noisecapt-$FENCEDATE.log'; outfile='$NOISEGRAPHFILE'; plottitle='$TITLE'; margin=60" $PLANEFENCEDIR/noiseplot.gnuplot
	fi
}

CREATE_SPECTROGRAM () {
	# usage: CREATE_SPECTROGRAM <starttime> <endtime>
	# returns the file name of the spectrogram it got

  if [[ -z "$REMOTENOISE" ]]; then return; fi
  
	local STARTTIME="$1"
	local ENDTIME="$2"
	local sf spectrotime
	if (( ENDTIME - STARTTIME < 30 )); then ENDTIME=$(( STARTTIME + 30 )); fi

	# get the measurement from noisecapt-"$FENCEDATE".log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	spectrotime="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /usr/share/planefence/persist/.internal/noisecapt-"$FENCEDATE".log)"
	sf="noisecapt-spectro-$(date -d "@${spectrotime}" +"%y%m%d-%H%M%S").png"

	if [[ ! -s "$OUTFILEDIR/$sf" ]]; then
		# we don't have $sf locally, or if it's an empty file, we get it:
		curl -sSL "$REMOTENOISE/$sf" > "$OUTFILEDIR/$sf"
	fi
	# shellcheck disable=SC2012
	if [[ ! -s "$OUTFILEDIR/$sf" ]] || (( $(ls -s1 "$OUTFILEDIR/$sf" | awk '{print $1}') < 10 )); then
		# we don't have $sf (or it's an empty file) and we can't get it; so let's erase it in case it's an empty file:
		rm -f "$OUTFILEDIR/$sf"
	else
		echo "$sf"
	fi
}

CREATE_MP3 () {
	# usage: CREATE_MP3 <starttime> <endtime>
	# returns the file name of the MP3 file it got

  if [[ -z "$REMOTENOISE" ]]; then return; fi

	local STARTTIME="$1"
	local ENDTIME="$2"
	local mp3time mp3f
	(( ENDTIME - STARTTIME < 30 )) && ENDTIME=$(( STARTTIME + 30 ))

	# get the measurement from noisecapt-"$FENCEDATE".log that contains the peak value
	# limited by $STARTTIME and $ENDTIME, and then get the corresponding spectrogram file name
	mp3time="$(awk -F, -v a="$STARTTIME" -v b="$ENDTIME" 'BEGIN{c=-999; d=0}{if ($1>=0+a && $1<=1+b && $2>0+c) {c=$2; d=$1}} END{print d}' /usr/share/planefence/persist/.internal/noisecapt-"$FENCEDATE".log)"
	mp3f="noisecapt-recording-$(date -d "@${mp3time}" +"%y%m%d-%H%M%S").mp3"

	if [[ ! -s "$OUTFILEDIR/$mp3f" ]]; then
		# we don't have $sf locally, or if it's an empty file, we get it:
		curl -sSL "$REMOTENOISE/$mp3f" > "$OUTFILEDIR/$mp3f"
	fi 
	# shellcheck disable=SC2012
	if [[ ! -s "$OUTFILEDIR/$mp3f" ]] || (( $(ls -s1 "$OUTFILEDIR/$mp3f" | awk '{print $1}') < 4 )); then
		# we don't have $mp3f (or it's an empty file) and we can't get it; so let's erase it in case it's an empty file:
		rm -f "$OUTFILEDIR/$mp3f"
	else
		echo "$mp3f"
	fi
}

LOG "-----------------------------------------------------"
# Function to write an HTML table from a CSV file
LOG "Defining WRITEHTMLTABLE"
WRITEHTMLTABLE () {
	# -----------------------------------------
	# Next create an HTML table from the CSV file
	# Usage: WRITEHTMLTABLE INPUTFILE OUTPUTFILE
	LOG "WRITEHTMLTABLE $1 $2"

	# if the CSV file doesn't exist, then simply return
	if [[ ! -f "$1" ]]; then return 0; fi

	# read the records from the CSV file into an assoc array called 'records'
	declare -A records
	local counter=0
	local HASNOISE=false
	local HASNOTIFS=false
	local HASROUTE=false
	local INPUTFILE="$(<"$1")"

	# Replace the map zoom by whatever $HEATMAPZOOM contains
	## shellcheck disable=SC2001
	if [[ -n "$HEATMAPZOOM" ]]; then INPUTFILE=$(sed 's|\(^.*&zoom=\)[0-9]*\(.*\)|\1'"$HEATMAPZOOM"'\2|' <<< "$INPUTFILE"); fi

	# check if INPUTFILE is updated since last run. If it is, then process it. If it isn't, then simply read the associated array from the cache
	if [[ ! -f /tmp/planefence-input.cache ]] || [[ ! -f /tmp/planefence-array.cache ]] || [[ -n "$(diff -q "$1" /tmp/planefence-input.cache)" ]]; then
		"${s6wrap[@]}" echo "Processing $1 (cache miss)"
		while read -r line; do
			# filling an Associative Array with the following structure: records[$index:key], where:
			# $index is a counter starting at 0 for each of the times
			# icao: ICAO hex ID
			# callsign: flight number or tail number
			# route: route (airport codes)
			# notified: notification has been sent (true/false)
			# firstseen: date/time first seen in secs since epoch
			# lastseen: date/time last seen in secs since epoch
			# altitude: lowest altitude observed
			# distance: minimum distance observed
			# map_link: link to ADSBX or other tar1090 style map
			# fa_link: link to flightaware
			# owner: owner or airline name
			# notif_link: link to notification
			# notif_service: "BlueSky", "Mastodon", or "yes"
			# image_thumblink: link to image thumbnail
			# image_weblink: link to image page at planespotters.net
			# sound_peak: peak sound level (if NoiseCapt is configured)
			# sound_1min: 1 minute sound level (if NoiseCapt is configured)
			# sound_5min: 5 minute sound level (if NoiseCapt is configured)
			# sound_10min: 10 minute sound level (if NoiseCapt is configured)
			# sound_1hour: 1 hour sound level (if NoiseCapt is configured)
			# sound_loudness: loudness level (if NoiseCapt is configured)
			# sound_color: background color corresponding to sound_loudness level
			# noisegraph_file: path of noisegraph file  (if NoiseCapt is configured)
			# noisegraph_link: link to noisegraph file  (if NoiseCapt is configured)
			# spectro_file: path of spectrogram file  (if NoiseCapt is configured)
			# spectro_link: link to spectrogram file  (if NoiseCapt is configured)
			# mp3_file: path of mp3 file  (if NoiseCapt is configured)
			# mp3_link: link to mp3 file  (if NoiseCapt is configured)
			#
			# additionally, the following are local variables:
			# maxindex: highest index number (useful for looping)
			# HASNOISE: true if noise data is present in the array
			# HASNOTIFS: true if notifications have been sent
			# HASROUTE: true if a route is available

			if [[ -z "$line" ]]; then continue; fi
			readarray -d, -t data <<< "$line"
			index="$((counter++))"	# we can't just use the ICAO because there can be multiple observations in a single day
			records[$index:icao]="${data[0]^^}"
			records[$index:callsign]="${data[1]//@/}"
			if [[ "${data[1]:0:1}" == "@" ]]; then
				records[$index:notified]=true
				HASNOTIFS=true
			else
				records[$index:notified]=false
			fi
			
			if ! chk_disabled "$CHECKROUTE"; then records[$index:route]="$(GET:ROUTE "${records[$index:callsign]}")"; fi
			if [[ -n "${records[$index:route]}" ]]; then HASROUTE=true; fi

			records[$index:firstseen]="$(date -d "${data[2]}" +%s)"
			records[$index:lastseen]="$(date -d "${data[3]}" +%s)"
			records[$index:altitude:value]="$(sed ':a;s/\B[0-9]\{3\}\>/,&/g;ta' <<< "${data[4]//$'\n'/}")"
			records[$index:distance:value]="${data[5]//$'\n'/}"
			records[$index:link:map]="${data[6]//globe.adsbexchange.com/"$TRACKSERVICE"}"
			records[$index:link:fa]="https://flightaware.com/live/modes/${records[$index:icao]}/ident/${records[$index:callsign]}/redirect"
			records[$index:owner]="$(/usr/share/planefence/airlinename.sh "${records[$index:callsign]}" "${records[$index:icao]}")"
			records[$index:owner]="${records[$index:owner]:-unknown}"
			records[$index:notif:link]="${data[7]//$'\n'/}" 	# this will be adjusted if there's noise data
			if [[ ${records[$index:callsign]} =~ ^N[0-9][0-9a-zA-Z]+$ ]] && \
				[[ "${records[$index:callsign]:0:4}" != "NATO" ]] && \
				[[ "${records[$index:icao]:0:1}" == "A" ]]
			then
				records[$index:link:faa]="https://registry.faa.gov/AircraftInquiry/Search/NNumberResult?nNumberTxt=${records[$index:callsign]}"
			fi

			# get an image links
			records[$index:image:thumblink]="$(GET_PS:PHOTO "${records[$index:icao]}" thumblink)"
			records[$index:image:weblink]="$(GET_PS:PHOTO "${records[$index:icao]}" link)"
		
			if [[ -n "$REMOTENOISE" ]] && [[ -z "${data[7]//[0-9.$'\n'-]/}" ]]; then
				# there is sound level information
				HASNOISE=true
				records[$index:sound:peak]="${data[7]//$'\n'/}"
				records[$index:sound:1min]="${data[8]//$'\n'/}"
				records[$index:sound:5min]="${data[9]//$'\n'/}"
				records[$index:sound:10min]="${data[10]//$'\n'/}"
				records[$index:sound:1hour]="${data[11]//$'\n'/}"
				if [[ -n "${records[$index:sound:peak]}" ]]; then records[$index:sound:loudness]="$(( data[7] - data[11] ))"; fi
				records[$index:notif:link]="${data[12]//$'\n'/}"
				{ # get a noise graph if one doesn't exist
					# $NOISEGRAPHFILE is the full file path, NOISEGRAPHLINK is the subset with the filename only
					records[$index:noisegraph:file]="$OUTFILEDIR"/"noisegraph-$(date -d "@${records[$index:firstseen]}" +"%y%m%d-%H%M%S")-${records[$index:icao]}.png"
					records[$index:noisegraph:link]="$(basename "${records[$index:noisegraph:file]}")"
					# If no noisegraph exists, create one:
					if [[ ! -f "${records[$index:noisegraph:file]}" ]]; then
						CREATE_NOISEPLOT "${records[$index:callsign]}" "${records[$index:firstseen]}" "${records[$index:lastseen]}" "${records[$index:icao]}"
						if [[ ! -f "${records[$index:noisegraph:file]}" ]]; then
							unset "${records[$index:noisegraph:file]}" "${records[$index:noisegraph:link]}"
						fi
					fi
				}
				{ # get a spectrogram if one doesn't exist
					records[$index:spectro:file]="$(CREATE:SPECTROGRAM "${records[$index:firstseen]}" "${records[$index:lastseen]}")"
					if [[ -n "${records[$index:spectro:file]}" ]]; then
						records[$index:spectro:link]="$(basename "${records[$index:spectro:file]}")"
					fi
				}
				{ # get a MP3 if one doesn't exist
				records[$index:mp3:file]="$(CREATE:MP3 "${records[$index:firstseen]}" "${records[$index:lastseen]}")"
				if [[ -n "${records[$index:mp3:file]}" ]]; then
					records[$index:mp3:link]="$(basename "${records[$index:mp3:file]}")"
				fi
				}
				{ # determine loudness background color
					if [[ -n "${records[$index:sound:loudness]}" ]]; then 
						records[$index:sound:color]="$RED"
						if (( ${records[$index:sound:loudness]} <= YELLOWLIMIT )); then records[$index:sound:color]="$YELLOW"; fi
						if (( ${records[$index:sound:loudness]} <= GREENLIMIT )); then records[$index:sound:color]="$GREEN"; fi
					fi
				}
			fi

			# get notification service name
			if "${records[$index:notified]}"; then
				records[$index:notif:service]="yes"
			else
				records[$index:notif:service]="no"
			fi
			if [[ -n "${records[$index:notif:link]}" ]]; then
				if [[ "${records[$index:notif:link]}" == "mqtt" ]]; then
					records[$index:notif:service]="MQTT"
					records[$index:notif:link]=""
				elif [[ "${records[$index:notif:link]:0:17}" == "https://bsky.app/" ]]; then records[$index:notif:service]="BlueSky"
				elif [[ "${records[$index:notif:link]:0:13}" == "https://t.me/" ]]; then records[$index:notif:service]="Telegram"
				elif grep -qo "$MASTODON_SERVER" <<< "${records[$index:notif:link]}"; then records[$index:notif:service]="Mastodon"
				fi
				if [[ -n "${records[$index:notif:link]}" ]]; then
					if [[ "${records[$index:notif:link]}" == "mqtt" ]]; then
						records[$index:notif:service]="MQTT"
						records[$index:notif:link]=""
					elif [[ "${records[$index:notif:link]:0:17}" == "https://bsky.app/" ]]; then records[$index:notif:service]="BlueSky"
					elif [[ "${records[$index:notif:link]:0:13}" == "https://t.me/" ]]; then records[$index:notif:service]="Telegram"
					elif grep -qo "$MASTODON_SERVER" <<< "${records[$index:notif:link]}"; then records[$index:notif:service]="Mastodon"
					fi
				fi
			fi

		done <<< "$INPUTFILE"
		maxindex="$((--counter))"
		# write the array to a cache file
		declare -p records 2>/dev/null > "/tmp/planefence-array.cache" || true
		{ echo "maxindex=$maxindex"
			echo "HASNOISE=$HASNOISE"
			echo "HASNOTIFS=$HASNOTIFS"
			echo "HASROUTE=$HASROUTE"
		} >> /tmp/planefence-array.cache
	else
		"${s6wrap[@]}" echo "Reading records from cache (cache hit)"
		source /tmp/planefence-array.cache
	fi
	cp -f "$1" /tmp/planefence-input.cache

	# Now write the HTML table header
	# open file for writing as fd 3
	exec 3>>"$2"

	cat >&3 <<EOF
	<table border="1" class="display planetable" id="mytable" style="width: auto; text-align: left; align: left" align="left">
	<thead border="1">
	<tr>
	<th style="width: auto; text-align: center">No.</th>
	$(${SHOWIMAGES} && echo "<th style=\"width: auto; text-align: center\">Aircraft Image</th>" || true)
	<th style="width: auto; text-align: center">Transponder ID</th>
	<th style="width: auto; text-align: center">Flight</th>
	$(${HASROUTE} && echo "<th style=\"width: auto; text-align: center\">Flight Route</th>" || true)
	<th style="width: auto; text-align: center">Airline or Owner</th>"
	<th style="width: auto; text-align: center">Time First Seen</th>
	<th style="width: auto; text-align: center">Time Last Seen</th>
	<th style="width: auto; text-align: center">Min. Altitude</th>
	<th style="width: auto; text-align: center">Min. Distance</th>
EOF

	if "$HASNOISE"; then
		# print the headers for the standard noise columns
		cat >&3 <<EOF
	<th style="width: auto; text-align: center">Loudness</th>
	<th style="width: auto; text-align: center">Peak RMS sound</th>
	<th style="width: auto; text-align: center">1 min avg</th>
	<th style="width: auto; text-align: center">5 min avg</th>
	<th style="width: auto; text-align: center">10 min avg</th>
	<th style="width: auto; text-align: center">1 hr avg</th>
	<th style="width: auto; text-align: center">Spectrogram</th>
EOF
	fi

	if "$HASNOTIFS"; then
		# print a header for the Notified column
		printf "	<th style=\"width: auto; text-align: center\">Notified</th>\n" >&3
	fi

	if chk_enabled "$SHOWIGNORE"; then
		# print a header for the Ignore column
		printf "	<th style=\"width: auto; text-align: center\">Ignore</th>\n" >&3
		PFIGNORELIST="$(<"/usr/share/planefence/persist/planefence-ignore.txt")"
	fi
	printf "	</tr></thead>\n<tbody border=\"1\">\n" >&3

	# Now write the table

	for (( index=0 ; index<=maxindex ; index++ )); do

		printf "<tr>\n" >&3
		printf "   <td style=\"text-align: center\">%s</td><!-- row 1: index -->\n" "$index" >&3 # table index number

		if ${SHOWIMAGES} && [[ -n "${records[$index:image:thumblink]}" ]]; then
			printf "   <td><a href=\"%s\" target=_blank><img src=\"%s\" style=\"width: auto; height: 75px;\"></a></td><!-- image file and link to planespotters.net -->\n" "${records[$index:image:weblink]}" "${records[$index:image:thumblink]}" >&3
		elif ${SHOWIMAGES}; then
			printf "   <td></td><!-- images enabled but no image file available for this entry -->\n" >&3
		fi

		printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- ICAO with map link -->\n" "${records[$index:link:map]}" "${records[$index:icao]}" >&3 # ICAO

		printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- Flight number/tail with FlightAware link -->\n" "${records[$index:link:fa]}" "${records[$index:callsign]}" >&3 # Flight number/tail with FlightAware link

		if ${HASROUTE}; then 
			printf "   <td>%s</td><!-- route -->\n" "${records[$index:route]}" >&3 # route
		fi

		if [[ -n "${records[$index:link:faa]}" ]]; then
			printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- owner with FAA link -->\n" "${records[$index:link:faa]}" "${records[$index:owner]}" >&3
		else
			printf "   <td>%s</td><!-- owner -->\n" "${records[$index:owner]}" >&3
		fi

		printf "   <td style=\"text-align: center\">%s</td><!-- date/time first seen -->\n" "$(date -d "@${records[$index:firstseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" >&3 # time first seen

		printf "   <td style=\"text-align: center\">%s</td><!-- date/time last seen -->\n" "$(date -d "@${records[$index:lastseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" >&3 # time last seen

		printf "   <td>%s %s %s</td><!-- min altitude -->\n" "${records[$index:altitude:value]}" "$ALTUNIT" "$ALTREFERENCE" >&3 # min altitude
		printf "   <td>%s %s</td><!-- min distance -->\n" "${records[$index:distance:value]}" "$DISTUNIT" >&3 # min distance

		# Print the noise values if we have determined that there is data
		if "$HASNOISE"; then
			# First the loudness field, which needs a color and a link to a noise graph:
			if [[ -n "${records[$index:noisegraph:link]}" ]]; then
				printf "   <td style=\"background-color: %s\"><a href=\"%s\" target=\"_blank\">%s dB</a></td><!-- loudness with noisegraph -->\n" "${records[$index:sound_color]}" "${records[$index:noisegraph:link]}" "${records[$index:sound:loudness]}" >&3
			else
				printf "   <td style=\"background-color: %s\">%s dB</td><!-- loudness (no noisegraph available) -->\n" "${records[$index:sound:color]}" "${records[$index:sound:loudness]}" >&3
			fi
			if [[ -n "${records[$index:mp3:link]}" ]]; then 
				printf "   <td><a href=\"%s\" target=\"_blank\">%s dBFS</td><!-- peak RMS value with MP3 link -->\n" "${records[$index:mp3:link]}" "${records[$index:sound:peak]}" >&3 # print actual value with "dBFS" unit
			else
				printf "   <td>%s dBFS</td><!-- peak RMS value (no MP3 recording available) -->\n" "${records[$index:sound:peak]}" >&3 # print actual value with "dBFS" unit
			fi
			printf "   <td>%s dBFS</td><!-- 1 minute avg audio levels -->\n" "${records[$index:sound:1min]}" >&3
			printf "   <td>%s dBFS</td><!-- 5 minute avg audio levels -->\n" "${records[$index:sound:5min]}" >&3
			printf "   <td>%s dBFS</td><!-- 10 minute avg audio levels -->\n" "${records[$index:sound:10min]}" >&3
			printf "   <td>%s dBFS</td><!-- 1 hour avg audio levels -->\n" "${records[$index:sound:1hour]}" >&3
			printf "   <td><a href=\"%s\" target=\"_blank\">Spectrogram</a></td><!-- spectrogram -->\n" "${records[$index:spectro:link]}" >&3 # print spectrogram
		fi

		# Print a notification, if there are any:
		if "$HASNOTIFS"; then
				if [[ -n "${records[$index:notif:link]}" ]]; then
					printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- notification link and service -->\n" "${records[$index:notif:link]}" "${records[$index:notif:service]}" >&3
				else
					printf "   <td>%s</td><!-- notified yes or no -->\n"  "${records[$index:notif:service]}" >&3
				fi
		fi

		# Print a delete button, if we have the SHOWIGNORE variable set
		if chk_enabled "$SHOWIGNORE"; then
			# If the record is in the ignore list, then print an "UnIgnore" button, otherwise print an "Ignore" button
			if ! grep -q -i "${records[$index:icao]}" <<< "$PFIGNORELIST"; then
				printf "   <td><form id=\"ignoreForm\" action=\"manage_ignore.php\" method=\"get\">
												<input type=\"hidden\" name=\"mode\" value=\"pf\">
												<input type=\"hidden\" name=\"action\" value=\"add\">
												<input type=\"hidden\" name=\"term\" value=\"%s\">
												<input type=\"hidden\" name=\"uuid\" value=\"%s\">
												<input type=\"hidden\" id=\"currentUrl\" name=\"callback\">
												<button type=\"submit\" onclick=\"return prepareSubmit()\">Ignore</button></form></td>" \
					"${records[$index:icao]}" "$uuid" >&3
			else
				printf "   <td><form id=\"ignoreForm\" action=\"manage_ignore.php\" method=\"get\">
												<input type=\"hidden\" name=\"mode\" value=\"pf\">
												<input type=\"hidden\" name=\"action\" value=\"delete\">
												<input type=\"hidden\" name=\"term\" value=\"%s\">
												<input type=\"hidden\" name=\"uuid\" value=\"%s\">
												<input type=\"hidden\" id=\"currentUrl\" name=\"callback\">
												<button type=\"submit\" onclick=\"return prepareSubmit()\">UnIgnore</button></form></td>" \
					"${records[$index:icao]}" "$uuid" >&3
			fi
		fi	
		printf "</tr>\n" >&3

	done
	printf "</tbody>\n</table>\n" >&3
	exec 3>&-
}

# Function to write the Planefence history file
LOG "Defining WRITEHTMLHISTORY"
WRITEHTMLHISTORY () {
	# -----------------------------------------
	# Write history file from directory
	# Usage: WRITEHTMLTABLE PLANEFENCEDIRECTORY OUTPUTFILE [standalone]
	LOG "WRITEHTMLHISTORY $1 $2 $3"
	if [[ "$3" == "standalone" ]]; then
		printf "<html>\n<body>\n" >>"$2"
	fi

	cat <<EOF >>"$2"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details open>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Historical Data</summary>
	<p>Today: <a href="index.html" target="_top">html</a> - <a href="planefence-$FENCEDATE.csv" target="_top">csv</a>
EOF

	# loop through the existing files. Note - if you change the file format, make sure to yodate the arguments in the line
	# right below. Right now, it lists all files that have the planefence-20*.html format (planefence-200504.html, etc.), and then
	# picks the newest 7 (or whatever HISTTIME is set to), reverses the strings to capture the characters 6-11 from the right, which contain the date (200504)
	# and reverses the results back so we get only a list of dates in the format yymmdd.
	
	if compgen -G "$1/planefence-??????.html" >/dev/null; then
		# shellcheck disable=SC2012
		for d in $(ls -1 "$1"/planefence-??????.html | tail --lines=$((HISTTIME+1)) | head --lines="$HISTTIME" | rev | cut -c6-11 | rev | sort -r)
		do
			{ printf " | %s" "$(date -d "$d" +%d-%b-%Y): "
			printf "<a href=\"%s\" target=\"_top\">html</a> - " "planefence-$(date -d "$d" +"%y%m%d").html"
			printf "<a href=\"%s\" target=\"_top\">csv</a>" "planefence-$(date -d "$d" +"%y%m%d").csv"
			} >> "$2"
		done
	fi
	{ printf "</p>\n"
	  printf "<p>Additional dates may be available by browsing to planefence-yymmdd.html in this directory.</p>"
	  printf "</details>\n</article>\n</section>"
	} >> "$2"

	# and print the footer:
	if [[ "$3" == "standalone" ]]; then
		printf "</body>\n</html>\n" >>"$2"
	fi
}

# file used to store the line progress at the start of the prune interval
PRUNESTARTFILE=/run/socket30003/.lastprunecount
# for detecting change of day
LASTFENCEFILE=/usr/share/planefence/persist/.internal/lastfencedate

# Here we go for real:
LOG "Initiating Planefence"
LOG "FENCEDATE=$FENCEDATE"
# First - if there's any command line argument, we need to do a full run discarding all cached items
if [[ "$1" != "" ]]; then
	rm "$LASTFENCEFILE"  2>/dev/null
	rm "$PRUNESTARTFILE"  2>/dev/null
	rm "$TMPLINES"  2>/dev/null
	rm "$OUTFILEHTML"  2>/dev/null
	rm "$OUTFILECSV"  2>/dev/null
	rm "$OUTFILEBASE-$FENCEDATE"-table.html  2>/dev/null
	rm "$OUTFILETMP"  2>/dev/null
	rm "$TMPDIR"/dump1090-pf*  2>/dev/null
	LOG "File cache reset- doing full run for $FENCEDATE"
fi

[[ "$BASETIME" != "" ]] && echo "1. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- start prune socket30003 data" || true

# find out the number of lines previously read
if [[ -f "$TMPLINES" ]]; then
	read -r READLINES < "$TMPLINES"
else
	READLINES=0
fi
# shellcheck disable=SC2153
if [[ -f "$TOTLINES" ]]; then
	read -r TOTALLINES < "$TOTLINES"
else
	TOTALLINES=0
fi
if [[ -f "$LASTFENCEFILE" ]]; then
	read -r LASTFENCEDATE < "$LASTFENCEFILE"
else
    # file is missing, assume we ran last yesterday
	LASTFENCEDATE=$(date --date="yesterday" '+%y%m%d')
fi

# delete some of the existing TMP files, so we don't leave any garbage around
# this is less relevant for today's file as it will be overwritten below, but this will
# also delete previous days' files that may have left behind
rm -f "$TMPLINES"
rm -f "$OUTFILETMP"

# before anything else, let's determine our current line count and write it back to the temp file
# We do this using 'wc -l', and then strip off all character starting at the first space
SOCKETFILE="$LOGFILEBASE$FENCEDATE.txt"
[[ -f "$SOCKETFILE" ]] && CURRCOUNT=$(wc -l "$SOCKETFILE" |cut -d ' ' -f 1) || CURRCOUNT=0

if [[ "$READLINES" -gt "$CURRCOUNT" ]]; then
	# Houston, we have a problem. READLINES is an earlier snapshot of the number of records, which should always be GE CURRCOUNT.
	# If it's not, this means most probably that the socket30003 logfile got reset, (again) probably because the container was restarted.
	# In this case, we want to use all lines from the socket30003 logfile.
	# There are some chances that we may process records we've already processed before, but this is improbably and we will take the risk.
	READLINES=0
fi

PRUNEMINS=180 # 3h

SOCKETFILEYESTERDAY="$LOGFILEBASE$(date -d yesterday +%y%m%d).txt"
if [[ -f $SOCKETFILEYESTERDAY ]] && (( $(date -d "1970-01-01 $(date +%T) +0:00" +%s) > PRUNEMINS * 60 ))
then
    # If we're longer than PRUNEMINS into today, remove yesterday's file
    rm -v -f "$SOCKETFILEYESTERDAY"
fi

# if the PRUNESTARTFILE file doesn't exist
# note down that we started up, write down 0 for the next prune as nothing will be older than PRUNEMINS
if [[ ! -f "$PRUNESTARTFILE" ]] || [[ "$LASTFENCEDATE" != "$FENCEDATE" ]]; then
    echo 0 > $PRUNESTARTFILE
# if PRUNESTARTFILE is older than PRUNEMINS, do the pruning
elif [[ $(find $PRUNESTARTFILE -mmin +$PRUNEMINS | wc -l) == 1 ]]; then
	read -r CUTLINES < "$PRUNESTARTFILE"
    if (( $(wc -l < "$SOCKETFILE") < CUTLINES )); then
        LOG "PRUNE ERROR: can't retain more lines than $SOCKETFILE has, retaining all lines, regular prune after next interval."
        CUTLINES=0
    fi
    tmpfile=$(mktemp)
    tail --lines=+$((CUTLINES + 1)) "$SOCKETFILE" > "$tmpfile"

    # restart Socket30003 to ensure that things run smoothly:
    touch /tmp/socket-cleanup   # this flags the socket30003 runfile not to complain about the exit and restart immediately
    killall /usr/bin/perl
    sleep .1 # give the script a moment to exit, then move the files

    mv -f "$tmpfile" "$SOCKETFILE"
    rm -f "$tmpfile"

    # update line numbers
    (( READLINES -= CUTLINES ))
    (( CURRCOUNT -= CUTLINES ))

    LOG "pruned $CUTLINES lines from $SOCKETFILE, current lines $CURRCOUNT"
    # socket30003 will start up on its own with a small delay

    # note the current position in the file, the next prune run will cut everything above that line
    echo $READLINES > $PRUNESTARTFILE
fi

# Now write the $CURRCOUNT back to the TMP file for use next time Planefence is invoked:
echo "$CURRCOUNT" > "$TMPLINES"

if [[ "$LASTFENCEDATE" != "$FENCEDATE" ]]; then
    TOTALLINES=0
    READLINES=0
fi

# update TOTALLINES and write it back to the file
TOTALLINES=$(( TOTALLINES + CURRCOUNT - READLINES ))
echo "$TOTALLINES" > "$TOTLINES"

LOG "Current run starts at line $READLINES of $CURRCOUNT, with $TOTALLINES lines for today"

# Now create a temp file with the latest logs
tail --lines=+"$READLINES" "$SOCKETFILE" > "$INFILETMP"

[[ "$BASETIME" != "" ]] && echo "2. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- invoking planefence.py" || true

# First, run planefence.py to create the CSV file:
LOG "Invoking planefence.py..."
$PLANEFENCEDIR/planefence.py --logfile="$INFILETMP" --outfile="$OUTFILETMP" --maxalt="$MAXALT" --altcorr="${ALTCORR:-0}" --dist="$DIST" --distunit="$DISTUNIT" --lat="$LAT" --lon="$LON" "$VERBOSE" "$CALCDIST" --trackservice="adsbexchange" | LOG
LOG "Returned from planefence.py..."

# Now we need to combine any double entries. This happens when a plane was in range during two consecutive Planefence runs
# A real simple solution could have been to use the Linux 'uniq' command, but that won't allow us to easily combine them

# Compare the last line of the previous CSV file with the first line of the new CSV file and combine them if needed
# Only do this is there are lines in both the original and the TMP csv files

[[ "$BASETIME" != "" ]] && echo "3. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- returned from planefence.py, start pruning duplicates" || true

if [[ -f "$OUTFILETMP" ]] && [[ -f "$OUTFILECSV" ]]; then
	while read -r newline
	do
		IFS="," read -ra newrec <<< "$newline"
		if grep -q "^${newrec[0]}," "$OUTFILECSV"
		then
#debug echo -n "There is a matching ICAO... ${newrec[1]} "
			# there's a ICAO match between the new record and the existing file
			# grab the last occurrence of the old record
			oldline=$(grep "^${newrec[0]}," "$OUTFILECSV" 2>/dev/null | tail -1)
			IFS="," read -ra oldrec <<< "$oldline"
			if (( $(date -d "${newrec[2]}" +%s) - $(date -d "${oldrec[3]}" +%s) > COLLAPSEWITHIN ))
			then
				# we're outside the collapse window. Write the string to $OUTFILECSV
				echo "$newline" >> "$OUTFILECSV"
#debug echo "outside COLLAPSE window: old end=${oldrec[3]} new start=${newrec[2]}"
			else
				# we are inside the collapse window and need to collapse the records.
				# Insert newrec's end time into oldrec. Do this ONLY for the line where the ICAO and the start time matches:
				# we also need to take the smallest altitude and distance
				(( $(echo "${newrec[4]} < ${oldrec[4]}" | bc -l) )) && NEWALT=${newrec[4]} || NEWALT=${oldrec[4]}
				(( $(echo "${newrec[5]} < ${oldrec[5]}" | bc -l) )) && NEWDIST=${newrec[5]} || NEWDIST=${oldrec[5]}
				sed -i "s|\(${oldrec[0]}\),\([A-Z0-9@-]*\),\(${oldrec[2]}\),\([0-9 /:]*\),\([0-9]*\),\([0-9\.]*\),\(.*\)|\1,\2,\3,${newrec[3]},$NEWALT,$NEWDIST,\7|" "$OUTFILECSV"
				#           ^  ICAO    ^     ^ flt/tail ^   ^ starttime  ^   ^ endtime ^  ^ alt    ^   ^dist^    ^rest^
				#               \1              \2              \3                \4          \5         \6        \7
				#sed -i "s|\(${oldrec[0]}\),\([A-Z0-9@-]*\),\(${oldrec[2]}\),\([0-9 /:]*\),\(.*\)|\1,\2,\3,${newrec[3]},\5|" "$OUTFILECSV"
				#            ^  ICAO    ^     ^ flt/tail ^   ^ starttime  ^   ^ endtime ^  ^rest^
#debug echo "COLLAPSE: inside collapse window: old end=${oldrec[3]} new end=${newrec[3]}"
#debug echo "sed line:"
#debug echo "sed -i \"s|\(${oldrec[0]}\),\([A-Z0-9@-]*\),\(${oldrec[2]}\),\([0-9 /:]*\),\([0-9]*\),\([0-9\.]*\),\(.*\)|\1,\2,\3,${newrec[3]},$NEWALT,$NEWDIST,\7|\" \"$OUTFILECSV\""
			fi
		else
			# the ICAO fields did not match and we should write it to the database:
#debug echo "${newrec[1]}: no matching ICAO / no collapsing considered"
			echo "$newline" >> "$OUTFILECSV"
		fi
	done < "$OUTFILETMP"
else
	# there's potentially no OUTFILECSV. Move OUTFILETMP to OUTFILECSV if one exists
	if [[ -f "$OUTFILETMP" ]]; then
		mv -f "$OUTFILETMP" "$OUTFILECSV"
		chmod a+rw "$OUTFILECSV"
	fi	
fi
rm -f "$OUTFILETMP"

[[ "$BASETIME" != "" ]] && echo "4. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done pruning duplicates, invoking noise2fence" || true

# Now check if we need to add noise data to the csv file
if [[ "$NOISECAPT" == "1" ]]; then
	LOG "Invoking noise2fence!"
	$PLANEFENCEDIR/noise2fence.sh
else
	LOG "Info: Noise2Fence not enabled"
fi

[[ "$BASETIME" != "" ]] && echo "5. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done invoking noise2fence, applying dirty fixes" || true

#Dirty fix -- sometimes the CSV file needs fixing
$PLANEFENCEDIR/pf-fix.sh "$OUTFILECSV"

[[ "$BASETIME" != "" ]] && echo "6. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done applying dirty fixes, applying filters" || true

# Ignore list -- first clean up the list to ensure there are no empty lines
# shellcheck disable=SC2153
sed -i '/^$/d' "$IGNORELIST" 2>/dev/null
# now apply the filter
# shellcheck disable=SC2126
LINESFILTERED=$(grep -i -f "$IGNORELIST" "$OUTFILECSV" 2>/dev/null | wc -l)
if (( LINESFILTERED > 0 ))
then
	grep -v -i -f "$IGNORELIST" "$OUTFILECSV" > /tmp/pf-out.tmp
	mv -f /tmp/pf-out.tmp "$OUTFILECSV"
fi

# rewrite LINESFILTERED to file
if [[ -f /run/planefence/filtered-$FENCEDATE ]]; then
	read -r i < "/run/planefence/filtered-$FENCEDATE"
else
	i=0
fi
echo $((LINESFILTERED + i)) > "/run/planefence/filtered-$FENCEDATE"

# if IGNOREDUPES is ON then remove duplicates
if [[ "$IGNOREDUPES" == "ON" ]]; then
	LINESFILTERED=$(awk -F',' 'seen[$1 gsub("/@/","", $2)]++' "$OUTFILECSV" 2>/dev/null | wc -l)
	if (( i>0 ))
	then
		# awk prints only the first instance of lines where fields 1 and 2 are the same
		awk -F',' '!seen[$1 gsub("/@/","", $2)]++' "$OUTFILECSV" > /tmp/pf-out.tmp
		mv -f /tmp/pf-out.tmp "$OUTFILECSV"
	fi
	# rewrite LINESFILTERED to file
	if [[ -f /run/planefence/filtered-$FENCEDATE ]]; then
		read -r i < "/run/planefence/filtered-$FENCEDATE"
	else
		i=0
	fi
	echo $((LINESFILTERED + i)) > "/run/planefence/filtered-$FENCEDATE"

fi

# see if we need to invoke PlaneTweet:
[[ "$BASETIME" != "" ]] && echo "7. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done applying filters, invoking PlaneTweet" || true

if chk_enabled "$PLANETWEET" \
   || chk_enabled "${PF_DISCORD}" \
   || chk_enabled "$PF_MASTODON" \
   || [[ -n "$BLUESKY_HANDLE" ]] \
   || [[ -n "$RSS_SITELINK" ]] \
	 || chk_enabled "$PF_TELEGRAM_ENABLED" \
   || [[ -n "$MQTT_URL" ]]; then
	LOG "Invoking planefence_notify.sh for notifications"
	$PLANEFENCEDIR/planefence_notify.sh today "$DISTUNIT" "$ALTUNIT"
else
 [[ "$1" != "" ]] && LOG "Info: planefence_notify.sh not called because we're doing a manual full run" || LOG "Info: PlaneTweet not enabled"
fi

# run planefence-rss.sh in the background:
{ timeout 120 /usr/share/planefence/planefence-rss.sh; } &

[[ "$BASETIME" != "" ]] && echo "8. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done invoking planefence_notify.sh, invoking PlaneHeat" || true

# And see if we need to run PLANEHEAT
if chk_enabled "$PLANEHEAT" && [[ -f "${PLANEHEATSCRIPT}" ]] # && [[ -f "$OUTFILECSV" ]]  <-- commented out to create heatmap even if there's no data
then
	LOG "Invoking PlaneHeat!"
	"${s6wrap[@]}" echo "Invoking PlaneHeat..."
	$PLANEHEATSCRIPT
	LOG "Returned from PlaneHeat"
else
	LOG "Skipped PlaneHeat"
fi

# Now let's link to the latest Spectrogram, if one was generated for today:
[[ "$BASETIME" != "" ]] && echo "9. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done invoking invoking PlaneHeat, getting NoiseCapt stuff" || true

if [[ "$NOISECAPT" == "1" ]]; then
	[[ "$BASETIME" != "" ]] && echo "9a. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- getting latest Spectrogram" || true
	# get the latest spectrogram from the remote server
	curl --fail -s "$REMOTENOISE/noisecapt-spectro-latest.png" >"$OUTFILEDIR/noisecapt-spectro-latest.png"

	# also create a noisegraph for the full day:
	[[ "$BASETIME" != "" ]] && echo "9b. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- creating day-long Noise Graph" || true
	rm -f /tmp/noiselog 2>/dev/null
	[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$(date -d "yesterday" +%y%m%d).log" ]] && cp -f "/usr/share/planefence/persist/.internal/noisecapt-$(date -d "yesterday" +%y%m%d).log" /tmp/noiselog
	[[ -f "/usr/share/planefence/persist/.internal/noisecapt-$(date -d "today" +%y%m%d).log" ]] && cat "/usr/share/planefence/persist/.internal/noisecapt-$(date -d "today" +%y%m%d).log" >> /tmp/noiselog
	gnuplot -e "offset=$(echo "$(date +%z) * 36" | sed 's/+[0]\?//g' | bc); start=$(date -d "yesterday" +%s); end=$(date +%s); infile='/tmp/noiselog'; outfile='/usr/share/planefence/html/noiseplot-latest.jpg'; plottitle='Noise Plot over Last 24 Hours (End date = $(date +%Y-%m-%d))'; margin=60" $PLANEFENCEDIR/noiseplot.gnuplot
	rm -f /tmp/noiselog 2>/dev/null

elif (( $(find "$TMPDIR"/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | wc -l  ) > 0 ))
then
	ln -sf "$(find "$TMPDIR"/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | tail -1)" "$OUTFILEDIR"/noisecapt-spectro-latest.png
else
	rm -f "$OUTFILEDIR"/noisecapt-spectro-latest.png 2>/dev/null
fi

[[ "$BASETIME" != "" ]] && echo "10. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done getting NoiseCapt stuff, invoking plane-alert.sh" || true

# Next, we are going to print today's HTML file:
# Note - all text between 'cat' and 'EOF' is HTML code:

"${s6wrap[@]}" echo "Writing Planefence web page..."
[[ "$BASETIME" != "" ]] && echo "11. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s --  starting to build the webpage" || true

cat <<EOF >"$OUTFILEHTMTMP"
<!DOCTYPE html>
<html>
<!--
# You are taking an interest in this code! Great!
# I'm not a professional programmer, and your suggestions and contributions
# are always welcome. Join me at the GitHub link shown below, or via email
# at kx1t (at) kx1t (dot) com.
#
# Copyright 2020-2025 Ramon F. Kolb, kx1t - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# The package contains contributions from several other packages, that may be licensed
# under different terms. Attributions and our thanks can be found at
# https://github.com/sdr-enthusiasts/docker-planefence/blob/main/ATTRIBUTION.md
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
-->
<head>
	<link rel="icon" href="favicon.ico">
	<meta charset="UTF-8">
EOF

if chk_enabled "${AUTOREFRESH,,}"; then
	REFRESH_INT="$(sed -n 's/\(^\s*PF_INTERVAL=\)\(.*\)/\2/p' /usr/share/planefence/persist/planefence.config)"
	cat <<EOF >>"$OUTFILEHTMTMP"
	<meta http-equiv="refresh" content="$REFRESH_INT">
EOF
fi
cat <<EOF >>"$OUTFILEHTMTMP"
    <!-- scripts and stylesheets related to the datatables functionality: -->
    <!-- please note that these scripts and plugins are licensed by their authors and IP owners
         For license terms and copyright ownership, see each linked file -->
    <!-- JQuery itself: -->
    <script src="scripts/jquery-3.7.1.min.js"></script>

    <!-- DataTables CSS and plugins: -->
    <link href="scripts/dataTables.dataTables.min.css" rel="stylesheet">
    <link href="scripts/buttons.dataTables.min.css" rel="stylesheet">
    <script src="scripts/jszip.min.js"></script>
    <script src="scripts/pdfmake.min.js"></script>
    <script src="scripts/vfs_fonts.js"></script>
    <script src="scripts/dataTables.min.js"></script>
    <script src="scripts/dataTables.buttons.min.js"></script>
    <script src="scripts/buttons.html5.min.js"></script>
    <script src="scripts/buttons.print.min.js"></script>

    <!-- plugin to make JQuery table columns resizable by the user: -->
    <script src="scripts/colResizable-1.6.min.js"></script>

    <title>ADS-B 1090 MHz Planefence</title>
EOF
	
if [[ -f "$PLANEHEATHTML" ]]; then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<link rel="stylesheet" href="scripts/leaflet.css" />
	<script src="scripts/leaflet.js"></script>
EOF
fi

cat <<EOF >>"$OUTFILEHTMTMP"
<style>
body { font: 12px/1.4 "Helvetica Neue", Arial, sans-serif;
EOF
if chk_enabled "$DARKMODE"; then
	cat <<EOF >>"$OUTFILEHTMTMP"
	   background-color: black;
		 color: white;
EOF
else
	cat <<EOF >>"$OUTFILEHTMTMP"
	   background-image: url('pf_background.jpg');
	   background-repeat: no-repeat;
	   background-attachment: fixed;
  	 background-size: cover;
		 color: black;
EOF
fi
cat <<EOF >>"$OUTFILEHTMTMP"
     }
a { color: #0077ff; }
h1 {text-align: center}
h2 {text-align: center}
.planetable { border: 1; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; text-align: center }
.history { border: none; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; }
.footer{ border: none; margin: 0; padding: 0; font: 12px/1.4 "Helvetica Neue", Arial, sans-serif; text-align: center }
/* Sticky table header */
table thead tr th tbody, table.dataTable tbody th, table.dataTable tbody td {
EOF
if chk_enabled "$DARKMODE"; then
	cat <<EOF >>"$OUTFILEHTMTMP"
	   background-color: black;
		 color: white;
EOF
else
	cat <<EOF >>"$OUTFILEHTMTMP"
     background-color: #f0f6f6;
		 color: black;
EOF
fi
cat <<EOF >>"$OUTFILEHTMTMP"
     position: sticky;
     z-index: 100;
		 top: 0 !important;
		 padding: 2 !important;
		 margin-top: 1 !important;
		 margin-bottom: 1 !important;
}
td, table.dataTable tbody td {
	text-align: center;
	vertical-align: middle;
}
</style>
$(if [[ -n "$MASTODON_SERVER" ]] && [[ -n "$MASTODON_ACCESS_TOKEN" ]] && [[ -n "$MASTODON_NAME" ]]; then echo "<link href=\"https://$MASTODON_SERVER/@$MASTODON_NAME\" rel=\"me\">"; fi)
</head>

$(if chk_enabled "$DARKMODE"; then echo "<body class=\"dark\">"; else echo "<body>"; fi)
<script type="text/javascript">
    \$(document).ready(function() { 
        \$("#mytable").dataTable( {
            order: [[0, 'desc']],
            pageLength: $TABLESIZE,
            lengthMenu: [10, 25, 50, 100, { label: 'All', value: -1 }],
            layout: { top2Start: { buttons: ['copy', 'csv', 'excel', 'pdf', 'print'] },
                      top1Start: { search: { placeholder: 'Type search here' } }, 
                      topEnd: '',
                    }
        });
		    \$("#mytable").colResizable({
            liveDrag: true, 
            gripInnerHtml: "<div class='grip'></div>", 
            draggingClass: "dragging", 
            resizeMode: 'flex',
						postbackSave: true
        });
    });
</script>
<script>
	function prepareSubmit() {
			// Set the current URL without query parameters
			var cleanUrl = window.location.href.split('?')[0];
			document.getElementById('currentUrl').value = cleanUrl;
			return true;
	}
</script>

<h1>Planefence</h1>
<h2>Show aircraft in range of <a href="$MYURL" target="_top">$MY</a> ADS-B station for a specific day</h2>
${PF_MOTD}
<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
<article>
<details open>
<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Executive Summary</summary>
<ul>
  <li>Last update: $(date +"%b %d, %Y %R:%S %Z")
  <li>Maximum distance from <a href="https://www.openstreetmap.org/?mlat=$LAT_VIS&mlon=$LON_VIS#map=14/$LAT_VIS/$LON_VIS&layers=H" target=_blank>${LAT_VIS}&deg;N, ${LON_VIS}&deg;E</a>: $DIST $DISTUNIT
  <li>Only aircraft below $(printf "%'.0d" "$MAXALT" | sed ':a;s/\B[0-9]\{3\}\>/,&/g;ta') $ALTUNIT are reported
  <li>Data extracted from $(printf "%'.0d" $TOTALLINES | sed ':a;s/\B[0-9]\{3\}\>/,&/g;ta') <a href="https://en.wikipedia.org/wiki/Automatic_dependent_surveillance_%E2%80%93_broadcast" target="_blank">ADS-B messages</a> received since midnight today
EOF
{	[[ -n "$FUDGELOC" ]] && printf "  <li> Please note that the reported station coordinates and the center of the circle on the heatmap are rounded for privacy protection. They do not reflect the exact location of the station\n"
	[[ -f "/run/planefence/filtered-$FENCEDATE" ]] && [[ -f "$IGNORELIST" ]] && (( $(grep -c "^[^#;]" "$IGNORELIST") > 0 )) && printf "  <li> %d entries were filtered out today because of an <a href=\"ignorelist.txt\" target=\"_blank\">ignore list</a>\n" "$(</run/planefence/filtered-"$FENCEDATE")"
	if [[ -n "$MASTODON_SERVER" ]] && [[ -n "$MASTODON_ACCESS_TOKEN" ]] && [[ -n "$MASTODON_NAME" ]]; then
		printf   "<li>Get notified instantaneously of aircraft in range by following <a href=\"https://%s/@%s\" rel=\"me\">@%s@%s</a> on Mastodon" \
			"$MASTODON_SERVER" "$MASTODON_NAME" "$MASTODON_NAME" "$MASTODON_SERVER"
	fi
	if [[ -n "$BLUESKY_HANDLE" ]] && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then printf "<li>Planefence notifications are sent to <a href=\"https://bsky.app/profile/%s\" target=\"_blank\">@%s</a> at BlueSky \n" "$BLUESKY_HANDLE" "$BLUESKY_HANDLE"; fi
	[[ "$PLANETWEET" != "" ]] && printf "<li>Get notified instantaneously of aircraft in range by following <a href=\"http://twitter.com/%s\" target=\"_blank\">@%s</a> on Twitter!\n" "$PLANETWEET" "$PLANETWEET"
	printf "<li> A RSS feed of the aircraft detected with Planefence is available at <a href=\"planefence.rss\">planefence.rss</a>\n"
	[[ -n "$PA_LINK" ]] && printf "<li> Additionally, click <a href=\"%s\" target=\"_blank\">here</a> to visit Plane Alert: a watchlist of aircraft in general range of the station\n" "$PA_LINK" 
} >> "$OUTFILEHTMTMP"

# shellcheck disable=SC2129
cat <<EOF >>"$OUTFILEHTMTMP"
</ul>
</details>
</article>
</section>

<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
<article>
<details>
<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Click on the triangle next to the header to show/collapse the section </summary>
</details>
</article>
</section>

<section style="border: none; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
<article>
<details open>
<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Flights In Range Table</summary>
<ul>
EOF

{	printf "<li>Click on the Transponder ID to see the full flight information/history (from <a href=\"https://$TRACKSERVICE/?lat=%s&lon=%s&zoom=11.0\" target=\"_blank\">$TRACKSERVICE</a>)\n" "$LAT_VIS" "$LON_VIS"
	printf "<li>Click on the Flight Number to see the full flight information/history (from <a href=http://www.flightaware.com\" target=\"_blank\">FlightAware</a>)\n"
	printf "<li>Click on the Owner Information to see the FAA record for this plane (private, US registered planes only)\n"
	(( ALTCORR > 0 )) && printf "<li>Minimum altitude is the altitude above local ground level, which is %s %s MSL.\n" "$ALTCORR" "$ALTUNIT" || printf "<li>Minimum altitude is the altitude above sea level\n"

	[[ "$PLANETWEET" != "" ]] && printf "<li>Click on the word &quot;yes&quot; in the <b>Tweeted</b> column to see the Tweet.\n<li>Note that tweets are issued after a slight delay\n"
	(( $(find "$TMPDIR"/noisecapt-spectro*.png -daystart -maxdepth 1 -mmin -1440 -print 2>/dev/null | wc -l  ) > 0 )) && printf "<li>Click on the word &quot;Spectrogram&quot; to see the audio spectrogram of the noisiest period while the aircraft was in range\n"
  chk_enabled "$PLANEALERT" && printf "<li>See a list of aircraft matching the station's Alert List <a href=\"%s\" target=\"_blank\">here</a>\n" "${PA_LINK:-plane-alert}"
	printf "<li>Press the header of any of the columns to sort by that column\n"
	printf "</ul>\n"
} >> "$OUTFILEHTMTMP"

[[ "$BASETIME" != "" ]] && echo "12. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- starting to write the PF table to the website" || true

WRITEHTMLTABLE "$OUTFILECSV" "$OUTFILEHTMTMP"

[[ "$BASETIME" != "" ]] && echo "13. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done writing the PF table to the website" || true

cat <<EOF >>"$OUTFILEHTMTMP"
</details>
</article>
</section>
EOF

# Write some extra text if NOISE data is present
if [[ "$HASNOISE" != "false" ]]; then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Notes on sound level data</summary>
	<ul>
	<li>This data is for informational purposes only and is of indicative value only. It was collected using a non-calibrated device under uncontrolled circumstances.
	<li>The data unit is &quot;dBFS&quot; (Decibels-Full Scale). 0 dBFS is the loudest sound the device can capture. Lower values, like -99 dBFS, mean very low noise. Higher values, like -10 dBFS, are very loud.
	<li>The system measures the <a href="https://en.wikipedia.org/wiki/Root_mean_square" target="_blank">RMS</a> of the sound level for contiguous periods of 5 seconds.
	<li>'Loudness' is the difference (in dB) between the Peak RMS Sound and the 1 hour average. It provides an indication of how much louder than normal it was when the aircraft flew over.
	<li>Loudness values of greater than $YELLOWLIMIT dB are in red. Values greater than $GREENLIMIT dB are in yellow.
	<li>'Peak RMS Sound' is the highest measured 5-seconds RMS value during the time the aircraft was in the coverage area.
	<li>The subsequent values are 1, 5, 10, and 60 minutes averages of these 5 second RMS measurements for the period leading up to the moment the aircraft left the coverage area.
	<li>One last, but important note: The reported sound levels are general outdoor ambient noise in a suburban environment. The system doesn't just capture airplane noise, but also trucks on a nearby highway, lawnmowers, children playing, people working on their projects, air conditioner noise, etc.
	<ul>
	</details>
	</article>
	</section>
	<hr/>
EOF
fi

# if $PLANEHEATHTML exists, then add the heatmap
if chk_enabled "$PLANEHEAT" && [[ -f "$PLANEHEATHTML" ]]; then
	# shellcheck disable=SC2129
	cat <<EOF >>"$OUTFILEHTMTMP"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details open>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Heatmap</summary>
	<ul>
	<li>This heatmap reflects passing frequency and does not indicate perceived noise levels
	<li>The heatmap is limited to the coverage area of Planefence, for any aircraft listed in the table above
	$( [[ -d "$OUTFILEDIR/../heatmap" ]] && printf "<li>For a heatmap of all planes in range of the station, please click <a href=\"../heatmap\" target=\"_blank\">here</a>" )
	</ul>
EOF
	cat "$PLANEHEATHTML" >>"$OUTFILEHTMTMP"
	cat <<EOF >>"$OUTFILEHTMTMP"
	</details>
	</article>
	</section>
	<hr/>
EOF
fi

# If there's a latest spectrogram, show it
if [[ -f "$OUTFILEDIR/noisecapt-spectro-latest.png" ]]; then
	cat <<EOF >>"$OUTFILEHTMTMP"
	<section style="border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;">
	<article>
	<details open>
	<summary style="font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;">Latest Spectrogram</summary>
	<ul>
	<li>Latest as of the time of generation of this page
	<li>For spectrograms related to overflying aircraft, see table above
	</ul>
	<a href="noisecapt-spectro-latest.png" target="_blank"><img src="noisecapt-spectro-latest.png"></a>
	$([[ -f "/usr/share/planefence/html/noiseplot-latest.jpg" ]] && echo "<a href=\"noiseplot-latest.jpg\" target=\"_blank\"><img src=\"noiseplot-latest.jpg\"></a>")
	</details>
	</section>
	<hr/>
EOF
fi

[[ "$BASETIME" != "" ]] && echo "14. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- starting to write the history line to the website" || true
WRITEHTMLHISTORY "$OUTFILEDIR" "$OUTFILEHTMTMP"
LOG "Done writing history"
[[ "$BASETIME" != "" ]] && echo "15. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done writing the history line to the website" || true


cat <<EOF >>"$OUTFILEHTMTMP"
<div class="footer">
<hr/>Planefence $VERSION is part of <a href="https://github.com/sdr-enthusiasts/docker-planefence" target="_blank">KX1T's Planefence Open Source Project</a>, available on GitHub. Support is available on the #Planefence channel of the SDR Enthusiasts Discord Server. Click the Chat icon below to join.
$(if [[ -f /root/.buildtime ]]; then printf " Build: %s" "$([[ -f /usr/share/planefence/branch ]] && cat /usr/share/planefence/branch || cat /root/.buildtime)"; fi)
<br/>&copy; Copyright 2020-2025 by Ram&oacute;n F. Kolb, kx1t. Please see <a href="https://github.com/sdr-enthusiasts/docker-planefence/blob/main/ATTRIBUTION.md" target="_blank">here</a> for attributions to our contributors and open source packages used.
<br/><a href="https://github.com/sdr-enthusiasts/docker-planefence" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/sdr-enthusiasts/docker-planefence/deploy.yml"></a>
<a href="https://discord.gg/VDT25xNZzV"><img src="https://img.shields.io/discord/734090820684349521" alt="discord"></a>
</div>
</body>
</html>
EOF

# Last thing we need to do, is repoint INDEX.HTML to today's file

[[ "$BASETIME" != "" ]] && echo "16. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- starting final cleanup" || true

pushd "$OUTFILEDIR" > /dev/null || true
mv -f "$OUTFILEHTMTMP" "$OUTFILEHTML"
ln -sf "${OUTFILEHTML##*/}" index.html
popd > /dev/null || true

# VERY last thing... ensure that the log doesn't overflow:
if [[ "$VERBOSE" != "" ]] && [[ "$LOGFILE" != "" ]] && [[ "$LOGFILE" != "logger" ]] && [[ -f $LOGFILE ]] && (( $(wc -l < "$LOGFILE") > 8000 ))
then
    #sed -i -e :a -e '$q;N;8000,$D;ba'
    tail -n 4000 "$LOGFILE" > "$LOGFILE.tmp"
    mv -f "$LOGFILE.tmp" "$LOGFILE"
fi

echo "$FENCEDATE" > "$LASTFENCEFILE"

# If $PLANEALERT=on then lets call plane-alert to see if the new lines contain any planes of special interest:
if chk_enabled "$PLANEALERT"; then
	LOG "Calling Plane-Alert as $PLALERTFILE $INFILETMP"
	"${s6wrap[@]}" echo "Invoking Plane-Alert..."
	$PLALERTFILE "$INFILETMP"
fi

# That's all
# This could probably have been done more elegantly. If you have changes to contribute, I'll be happy to consider them for addition
# to the GIT repository! --Ramon

# Wait for any background processes to finish
# Currently, planefence_notify.sh and planefence-rss.sh are the only background processes that are invoked, and those have a time limit of 120 secs
wait $!

LOG "Finishing Planefence... sayonara!"
[[ "$BASETIME" != "" ]] && echo "17. $(bc -l <<< "$(date +%s.%2N) - $BASETIME")s -- done final cleanup" || true
"${s6wrap[@]}" echo "Done"
