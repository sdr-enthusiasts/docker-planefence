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
##
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

source /scripts/common
source /usr/share/planefence/planefence.conf

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
HTMLDIR=/tmp
PLANEFENCEDIR=/
OUTFILEDIR=/tmp
set -eo pipefail
DEBUG=true

# -----------------------------------------------------------------------------------
#      FUNCTIONS
# -----------------------------------------------------------------------------------

# First define a bunch of functions:

template_replace() {
	# Replace instance of $1 with $2 in the template variable
	# Do this in a safe way that doesn't break on characters in the replacement string

	if ! grep -q "$1" <(printf '%s\n' "$template"); then
		debug_print "Can't replace - \"$1\" not found in template"
		return
	fi

  while firstpart="$(awk -v pat="$1" '
		{
			i = index($0, pat)
			if (i) {
				if (i>1) print substr($0,1,i-1)
				found=1
				exit
			}
			print
		}
		END { exit(!found) }' <(printf '%s\n' "$template"))"; do
		lastpart="$(awk -v pat="$1" '
			BEGIN { found=0; plen=length(pat) }
			{
				if (!found) {
					i = index($0, pat)
					if (i) {
						# print rest of this line after the matched pattern (if any)
						post = substr($0, i + plen)
						if (length(post)) print post
						found = 1
						next
					}
				} else {
					print
				}
			}
			END { exit(!found) }' <(printf '%s\n' "$template"))"

	  template="${firstpart}${2}${lastpart}"
	done
}

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
			<th style=\"width: auto; text-align: center\">Flight</th>
			$(if chk_enabled "${records[HASROUTE]}"; then echo "<th style=\"width: auto; text-align: center\">Flight Route</th>"; fi)
			<th style=\"width: auto; text-align: center\">Airline or Owner</th>
			<th style=\"width: auto; text-align: center\">Time First Seen</th>
			<th style=\"width: auto; text-align: center\">Time Last Seen</th>
			<th style=\"width: auto; text-align: center\">Min. Altitude</th>
			<th style=\"width: auto; text-align: center\">Min. Distance</th>"

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
			printf "   <td style=\"text-align: center\">%s</td><!-- row 1: index -->\n" "$idx" # table index number

			if chk_enabled "${SHOWIMAGES}" && [[ -n "${records["$idx":image_thumblink]}" ]]; then
				printf "   <td><a href=\"%s\" target=_blank><img src=\"%s\" style=\"width: auto; height: 75px;\"></a></td><!-- image file and link to planespotters.net -->\n" "${records["$idx":image_weblink]}" "${records["$idx":image_thumblink]}"
			elif chk_enabled "${SHOWIMAGES}"; then
				printf "   <td></td><!-- images enabled but no image file available for this entry -->\n"
			fi

			printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- ICAO with map link -->\n" "${records["$idx":map_link]}" "${records["$idx":icao]}" # ICAO
			printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- Flight number/tail with FlightAware link -->\n" "${records["$idx":fa_link]}" "${records["$idx":callsign]}" # Flight number/tail with FlightAware link

			if chk_enabled "${records[HASROUTE]}"; then
				printf "   <td>%s</td><!-- route -->\n" "${records["$idx":route]}" # route
			fi

			if [[ -n "${records["$idx":faa_link]}" ]]; then
				printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- owner with FAA link -->\n" "${records["$idx":faa_link]}" "${records["$idx":owner]}"
			else
				printf "   <td>%s</td><!-- owner -->\n" "${records["$idx":owner]}"
			fi

			printf "   <td style=\"text-align: center\">%s</td><!-- date/time first seen -->\n" "$(date -d "@${records["$idx":firstseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" # time first seen

			printf "   <td style=\"text-align: center\">%s</td><!-- date/time last seen -->\n" "$(date -d "@${records["$idx":lastseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" # time last seen

			printf "   <td>%s %s %s</td><!-- min altitude -->\n" "${records["$idx":altitude]}" "$ALTUNIT" "$ALTREFERENCE" # min altitude
			printf "   <td>%s %s</td><!-- min distance -->\n" "${records["$idx":distance]}" "$DISTUNIT" # min distance

			# Print the noise values if we have determined that there is data
			if chk_enabled "${records[HASNOISE]}"; then
				# First the loudness field, which needs a color and a link to a noise graph:
				if [[ -n "${records["$idx":noisegraph_link]}" ]]; then
					printf "   <td style=\"background-color: %s\"><a href=\"%s\" target=\"_blank\">%s dB</a></td><!-- loudness with noisegraph -->\n" "${records["$idx":sound_color]}" "${records["$idx":noisegraph_link]}" "${records["$idx":sound_loudness]}"
				else
					printf "   <td style=\"background-color: %s\">%s dB</td><!-- loudness (no noisegraph available) -->\n" "${records["$idx":sound_color]}" "${records["$idx":sound_loudness]}"
				fi
				if [[ -n "${records["$idx":mp3_link]}" ]]; then 
					printf "   <td><a href=\"%s\" target=\"_blank\">%s dBFS</td><!-- peak RMS value with MP3 link -->\n" "${records["$idx":mp3_link]}" "${records["$idx":sound_peak]}" # print actual value with "dBFS" unit
				else
					printf "   <td>%s dBFS</td><!-- peak RMS value (no MP3 recording available) -->\n" "${records["$idx":sound_peak]}" # print actual value with "dBFS" unit
				fi
				printf "   <td>%s dBFS</td><!-- 1 minute avg audio levels -->\n" "${records["$idx":sound_1min]}"
				printf "   <td>%s dBFS</td><!-- 5 minute avg audio levels -->\n" "${records["$idx":sound_5min]}"
				printf "   <td>%s dBFS</td><!-- 10 minute avg audio levels -->\n" "${records["$idx":sound_10min]}"
				printf "   <td>%s dBFS</td><!-- 1 hour avg audio levels -->\n" "${records["$idx":sound_1hour]}"
				printf "   <td><a href=\"%s\" target=\"_blank\">Spectrogram</a></td><!-- spectrogram -->\n" "${records["$idx":spectro_link]}" # print spectrogram
			fi

			# Print a notification, if there are any:
			if chk_enabled "${records[HASNOTIFS]}"; then
					if [[ -n "${records["$idx":notif_link]}" ]]; then
						printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- notification link and service -->\n" "${records["$idx":notif_link]}" "${records["$idx":notif_service]}"
					else
						printf "   <td>%s</td><!-- notified yes or no -->\n"  "${records["$idx":notif_service]}"
					fi
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

	template_replace "##PLANETABLE##" "$table"
	template_replace "##TABLESIZE##" "${TABLESIZE:-50}"

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
		template_replace "##HISTTABLE##" "$htmlhistory"
}

# Function to create the Heatmap
CREATEHEATMAP () {
	# Disable the heatmap in the template if $PLANEHEAT is not enabled
	if ! chk_enabled "$PLANEHEAT"; then
		template="$(sed -z 's/<!--PLANEHEAT##>.*<##PLANEHEAT-->//g' <<< "$template")"
		return
	else
		template_replace "<!--PLANEHEAT##>" ""
		template_replace "<##PLANEHEAT-->" ""
	fi

	# If OpenAIP is enabled, include it. If not, exclude it.
	if chk_enabled "$OPENAIP_LAYER"; then
		template_replace "<!--OPENAIP##>" ""
		template_replace "<##OPENAIP-->" ""
		template_replace "##OPENAIPKEY##" "$OPENAIPKEY"
	else
		template="$(sed -z 's/<!--OPENAIP##>.*<##OPENAIP-->//g' <<< "$template")"
	fi

	# Replace the other template values:
	# Determine the zoom level for the heatmap
	template_replace "##HEATMAPZOOM##" "$HEATMAPZOOM"
	template_replace "##HEATMAPWIDTH##" "$HEATMAPWIDTH"
	template_replace "##HEATMAPHEIGHT##" "$HEATMAPHEIGHT"
	template_replace "##DISTMTS##" "$DISTMTS"

	# Create the heatmap data
	{ printf "var addressPoints = [\n"
		for i in "${!records[@]}"; do
			if [[ "${i:0:7}" == "heatmap" ]]; then
				printf "[ %s,%s ],\n" "${i:7}" "${records[$i]}"
			fi
		done
		printf "];\n"
	} > "$OUTFILEDIR/planeheatdata-$TODAY.js"

  # That's all for the heatmap

}

CREATENOTIFICATIONS () {

	if ! chk_enabled "${records[HASNOTIFS]}"; then
		template_replace "##NOTIFICATIONS##" ""
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
	template_replace "##NOTIFICATIONS##" "$notifhtml"

}

# -----------------------------------------------------------------------------------
#      PREP WORK
# -----------------------------------------------------------------------------------

TODAY="$(date +%y%m%d)"
NOWTIME="$(date +%s)"
RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"

# Load the template into a variable that we can manipulate:
if ! template=$(<"$PLANEFENCEDIR/planefence.html.template"); then
	echo "Failed to load template" >&2
	exit 1
fi

# Load the records
if [[ -f "$RECORDSFILE" ]]; then
	# shellcheck disable=SC1090
	source "$RECORDSFILE"
else
	echo "Failed to load records" >&2
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
DISTMTS="$(awk "BEGIN{print int($DIST * $TO_METER)}")"

# -----------------------------------------------------------------------------------
#      MODIFY THE TEMPLATE
# -----------------------------------------------------------------------------------

CREATEHTMLTABLE
CREATEHTMLHISTORY
CREATEHEATMAP
CREATENOTIFICATIONS

# Now replace the other template values:

# ##AUTOREFRESH##
if chk_enabled "${AUTOREFRESH}"; then
	REFRESH_INT="$(sed -n 's/\(^\s*PF_INTERVAL=\)\(.*\)/\2/p' /usr/share/planefence/persist/planefence.config)"
	template_replace "##AUTOREFRESH##" "<meta http-equiv=\"refresh\" content=\"${REFRESH_INT:-300}\">"
else
	template_replace "##AUTOREFRESH##" ""
fi

# a bunch of simple replacements:
template_replace "##MY##" "$MY"
template_replace "##MYURL##" "$MYURL"
template_replace "##MAPZOOM##" "$MAPZOOM"
template_replace "##MAXALT##" "$MAXALT"
template_replace "##VERSION##" "$VERSION"
template_replace "##BUILD##" "$(</.VERSION)"
template_replace "##SOCKETLINES##" "$SOCKETLINES"
template_replace "##DIST##" "$DIST"
template_replace "##DISTUNIT##" "$DISTUNIT"
template_replace "##ALTUNIT##" "$ALTUNIT"
template_replace "##ALTREF##" "$ALTREF"
template_replace "##LASTUPDATE##" "$(date -d "@$NOWTIME")"
template_replace "##TRACKURL##" "$TRACKURL"
template_replace "##LATFUDGED##" "$LATFUDGED"
template_replace "##LONFUDGED##" "$LONFUDGED"

# Altitude correction
if [[ -n "$ALTCORR" ]]; then
	template_replace "##ALTCORR##" "$ALTCORR"
	template_replace "##ALTUNIT##" "$ALTUNIT"
	template_replace "##ALTREF##" "$ALTREF"
	template_replace "<!--ALTCORR##>" ""
	template_replace "<##ALTCORR-->" ""
else
	template="$(sed -z 's/<!--ALTCORR##>.*<##ALTCORR-->//g' <<< "$template")"
fi

# BSky correction
if chk_enabled "$BSKY"; then
	template_replace "##BSKYHANDLE##" "$BSKYHANDLE"
	template_replace "##BSKYLINK##" "$BSKYLINK"
	template_replace "<!--BSKY##>" ""
	template_replace "<##BSKY-->" ""
else
	template="$(sed -z 's/<!--BSKY##>.*<##BSKY-->//g' <<< "$template")"
fi

# Noise data section
# Set PlaneAlert link if PA is enabled
if chk_enabled "${records[HASNOISE]}"; then
	template_replace "<!--NOISEDATA##>" ""
	template_replace "<##NOISEDATA-->" ""
else
	template="$(sed -z 's/<!--NOISEDATA##>.*<##NOISEDATA-->//g' <<< "$template")"
fi

# Set PlaneAlert link if PA is enabled
if chk_enabled "$PLANEALERT"; then
	template_replace "##PALINK##" "$PALINK"
	template_replace "<!--PA##>" ""
	template_replace "<##PA-->" ""
else
	template="$(sed -z 's/<!--PA##>.*<##PA-->//g' <<< "$template")"
fi


# ---------------------------------------------------------------------------
#      FINALIZE AND WRITE THE FILES
# ---------------------------------------------------------------------------

echo "$template" > "$OUTFILEDIR/planefence-$TODAY.html"
ln -sf "$OUTFILEDIR/planefence-$TODAY.html" "$OUTFILEDIR/index.html"

debug_print "Done - Wrote HTML file to $OUTFILEDIR/planefence-$TODAY.html"
