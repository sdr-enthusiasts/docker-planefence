#!/command/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034,SC2154,SC2155
#
# #-----------------------------------------------------------------------------------
# PF-CREATE-HTML.SH
# Load a template, insert data, and produce a complete HTML document
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
HTMLDIR="$OUTFILEDIR"
set -eo pipefail
DEBUG=true

# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------

# First define a bunch of functions:

# Function to write the Planefence HTML table
CREATEHTMLTABLE () {

	# Write the HTML table header
	# shellcheck disable=SC2034
	table="$(
		echo "
			<table border=\"1\" class=\"display planetable\" id=\"mytable\" style=\"width: auto; text-align: left; align: left\" align=\"left\">
			<thead border=\"1\">
			<tr>
			<th style=\"width: auto; text-align: center\">No.</th>
			$(if chk_enabled "${records[HASIMAGES]}"; then echo "<th style=\"width: auto; text-align: center\">Aircraft Image</th>"; fi)
			<th style=\"width: auto; text-align: center\">Transponder ID</th>
			<th style=\"width: auto; text-align: center\">Tail</th>
			<th style=\"width: auto; text-align: center\">Flight</th>
			$(if chk_enabled "${records[HASROUTE]}"; then echo "<th style=\"width: auto; text-align: center\">Flight Route</th>"; fi)
			<th style=\"width: auto; text-align: center\">Airline or Owner</th>
			<th style=\"width: auto; text-align: center\">Time First Seen</th>
			<th style=\"width: auto; text-align: center\">Time Last Seen</th>
			<th style=\"width: auto; text-align: center\">Min. Altitude</th>
			<th style=\"width: auto; text-align: center\">Min. Distance</th>
			<th style=\"width: auto; text-align: center\">Track</th>"

		if chk_enabled "${records[HASNOISE]}"; then
			# print the headers for the standard noise columns
			echo "
			<th style=\"width: auto; text-align: center\">Loudness</th>
			<th style=\"width: auto; text-align: center\">Peak RMS sound</th>
			<th style=\"width: auto; text-align: center\">1 min avg</th>
			<th style=\"width: auto; text-align: center\">5 min avg</th>
			<th style=\"width: auto; text-align: center\">10 min avg</th>
			<th style=\"width: auto; text-align: center\">1 hr avg</th>
			<th style=\"width: auto; text-align: center\">Spectrogram</th>"
		fi

		if chk_enabled "${records[HASNOTIFS]}"; then
			# print a header for the Notified column
			printf "	<th style=\"width: auto; text-align: center\">Notified</th>\n"
		fi

		if chk_enabled "$SHOWIGNORE"; then
			# print a header for the Ignore column
			printf "	<th style=\"width: auto; text-align: center\">Ignore</th>\n"
		fi
		printf "	</tr></thead>\n<tbody border=\"1\">\n"

		# Now write the table

		for (( idx=0; idx <= records[maxindex]; idx++ )); do
			printf "<tr>\n"

			# table index number:
			printf "   <td style=\"text-align: center\">%s</td>\n" "$idx"

			# image:
			if chk_enabled "${SHOWIMAGES}" && [[ -n "${records["$idx":image:thumblink]}" ]]; then
				# shellcheck disable=SC2030
				printf "   <td><a href=\"%s\" target=_blank><img src=\"%s\" style=\"width: auto; height: 75px;\"></a></td><!-- image file and link to planespotters.net -->\n" "${records["$idx":image:link]}" "${records["$idx":image:thumblink]}"
			elif chk_enabled "${SHOWIMAGES}"; then
				printf "   <td></td><!-- images enabled but no image file available for this entry -->\n"
			fi

			# ICAO
			printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- ICAO with map link -->\n" "${records["$idx":map:link]}" "${records["$idx":icao]}"

			# Tail
			if [[ -z "${records["$idx":faa:link]}" ]]; then
				printf "   <td>%s</td><!-- Tail -->\n" "${records["$idx":tail]}"
			else
				printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- tail with FAA link -->\n" "${records["$idx":faa:link]}" "${records["$idx":tail]}"
			fi

			# Flight number
			printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- Flight number/tail with FlightAware link -->\n" "${records["$idx":fa:link]}" "${records["$idx":callsign]}"

			# Route
			if chk_enabled "${records[HASROUTE]}"; then
				printf "   <td>%s</td><!-- route -->\n" "${records["$idx":route]}"
			fi

			# Owner
			printf "   <td>%s</td><!-- owner -->\n" "${records["$idx":owner]}"

			# time first seen
			printf "   <td style=\"text-align: center\">%s</td><!-- date/time first seen -->\n" "$(date -d "@${records["$idx":firstseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")"

			# time last seen
			printf "   <td style=\"text-align: center\">%s%s</td><!-- date/time last seen -->\n" "$(date -d "@${records["$idx":lastseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" "$(if ! chk_enabled "${records["$idx":complete]}"; then echo "<br>(still processing)"; fi)"

			# min altitude
			printf "   <td>%s %s %s</td><!-- min altitude -->\n" "${records["$idx":altitude]}" "$ALTUNIT" "$ALTREFERENCE"

			# min distance
			printf "   <td>%s %s<br><img src=\"%s\"></td><!-- min distance -->\n" "${records["$idx":distance]}" "$DISTUNIT" "arrow$(( ${records["$idx":angle]%%.*} / 10 * 10 )).gif"  # round angle to nearest 10 degrees for arrow

			# track
			printf "   <td>%s<img src=\"%s\"></td><!-- track -->\n" "${records["$idx":track]}&deg;" "arrow$(( ${records["$idx":track]%%.*} / 10 * 10 )).gif"

			# Print the noise values if we have determined that there is data
			if chk_enabled "${records[HASNOISE]}"; then
				# First the loudness field, which needs a color and a link to a noise graph:
				if [[ -n "${records["$idx":noisegraph:link]}" ]]; then
					printf "   <td style=\"background-color: %s\"><a href=\"%s\" target=\"_blank\">%s %s</a></td><!-- loudness with noisegraph -->\n" "${records["$idx":sound:color]}" "${records["$idx":noisegraph:link]}" "${records["$idx":sound:loudness]}" "$([[ -n "${records["$idx":sound:loudness]}" ]] && echo "dB")"
				else
					printf "   <td style=\"background-color: %s\">%s %s</td><!-- loudness (no noisegraph available) -->\n" "${records["$idx":sound:color]}" "${records["$idx":sound:loudness]}" "$([[ -n "${records["$idx":sound:loudness]}" ]] && echo "dB")"
				fi
				if [[ -n "${records["$idx":mp3:link]}" ]]; then 
					printf "   <td><a href=\"%s\" target=\"_blank\">%s %s</td><!-- peak RMS value with MP3 link -->\n" "${records["$idx":mp3:link]}" "${records["$idx":sound:peak]}" "$([[ -n "${records["$idx":sound:peak]}" ]] && echo "dBFS")" # print actual value with "dBFS" unit
				else
					printf "   <td>%s %s</td><!-- peak RMS value (no MP3 recording available) -->\n" "${records["$idx":sound:peak]}" "$([[ -n "${records["$idx":sound:peak]}" ]] && echo "dBFS")" # print actual value with "dBFS" unit
				fi
				printf "   <td>%s %s</td><!-- 1 minute avg audio levels -->\n" "${records["$idx":sound:1min]}" "$([[ -n "${records["$idx":sound:1min]}" ]] && echo "dBFS")"
				printf "   <td>%s %s</td><!-- 5 minute avg audio levels -->\n" "${records["$idx":sound:5min]}" "$([[ -n "${records["$idx":sound:5min]}" ]] && echo "dBFS")"
				printf "   <td>%s %s</td><!-- 10 minute avg audio levels -->\n" "${records["$idx":sound:10min]}" "$([[ -n "${records["$idx":sound:10min]}" ]] && echo "dBFS")"
				printf "   <td>%s %s</td><!-- 1 hour avg audio levels -->\n" "${records["$idx":sound:1hour]}" "$([[ -n "${records["$idx":sound:1hour]}" ]] && echo "dBFS")"
				if [[ -n "${records["$idx":spectro:link]}" ]]; then
					printf "   <td><a href=\"%s\" target=\"_blank\">Spectrogram</a></td><!-- spectrogram -->\n" "${records["$idx":spectro:link]}" # print spectrogram
				else
					printf "   <td></td>"
				fi
			fi

			# Print notifications, if there are any:
			if chk_enabled "${records[HASNOTIFS]}"; then
				notifstr=""
				# read array of available notification services into notifs array
				readarray -t notifs <<< "$(printf "%s\n" "${!records[@]}" | awk -F: -v idx="$idx" '{if ($1==idx && $3=="notified") {print $2}}'| sort -u)"
				for notif in "${notifs[@]}"; do
					if [[ "${records["$idx":"$notif":notified]}" == "true" ]]; then
						# if set to true, notification was successfully done but there's no link
						notifstr+="$(printf "%s - "  "$notif")"
					elif [[ "${records["$idx":"$notif":notified]}" != "false" ]]; then
						# if not set to true or false and not empty, then it's a link to the notification
						notifstr+="$(printf "<a href=\"%s\" target=\"_blank\">%s</a> - " "${records["$idx":"$notif":notified]}" "$notif")"
					fi
				done
				if (( ${#notifstr} > 3 )); then notifstr="${notifstr:0:-3}"; fi	# get rid of trailing " - "
				printf "<td>%s</td>\n" "$notifstr"
			fi

			# Print a delete button, if we have the SHOWIGNORE variable set
			if chk_enabled "$SHOWIGNORE"; then
				# If the record is in the ignore list, then print an "UnIgnore" button, otherwise print an "Ignore" button
				if ! grep -q -i "${records["$idx":icao]}" <<< "$PFIGNORELIST"; then
					printf "   <td><form id=\"ignoreForm\" action=\"manage_ignore.php\" method=\"get\">
													<input type=\"hidden\" name=\"mode\" value=\"pf\">
													<input type=\"hidden\" name=\"action\" value=\"add\">
													<input type=\"hidden\" name=\"term\" value=\"%s\">
													<input type=\"hidden\" name=\"uuid\" value=\"%s\">
													<input type=\"hidden\" id=\"currentUrl\" name=\"callback\">
													<button type=\"submit\" onclick=\"return prepareSubmit()\">Ignore</button></form></td>" \
						"${records["$idx":icao]}" "$uuid"
				else
					printf "   <td><form id=\"ignoreForm\" action=\"manage_ignore.php\" method=\"get\">
													<input type=\"hidden\" name=\"mode\" value=\"pf\">
													<input type=\"hidden\" name=\"action\" value=\"delete\">
													<input type=\"hidden\" name=\"term\" value=\"%s\">
													<input type=\"hidden\" name=\"uuid\" value=\"%s\">
													<input type=\"hidden\" id=\"currentUrl\" name=\"callback\">
													<button type=\"submit\" onclick=\"return prepareSubmit()\">UnIgnore</button></form></td>" \
						"${records["$idx":icao]}" "$uuid"
				fi
			fi	
			printf "</tr>\n"

		done
		printf "</tbody>\n</table>\n"
	)"
	echo "$table" > /tmp/table
	echo "$template" > /tmp/before
	template="$(template_replace "||PLANETABLE||" "$table" "$template")"
	echo "$template" > /tmp/after
	template="$(template_replace "||TABLESIZE||" "${TABLESIZE:-50}" "$template")"

}

# Function to write the Planefence history file
CREATEHTMLHISTORY () {
	# Insert HTML history into template
	htmlhistory="$(
		echo "<section style=\"border: none; margin: 0; padding: 0; font: 12px/1.4 'Helvetica Neue', Arial, sans-serif;\">
		<article>
		<details open>
		<summary style=\"font-weight: 900; font: 14px/1.4 'Helvetica Neue', Arial, sans-serif;\">Historical Data</summary>
		<p>Today: <a href=\"index.html\" target=\"_top\">html</a> - <a href=\"planefence-$TODAY.csv\" target=\"_top\">csv</a>
		"

		# loop through the existing files. Note - if you change the file format, make sure to yodate the arguments in the line
		# right below. Right now, it lists all files that have the planefence-20*.html format (planefence-200504.html, etc.), and then
		# picks the newest 7 (or whatever HISTTIME is set to), reverses the strings to capture the characters 6-11 from the right, which contain the date (200504)
		# and reverses the results back so we get only a list of dates in the format yymmdd.
		
		if compgen -G "$OUTFILEDIR/planefence-??????.html" >/dev/null; then
			# s#hellcheck disable=SC2012
			for d in $(find "$OUTFILEDIR" -name 'planefence-??????.html' -exec basename {} \; | awk -F'[-.]' '{print $2}' | sort -r); do
				printf " | %s" "$(date -d "$d" +%d-%b-%Y): "
				printf "<a href=\"%s\" target=\"_top\">html</a>" "planefence-$(date -d "$d" +"%y%m%d").html"
				if [[ -f "$OUTFILEDIR/planefence-$(date -d "$d" +"%y%m%d").csv" ]]; then
					printf " - <a href=\"%s\" target=\"_top\">csv</a>" "planefence-$(date -d "$d" +"%y%m%d").csv"
				fi
				if [[ -f "$OUTFILEDIR/planefence-$(date -d "$d" +"%y%m%d").json" ]]; then
					printf " - <a href=\"%s\" target=\"_top\">json</a>" "planefence-$(date -d "$d" +"%y%m%d").json"
				fi
			done
		fi
		printf "\n</p>\n"
		printf "</details>\n</article>\n</section>"
	)"
		template="$(template_replace "||HISTTABLE||" "$htmlhistory" "$template")"
}

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
	} > "$OUTFILEDIR/planeheatdata-$TODAY.js"

  # That's all for the heatmap

}

CREATENOTIFICATIONS () {

	if ! chk_enabled "${records[HASNOTIFS]}"; then
		template="$(template_replace "||NOTIFICATIONS||" "" "$template")"
		return
	fi
	# shellcheck disable=SC2034
	local notifhtml="$(
		printf "<li>Notifications are sent to the following services:</li>\n"
		if chk_enabled "$PF_DISCORD"; then
			printf "<ul><li>Discord</li></ul>\n"
		fi
		if [[ -n "$MASTODON_SERVER" ]]; then
			printf "<ul><li>Mastodon (<a href=\"%s\" target=\"_blank\">%s</a>)</li></ul>\n" "$MASTODON_SERVER/@$MASTODON_NAME" "@$MASTODON_NAME"
		fi
		if [[ -n "$BLUESKY_HANDLE" ]] && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then
			printf "<ul><li>BlueSky (<a href=\"https://bsky.app/profile/%s\" target=\"_blank\">@%s</a>)</li></ul>\n" "$BLUESKY_HANDLE" "$BLUESKY_HANDLE"
		fi
		if chk_enabled "$PF_TELEGRAM_ENABLED"; then
			printf "<ul><li>Telegram</li></ul>\n"
		fi
		if [[ -n "$MQTT_URL" ]]; then
			printf "<ul><li>MQTT broker at %s</li></ul>\n" "$MQTT_URL"
		fi
		if [[ -n "$RSS_SITELINK" ]]; then
			printf "<ul><li>RSS feed at <a href=\"%s\" target=\"_blank\">%s</a></li></ul>\n" "$RSS_SITELINK" "$RSS_SITELINK"
		fi
	)"
	template="$(template_replace "||NOTIFICATIONS||" "$notifhtml" "$template")"

}

# -----------------------------------------------------------------------------------
#      PREP WORK
# -----------------------------------------------------------------------------------

TODAY="$(date +%y%m%d)"
NOWTIME="$(date +%s)"
RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"
debug_print "Hello."

# Load the template into a variable that we can manipulate:
if ! template=$(<"$PLANEFENCEDIR/planefence.html.template"); then
	debug_print "Failed to load template"
	exit 1
fi

# Load the records
if [[ -f "$RECORDSFILE" ]]; then
	# shellcheck disable=SC1090
	source "$RECORDSFILE"
else
	debug_print "Failed to load records"
	exit 1
fi

# Ensure that there's an '/tmp/add_delete.uuid' file, or update it if needed
if [[ ! -f /tmp/add_delete.uuid ]] || ( [[ -f /tmp/add_delete.uuid.used ]] && (( NOWTIME - $(</tmp/add_delete.uuid.used) > 300 )) ); then
	# UUID file needs to be updated. This is done to prevent replay attacks.
	# This is done if the UUID was used more than 300 seconds ago, or if the file doesn't exist.
	cat /proc/sys/kernel/random/uuid > /tmp/add_delete.uuid
	touch /tmp/.force_pa_webpage_update	# this is used to force a Plane-Alert webpage update upon change of parameters
	rm -f /tmp/add_delete.uuid.used
fi
uuid="$(</tmp/add_delete.uuid)"

#
# Determine the user visible longitude and latitude based on the "fudge" factor we need to add:
printf -v LATFUDGED "%.${FUDGELOC:-3}f" "$LAT"
printf -v LONFUDGED "%.${FUDGELOC:-3}f" "$LON"

# Get the altitude reference:
if [[ -n "$ALTCORR" ]]; then ALTREF="AGL"; else ALTREF="MSL"; fi
# "DIST is $DIST $DISTUNIT; Conv to meters is $TO_METER"
DISTMTS="$(awk "BEGIN{print int($DIST * $TO_METER)}")"

# -----------------------------------------------------------------------------------
#      MODIFY THE TEMPLATE
# -----------------------------------------------------------------------------------
CREATEHTMLTABLE
CREATEHTMLHISTORY
CREATEHEATMAP
CREATENOTIFICATIONS

# Now replace the other template values:

# ||AUTOREFRESH||
if chk_enabled "${AUTOREFRESH}"; then
	REFRESH_INT="$(sed -n 's/\(^\s*PF_INTERVAL=\)\(.*\)/\2/p' /usr/share/planefence/persist/planefence.config)"
	template="$(template_replace "||AUTOREFRESH||" "<meta http-equiv=\"refresh\" content=\"${REFRESH_INT:-300}\">" "$template")"
else
	template="$(template_replace "||AUTOREFRESH||" "" "$template")"
fi

# a bunch of simple replacements:
template="$(template_replace "||MY||" "$MY" "$template")"
template="$(template_replace "||MYURL||" "$MYURL" "$template")"
template="$(template_replace "||MAPZOOM||" "$MAPZOOM" "$template")"
template="$(template_replace "||MAXALT||" "$MAXALT" "$template")"
template="$(template_replace "||VERSION||" "$VERSION" "$template")"
template="$(template_replace "||BUILD||" "$(</.VERSION)" "$template")"
template="$(template_replace "||SOCKETLINES||" "$SOCKETLINES" "$template")"
template="$(template_replace "||DIST||" "$DIST" "$template")"
template="$(template_replace "||DISTUNIT||" "$DISTUNIT" "$template")"
template="$(template_replace "||ALTUNIT||" "$ALTUNIT" "$template")"
template="$(template_replace "||ALTREF||" "$ALTREF" "$template")"
template="$(template_replace "||LASTUPDATE||" "$(date -d "@$NOWTIME")" "$template")"
template="$(template_replace "||TRACKURL||" "$TRACKURL" "$template")"
template="$(template_replace "||LATFUDGED||" "$LATFUDGED" "$template")"
template="$(template_replace "||LONFUDGED||" "$LONFUDGED" "$template")"
template="$(template_replace "||TODAY||" "$TODAY" "$template")"

# Altitude correction
if [[ -n "$ALTCORR" ]]; then
	template="$(template_replace "||ALTCORR||" "$ALTCORR" "$template")"
	template="$(template_replace "||ALTUNIT||" "$ALTUNIT" "$template")"
	template="$(template_replace "||ALTREF||" "$ALTREF" "$template")"
	template="$(template_replace "<!--ALTCORR||>" "" "$template")"
	template="$(template_replace "<||ALTCORR-->" "" "$template")"
else
	template="$(sed -z 's/<!--ALTCORR||>.*<||ALTCORR-->//g' <<< "$template")"
fi

# BSky correction
if chk_enabled "$BSKY"; then
	template="$(template_replace "||BSKYHANDLE||" "$BSKYHANDLE" "$template")"
	template="$(template_replace "||BSKYLINK||" "$BSKYLINK" "$template")"
	template="$(template_replace "<!--BSKY||>" "" "$template")"
	template="$(template_replace "<||BSKY-->" "" "$template")"
else
	template="$(sed -z 's/<!--BSKY||>.*<||BSKY-->//g' <<< "$template")"
fi

# Noise data section
# Set PlaneAlert link if PA is enabled
if chk_enabled "${records[HASNOISE]}"; then
	template="$(template_replace "<!--NOISEDATA||>" "" "$template")"
	template="$(template_replace "<||NOISEDATA-->" "" "$template")"
else
	template="$(sed -z 's/<!--NOISEDATA||>.*<||NOISEDATA-->//g' <<< "$template")"
fi

# Set PlaneAlert link if PA is enabled
if chk_enabled "$PLANEALERT"; then
	template="$(template_replace "||PALINK||" "$PALINK" "$template")"
	template="$(template_replace "<!--PA||>" "" "$template")"
	template="$(template_replace "<||PA-->" "" "$template")"
else
	template="$(sed -z 's/<!--PA||>.*<||PA-->//g' <<< "$template")"
fi


# ---------------------------------------------------------------------------
#      FINALIZE AND WRITE THE FILES
# ---------------------------------------------------------------------------

echo "$template" > "$OUTFILEDIR/planefence-$TODAY.html"
ln -sf "$OUTFILEDIR/planefence-$TODAY.html" "$OUTFILEDIR/index.html"

debug_print "Done - Wrote HTML file to $OUTFILEDIR/planefence-$TODAY.html"
