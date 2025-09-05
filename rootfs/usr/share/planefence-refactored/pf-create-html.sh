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

source /scripts/common
source /usr/share/planefence/planefence.conf

# First define a bunch of functions:
debug_print() {
    local currenttime
    if [[ -z "$execstarttime" ]]; then
      execstarttime="$(date +%s.%3N)"
      execlaststeptime="$execstarttime"
    fi
    currenttime="$(date +%s.%3N)"
    if chk_enabled "$DEBUG"; then 
      "${s6wrap[@]}" printf "[DEBUG] %s (%s secs, total time elapsed %s secs)\n" "$1" "$(bc -l <<< "$currenttime - $execlaststeptime")" "$(bc -l <<< "$currenttime - $execstarttime")" >&2
    fi
    execlaststeptime="$currenttime"
}

# Function to write the Planefence HTML table
CREATEHTMLTABLE () {

	# Write the HTML table header
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
		PFIGNORELIST="$(<"/usr/share/planefence/persist/planefence-ignore.txt")"
	fi
	printf "	</tr></thead>\n<tbody border=\"1\">\n"

	# Now write the table

	for (( index=0 ; index<=maxindex ; index++ )); do

		printf "<tr>\n"
		printf "   <td style=\"text-align: center\">%s</td><!-- row 1: index -->\n" "$index" # table index number

		if chk_enabled "${SHOWIMAGES}" && [[ -n "${records[$index:image_thumblink]}" ]]; then
			printf "   <td><a href=\"%s\" target=_blank><img src=\"%s\" style=\"width: auto; height: 75px;\"></a></td><!-- image file and link to planespotters.net -->\n" "${records[$index:image_weblink]}" "${records[$index:image_thumblink]}"
		elif chk_enabled "${SHOWIMAGES}"; then
			printf "   <td></td><!-- images enabled but no image file available for this entry -->\n"
		fi

		printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- ICAO with map link -->\n" "${records[$index:map_link]}" "${records[$index:icao]}" # ICAO

		printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- Flight number/tail with FlightAware link -->\n" "${records[$index:fa_link]}" "${records[$index:callsign]}" # Flight number/tail with FlightAware link

		if chk_enabled "${records[HASROUTE]}"; then
			printf "   <td>%s</td><!-- route -->\n" "${records[$index:route]}" # route
		fi

		if [[ -n "${records[$index:faa_link]}" ]]; then
			printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- owner with FAA link -->\n" "${records[$index:faa_link]}" "${records[$index:owner]}"
		else
			printf "   <td>%s</td><!-- owner -->\n" "${records[$index:owner]}"
		fi

		printf "   <td style=\"text-align: center\">%s</td><!-- date/time first seen -->\n" "$(date -d "@${records[$index:firstseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" # time first seen

		printf "   <td style=\"text-align: center\">%s</td><!-- date/time last seen -->\n" "$(date -d "@${records[$index:lastseen]}" "+${NOTIF_DATEFORMAT:-%F %T %Z}")" # time last seen

		printf "   <td>%s %s %s</td><!-- min altitude -->\n" "${records[$index:altitude]}" "$ALTUNIT" "$ALTREFERENCE" # min altitude
		printf "   <td>%s %s</td><!-- min distance -->\n" "${records[$index:distance]}" "$DISTUNIT" # min distance

		# Print the noise values if we have determined that there is data
		if "$HASNOISE"; then
			# First the loudness field, which needs a color and a link to a noise graph:
			if [[ -n "${records[$index:noisegraph_link]}" ]]; then
				printf "   <td style=\"background-color: %s\"><a href=\"%s\" target=\"_blank\">%s dB</a></td><!-- loudness with noisegraph -->\n" "${records[$index:sound_color]}" "${records[$index:noisegraph_link]}" "${records[$index:sound_loudness]}"
			else
				printf "   <td style=\"background-color: %s\">%s dB</td><!-- loudness (no noisegraph available) -->\n" "${records[$index:sound_color]}" "${records[$index:sound_loudness]}"
			fi
			if [[ -n "${records[$index:mp3_link]}" ]]; then 
				printf "   <td><a href=\"%s\" target=\"_blank\">%s dBFS</td><!-- peak RMS value with MP3 link -->\n" "${records[$index:mp3_link]}" "${records[$index:sound_peak]}" # print actual value with "dBFS" unit
			else
				printf "   <td>%s dBFS</td><!-- peak RMS value (no MP3 recording available) -->\n" "${records[$index:sound_peak]}" # print actual value with "dBFS" unit
			fi
			printf "   <td>%s dBFS</td><!-- 1 minute avg audio levels -->\n" "${records[$index:sound_1min]}"
			printf "   <td>%s dBFS</td><!-- 5 minute avg audio levels -->\n" "${records[$index:sound_5min]}"
			printf "   <td>%s dBFS</td><!-- 10 minute avg audio levels -->\n" "${records[$index:sound_10min]}"
			printf "   <td>%s dBFS</td><!-- 1 hour avg audio levels -->\n" "${records[$index:sound_1hour]}"
			printf "   <td><a href=\"%s\" target=\"_blank\">Spectrogram</a></td><!-- spectrogram -->\n" "${records[$index:spectro_link]}" # print spectrogram
		fi

		# Print a notification, if there are any:
		if "$HASNOTIFS"; then
				if [[ -n "${records[$index:notif_link]}" ]]; then
					printf "   <td><a href=\"%s\" target=\"_blank\">%s</a></td><!-- notification link and service -->\n" "${records[$index:notif_link]}" "${records[$index:notif_service]}"
				else
					printf "   <td>%s</td><!-- notified yes or no -->\n"  "${records[$index:notif_service]}"
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
					"${records[$index:icao]}" "$uuid"
			else
				printf "   <td><form id=\"ignoreForm\" action=\"manage_ignore.php\" method=\"get\">
												<input type=\"hidden\" name=\"mode\" value=\"pf\">
												<input type=\"hidden\" name=\"action\" value=\"delete\">
												<input type=\"hidden\" name=\"term\" value=\"%s\">
												<input type=\"hidden\" name=\"uuid\" value=\"%s\">
												<input type=\"hidden\" id=\"currentUrl\" name=\"callback\">
												<button type=\"submit\" onclick=\"return prepareSubmit()\">UnIgnore</button></form></td>" \
					"${records[$index:icao]}" "$uuid"
			fi
		fi	
		printf "</tr>\n"

	done
	printf "</tbody>\n</table>\n"

}

# Function to write the Planefence history file
CREATEHTMLHISTORY () {
	# -----------------------------------------
	# Write history file from directory
	# Usage: WRITEHTMLTABLE PLANEFENCEDIRECTORY OUTPUTFILE [standalone]

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
	printf "</p>\n"
	printf "</details>\n</article>\n</section>"
}

# Function to create the Heatmap
CREATEHEATMAP () {

	# Disable the heatmap in the template if $PLANEHEAT is not enabled
	if ! chk_enabled "$PLANEHEAT"; then
		template="$(sed -z 's/<!--PLANEHEAT##>.*<##PLANEHEAT-->//g' <<< "$template")"
		return
	else
		template="$(sed 's/<!--PLANEHEAT##>//g; s/<##PLANEHEAT-->//g' <<< "$template")"
	fi

	# If OpenAIP is enabled, include it. If not, exclude it.
	if chk_enabled "$OPENAIP_LAYER"; then
		template="$(sed "s/<!--OPENAIP##>//g; s/<##OPENAIP-->//; "s/##OPENAIPKEY##/$OPENAIPKEY/g" <<< "$template")"
	else
		template="$(sed -z 's/<!--OPENAIP##>.*<##OPENAIP-->//g' <<< "$template")"
	fi

	# Replace the other template values:
	template="$(sed "s/##LATFUDGED##/$LAT/g;
									 s/##LONFUDGED##/$LON/g;
									 s/##HEATMAPZOOM##/$HEATMAPZOOM/g;
									 s/##HEATMAPWIDTH##/$HEATMAPWIDTH/g;
									 s/##HEATMAPHEIGHT##/$HEATMAPHEIGHT/g;
									 s/##DISTMTS##/$DISTMTS/g;
									 " <<< "$template")"
	# Create the heatmap data
	{ printf -v "var addressPoints = [\n"
		for i in "${!records[@]}"; do
			if [[ "${i:0:7}" == "heatmap" ]]; then
				printf "[ %s,%s ],\n" "${i:7}" "${records[$i]}"
			fi
		done
		printf "];\n"
	} > "$OUTFILEDIR/planeheatdata-$TODAY.js"

  # Modify the template values to reflect the current values 

}


TODAY="$(date +%y%m%d)"
YESTERDAY="$(date -d "yesterday" +%y%m%d)"
NOWTIME="$(date +%s)"
RECORDSFILE="$HTMLDIR/.planefence-records-${TODAY}"

# The following template values must be filled in:
# ##ALTCORR##
# <!--ALTCORR##>
# <##ALTCORR-->
# ##ALTREF##
# ##ALTUNIT##
# <!--BSKY##>
# <##BSKY-->
# ##BSKYHANDLE##
# ##BSKYLINK##
# ##BUILD##
# ##DIST##
# ##DISTUNIT##
# ##HISTTABLE##
# ##LASTUPDATE##
# ##LATFUDGED##
# ##LONFUDGED##
# ##MAPZOOM##
# ##MAXALT##
# ##MY##
# ##MYURL##
# <!--NOISEDATA##>
# <##NOISEDATA-->
# <!--PA##>
# <##PA-->
# ##PALINK##
# <!--PLANEHEAT##>
# <##PLANEHEAT-->
# ##PLANETABLE##
# <!--RSS##>
# <##RSS-->
# ##SOCKETLINES##
# ##TRACKURL##
# ##VERSION##

# Load the template into a variable that we can manipulate:
if ! template=$(<"$PLANEFENCEDIR/planefence.template.html"); then
	echo "Failed to load template" >&2
	exit 1
fi

# Load the records
if ! records=$(<"$RECORDSFILE"); then
	echo "Failed to load records" >&2
	exit 1
fi

# Get DISTANCE unit:
DISTUNIT="mi"
ALTUNIT="ft"
if [[ -f "$SOCKETCONFIG" ]]; then
	case "$(grep "^distanceunit=" "$SOCKETCONFIG" |sed "s/distanceunit=//g")" in
		nauticalmile)
		DISTUNIT="nm"
    TO_METER=1852
		;;
		kilometer)
		DISTUNIT="km"
		TO_METER=1000
		;;
		mile)
		DISTUNIT="mi"
		TO_METER=1609
		;;
		meter)
		DISTUNIT="m"
		TO_METER=1
	esac
	case "$(grep "^altitudeunit=" "$SOCKETCONFIG" |sed "s/altitudeunit=//g")" in
		feet)
		ALTUNIT="ft"
		;;
		meter)
		ALTUNIT="m"
	esac
fi

#
# Determine the user visible longitude and latitude based on the "fudge" factor we need to add:
printf -v LATFUDGED "%.${FUDGELOC:-3}f" "$LAT"
printf -v LONFUDGED "%.${FUDGELOC:-3}f" "$LON"

if [[ -n "$ALTCORR" ]]; then ALTREF="AGL"; else ALTREF="MSL"; fi
DISTMTS="$(awk "BEGIN{print int($DIST * $TO_METER)}")"

# See if we need to run PLANEHEAT
if chk_enabled "$PLANEHEAT" && [[ -f "${PLANEHEATSCRIPT}" ]];then
	"${s6wrap[@]}" echo "Invoking PlaneHeat..."
	$PLANEHEATSCRIPT
fi

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
  <li>Maximum distance from <a href="https://www.openstreetmap.org/?mlat=$LATFUDGED&mlon=$LONFUDGED#map=14/$LATFUDGED/$LONFUDGED&layers=H" target=_blank>${LATFUDGED}&deg;N, ${LONFUDGED}&deg;E</a>: $DIST $DISTUNIT
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

{	printf "<li>Click on the Transponder ID to see the full flight information/history (from <a href=\"https://$TRACKSERVICE/?lat=%s&lon=%s&zoom=11.0\" target=\"_blank\">$TRACKSERVICE</a>)\n" "$LATFUDGED" "$LONFUDGED"
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
CREATEHTMLHISTORY "$OUTFILEDIR" "$OUTFILEHTMTMP"
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
