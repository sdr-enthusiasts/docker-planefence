#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2268,SC2174,SC1091,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence4docker/
#
# Programmers note: when using sed for URLs or file names, make sure NOT to use '/'
# as command separator, but use something else instead, for example '|'
#
# -----------------------------------------------------------------------------------
#
source /scripts/pf-common

REMOTEURL=$(sed -n 's/\(^\s*REMOTEURL=\)\(.*\)/\2/p' /usr/share/planefence/planefence.conf)

function configure_planefence() {
	local SETTING_NAME="$1"
	local SETTING_VALUE="$2"
	if [[ -n "$SETTING_VALUE" ]]; then
		if [[ "${SETTING_VALUE:0:1}" != "\"" ]] && [[ "${SETTING_VALUE:0:1}" != "'" ]]; then SETTING_VALUE="\"$SETTING_VALUE"; fi
		if [[ "${SETTING_VALUE: -1}" != "\"" ]] && [[ "${SETTING_VALUE: -1}" != "'" ]]; then SETTING_VALUE="$SETTING_VALUE\""; fi
		sed -i "s~\(^\s*${SETTING_NAME}=\).*~\1${SETTING_VALUE}~" /usr/share/planefence/planefence.conf
	else
		sed -i "s|\(^\s*${SETTING_NAME}=\).*|\1|" /usr/share/planefence/planefence.conf
	fi
}
function configure_planealert() {
	local SETTING_NAME="$1"
	local SETTING_VALUE="$2"
	if [[ -n "$SETTING_VALUE" ]]; then
		if [[ "${SETTING_VALUE:0:1}" != "\"" ]] && [[ "${SETTING_VALUE:0:1}" != "'" ]]; then SETTING_VALUE="\"$SETTING_VALUE"; fi
		if [[ "${SETTING_VALUE: -1}" != "\"" ]] && [[ "${SETTING_VALUE: -1}" != "'" ]]; then SETTING_VALUE="$SETTING_VALUE\""; fi
		sed -i "s~\(^\s*${SETTING_NAME}=\).*~\1${SETTING_VALUE}~" /usr/share/plane-alert/plane-alert.conf
	else
		sed -i "s|\(^\s*${SETTING_NAME}=\).*|\1|" /usr/share/plane-alert/plane-alert.conf
	fi
}
function configure_both() {
	configure_planefence "$1" "$2"
	configure_planealert "$1" "$2"
}

[[ "$LOGLEVEL" != "ERROR" ]] && "${s6wrap[@]}" echo "Running Planefence configuration - either the container is restarted or a config change was detected." || true
# Sometimes, variables are passed in through .env in the Docker-compose directory
# However, if there is a planefence.config file in the ..../persist directory
# (by default exposed to ~/.planefence) then export all of those variables as well
# note that the grep strips off any spaces at the beginning of a line, and any commented line
mkdir -p /usr/share/planefence/persist/.internal
mkdir -p /usr/share/planefence/persist/planepix/cache
mkdir -p /usr/share/planefence/html/plane-alert/silhouettes
mkdir -p /usr/share/planefence/html/scripts
chmod -f a=rwx /usr/share/planefence/persist /usr/share/planefence/persist/planepix
chmod -fR a+rw /usr/share/planefence/persist/{.[!.]*,*}
chmod u=rwx,go=rx \
	/usr/share/planefence/persist/.internal \
	/usr/share/planefence/html \
	/usr/share/planefence/html/plane-alert \
	/usr/share/planefence/html/plane-alert/silhouettes \
	/usr/share/planefence/html/scripts
ln -sf /usr/share/planefence/html/scripts /usr/share/planefence/html/plane-alert/scripts
if [[ ! -e /usr/share/planefence/html/imgcache ]]; then ln -sf /usr/share/planefence/persist/planepix/cache /usr/share/planefence/html/imgcache; fi
if [[ ! -e /usr/share/planefence/html/plane-alert/imgcache ]]; then ln -sf /usr/share/planefence/persist/planepix/cache /usr/share/planefence/html/plane-alert/imgcache; fi
chmod a+rx /usr/share/planefence/html/imgcache /usr/share/planefence/html/plane-alert/imgcache
if [[ -f /usr/share/planefence/persist/planefence.config ]]; then
	set -o allexport
	# shellcheck disable=SC1091
	source /usr/share/planefence/persist/planefence.config
	set +o allexport
else
	cp -n /usr/share/planefence/stage/planefence.config /usr/share/planefence/persist/planefence.config-RENAME-and-EDIT-me
	chmod -f a+rw /usr/share/planefence/persist/planefence.config
fi
#
# -----------------------------------------------------------------------------------
#
# Move the jscript files from the staging directory into the html/staging directory.
# this cannot be done at build time because the directory is exposed and it is
# overwritten by the host at start of runtime
cp -f /usr/share/planefence/stage/* /usr/share/planefence/html
cp -n /usr/share/planefence/stage/favicon.ico /usr/share/planefence/html/plane-alert
mv -f /usr/share/planefence/html/{*.js,*.css} /usr/share/planefence/html/scripts
mv -f /usr/share/planefence/html/Silhouettes.zip /tmp/silhouettes-org.zip
rm -f /usr/share/planefence/html/planefence.config /usr/share/planefence/html/*.template /usr/share/planefence/html/aircraft-database-complete-
mv -f /usr/share/planefence/html/pa_query.php /usr/share/planefence/html/plane-alert
[[ ! -f /usr/share/planefence/persist/pf_background.jpg ]] && cp -f /usr/share/planefence/html/background.jpg /usr/share/planefence/persist/pf_background.jpg
[[ ! -f /usr/share/planefence/persist/pa_background.jpg ]] && cp -f /usr/share/planefence/html/background.jpg /usr/share/planefence/persist/pa_background.jpg
rm -f /usr/share/planefence/html/background.jpg
[[ ! -f /usr/share/planefence/persist/planefence-ignore.txt ]] && mv -f /usr/share/planefence/html/planefence-ignore.txt /usr/share/planefence/persist/ || rm -f /usr/share/planefence/html/planefence-ignore.txt
#
# maybe for future use
# cp -u /usr/share/planefence/stage/*.template /usr/share/planefence/persist >/dev/null 2>&1
#
#--------------------------------------------------------------------------------
#
# Now initialize Plane Alert. Note that this isn't in its own s6 runtime because it's
# only called synchronously from planefence (if enabled)
#
mkdir -p /usr/share/planefence/html/plane-alert
[[ ! -f /usr/share/planefence/html/plane-alert/index.html ]] && cp /usr/share/plane-alert/html/index.html /usr/share/planefence/html/plane-alert/
# Sync the plane-alert DB with a preference for newer versions on the persist volume:
cp -n /usr/share/plane-alert/plane-alert-db.txt /usr/share/planefence/persist
#
# LOOPTIME is the time between two runs of Planefence (in seconds)
if [[ -n "$PF_INTERVAL" ]]; then
	export LOOPTIME=$PF_INTERVAL

else
	export LOOPTIME=120
fi
#
# PLANEFENCEDIR contains the directory where planefence.sh is location

#
# Make sure the /run directory exists
mkdir -p /run/planefence
# -----------------------------------------------------------------------------------
# Do one last check. If FEEDER_LAT= empty or 90.12345, then the user obviously hasn't touched the config file.
if [[ -z "$FEEDER_LAT" ]] || [[ "$FEEDER_LAT" == "90.12345" ]]; then
	sleep 10s
	"${s6wrap[@]}" echo "----------------------------------------------------------"
	"${s6wrap[@]}" echo "!!! STOP !!!! You haven\'t configured FEEDER_LON and/or FEEDER_LAT for Planefence !!!!"
	"${s6wrap[@]}" echo "Planefence will not run unless you edit it configuration."
	"${s6wrap[@]}" echo "You can do this by pressing CTRL-c now and typing:"
	"${s6wrap[@]}" echo "sudo nano -l ~/.planefence/planefence.config"
	"${s6wrap[@]}" echo "Once done, restart the container and this message should disappear."
	"${s6wrap[@]}" echo "----------------------------------------------------------"
	exec sleep infinity
fi

#
# Set logging in planefence.conf:
#
if chk_disabled "$PF_LOG"; then
	export LOGFILE=/dev/null
	sed -i 's/\(^\s*VERBOSE=\).*/\1'""'/' /usr/share/planefence/planefence.conf
else
	[[ -z "$PF_LOG" ]] && export LOGFILE="/tmp/planefence.log" || export LOGFILE="$PF_LOG"
fi
# echo pflog=$PF_LOG and logfile=$LOGFILE
sed -i 's|\(^\s*LOGFILE=\).*|\1'"$LOGFILE"'|' /usr/share/planefence/planefence.conf
#
# -----------------------------------------------------------------------------------
#
# read the environment variables and put them in the planefence.conf file:
if [[ -n "$FEEDER_LAT" ]]; then
	configure_planefence "LAT" "$FEEDER_LAT"
else
	"${s6wrap[@]}" echo "Error - \$FEEDER_LAT ($FEEDER_LAT) not defined"
	exec sleep infinity
fi

if [[ -n "$FEEDER_LONG" ]]; then
	configure_planefence "LON" "$FEEDER_LONG"
else
	"${s6wrap[@]}" echo "Error - \$FEEDER_LONG not defined"
	exec sleep infinity
fi

configure_planefence "MAXALT" "$PF_MAXALT"
configure_planefence "DIST" "$PF_MAXDIST"
configure_planefence "ALTCORR" "$PF_ELEVATION"
configure_planefence "MY" "$PF_NAME"
configure_planefence "MYURL" "$PF_MAPURL"
configure_planefence "REMOTENOISE" "$PF_NOISECAPT"
configure_planefence "FUDGELOC" "$PF_FUDGELOC"

if chk_enabled "$PF_OPENAIP_LAYER"; then
	configure_planefence "OPENAIP_LAYER" "ON"
else
	configure_planefence "OPENAIP_LAYER" "OFF"
fi

configure_planefence "TWEET_MINTIME" "${PF_NOTIF_MINTIME:-$PF_TWEET_MINTIME}"
configure_planefence "TWEET_BEHAVIOR" "${PF_NOTIF_BEHAVIOR:-$PF_TWEET_BEHAVIOR}"
configure_planefence "PA_LINK" "$PF_PA_LINK"
configure_planealert "PF_LINK" "$PA_PF_LINK"
if chk_enabled "${PF_NOTIFEVERY:-$PF_TWEETEVERY}"; then
	configure_planefence "TWEETEVERY" "true"
else
	configure_planefence "TWEETEVERY" "false"
fi
configure_planealert "HISTTIME" "$PA_HISTTIME"
configure_planealert "ALERTHEADER" "'$PF_ALERTHEADER'"
if chk_disabled "$PF_SHOWIMAGES"; then configure_planefence "SHOWIMAGES" "false"; else configure_planefence "SHOWIMAGES" "true"; fi
if chk_disabled "$PA_SHOWIMAGES"; then configure_planealert "SHOWIMAGES" "false"; else configure_planealert "SHOWIMAGES" "true"; fi

if chk_disabled "$PF_CHECKROUTE"; then configure_planefence "CHECKROUTE" "false"; else configure_planefence "CHECKROUTE" "true"; fi

if [[ -n "$PF_SOCK30003HOST" ]]; then
	# shellcheck disable=SC2001
	a=$(sed 's|\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)|\1\_\2\_\3\_\4|g' <<<"$PF_SOCK30003HOST")
	sed -i 's|\(^\s*LOGFILEBASE=/run/socket30003/dump1090-\).*|\1'"$a"'-|' /usr/share/planefence/planefence.conf
	unset a
else
	sleep 10s
	"${s6wrap[@]}" echo "----------------------------------------------------------"
	"${s6wrap[@]}" echo "!!! STOP !!!! You haven't configured PF_SOCK30003HOST for Planefence !!!!"
	"${s6wrap[@]}" echo "Planefence will not run unless you edit it configuration."
	"${s6wrap[@]}" echo "You can do this by pressing CTRL-c now and typing:"
	"${s6wrap[@]}" echo "sudo nano -l ~/planefence/planefence.config"
	"${s6wrap[@]}" echo "Once done, restart the container and this message should disappear."
	"${s6wrap[@]}" echo "----------------------------------------------------------"
	while true; do
		sleep 99999
	done
fi
#
# Deal with duplicates. Put IGNOREDUPES in its place and create (or delete) the link to the ignorelist:
if chk_enabled "$PF_IGNOREDUPES"; then configure_planefence "IGNOREDUPES" "ON"; else configure_planefence "IGNOREDUPES" "OFF"; fi
configure_planefence "COLLAPSEWITHIN" "${PF_COLLAPSEWITHIN:-300}"
a="$(sed -n 's/^\s*IGNORELIST=\(.*\)/\1/p' /usr/share/planefence/planefence.conf | sed 's/\"//g')"
[[ -n "$a" ]] && ln -sf "$a" /usr/share/planefence/html/ignorelist.txt || rm -f /usr/share/planefence/html/ignorelist.txt
unset a
#
# -----------------------------------------------------------------------------------
#
# enable or disable tweeting:
#

# Despite the name, this variable also works for Mastodon and Discord notifications:
# You can use PF_TWATTRIB/PA_TWATTRIB or PF_ATTRIB/PA_ATTRIB or simply $ATTRIB
# If PA_[TW]ATTRIB isn't set, but PF_[TW]ATTRIB has a value, then the latter will also be used for Plane-Alert
if [[ -n "${PF_TWATTRIB:-${PF_ATTRIB:-$ATTRIB}}" ]]; then configure_planefence "ATTRIB" "${PF_TWATTRIB:-$PF_ATTRIB}"; fi
if [[ -n "${PA_TWATTRIB:-${PA_ATTRIB:-$ATTRIB}}" ]]; then configure_planealert "ATTRIB" "${PA_TWATTRIB:-${PA_ATTRIB:-$ATTRIB}}"; fi

# -----------------------------------------------------------------------------------
# Set notifications date/time format:
if [[ -n "$NOTIF_DATEFORMAT" ]]; then configure_both "NOTIF_DATEFORMAT" "$NOTIF_DATEFORMAT"; fi
# ---------------------------------------------------------------------

# enable/disable planeheat;
if chk_disabled "$PF_HEATMAP"; then configure_planefence "PLANEHEAT" "OFF"; else configure_planefence "PLANEHEAT" "ON"; fi
# Change the heatmap height and width if they are defined in the .env parameter file:
configure_planefence "HEATMAPHEIGHT" "$PF_MAPHEIGHT"
configure_planefence "HEATMAPWIDTH" "$PF_MAPWIDTH"
configure_planefence "HEATMAPZOOM" "$PF_MAPZOOM"
#
# Also do this for files in the past -- /usr/share/planefence/html/planefence-??????.html
if compgen -G "$1/planefence-??????.html" >/dev/null; then
	for i in /usr/share/planefence/html/planefence-??????.html; do
		[[ -n "$PF_MAPWIDTH" ]] && sed -i 's|\(^\s*<div id=\"map\" style=\"width:.*;\)|<div id=\"map\" style=\"width:'"$PF_MAPWIDTH"';|' "$i"
		[[ -n "$PF_MAPHEIGHT" ]] && sed -i 's|\(; height:[^\"]*\)|; height: '"$PF_MAPHEIGHT"'\"|' "$i"
		[[ -n "$PF_MAPZOOM" ]] && sed -i 's|\(^\s*var map =.*], \)\(.*\)|\1'"$PF_MAPZOOM"');|' "$i"
	done
fi

# place the screenshotting URL in place:

if [[ -n "$PF_SCREENSHOTURL" ]]; then
	configure_both "SCREENSHOTURL" "$PF_SCREENSHOTURL"
fi
if [[ -n "$PF_SCREENSHOT_TIMEOUT" ]]; then
	configure_both "SCREENSHOT_TIMEOUT" "$PF_SCREENSHOT_TIMEOUT"
fi

# if it still doesn't exist, something went drastically wrong and we need to set $PF_PLANEALERT to OFF!
if [[ ! -f /usr/share/planefence/persist/plane-alert-db.txt ]] && chk_enabled "$PF_PLANEALERT"; then
	"${s6wrap[@]}" echo "Cannot find or create the plane-alert-db.txt file. Disabling Plane-Alert."
	"${s6wrap[@]}" echo "Do this on the host to get a base file:"
	"${s6wrap[@]}" echo "curl --compressed -s https://raw.githubusercontent.com/kx1t/docker-planefence/plane-alert/plane-alert-db.txt >~/.planefence/plane-alert-db.txt"
	"${s6wrap[@]}" echo "and then restart this docker container"
	PF_PLANEALERT="OFF"
fi

# make sure $PLANEALERT is set to ON in the planefence.conf file, so it will be invoked:
if chk_enabled "$PF_PLANEALERT"; then configure_planefence "PLANEALERT" "ON"; else configure_planefence "PLANEALERT" "OFF"; fi
# Go get the plane-alert-db files:
/usr/share/plane-alert/get-pa-alertlist.sh
/usr/share/plane-alert/get-silhouettes.sh

configure_planefence "PF_DISCORD" "$PF_DISCORD"
configure_planealert "PA_DISCORD" "$PA_DISCORD"
configure_planealert "PA_DISCORD_WEBHOOKS" "${PA_DISCORD_WEBHOOKS}"
configure_planefence "PF_DISCORD_WEBHOOKS" "${PF_DISCORD_WEBHOOKS}"
configure_planealert "PA_DISCORD_COLOR" "$PA_DISCORD_COLOR"
configure_both "DISCORD_FEEDER_NAME" "${DISCORD_FEEDER_NAME}"
configure_both "DISCORD_MEDIA" "${DISCORD_MEDIA}"
configure_both "NOTIFICATION_SERVER" "NOTIFICATION_SERVER"

# Add OPENAIPKEY for use with OpenAIP, necessary for it to work if PF_OPENAIP_LAYER is ON
configure_planefence "OPENAIPKEY" "$PF_OPENAIPKEY"

# Configure Mastodon parameters:
if [[ -n "$MASTODON_SERVER" ]] && [[ -n "$MASTODON_ACCESS_TOKEN" ]]; then
	MASTODON_SERVER="${MASTODON_SERVER,,}"
	# strip http:// https://
	if [[ "${MASTODON_SERVER:0:7}" == "http://" ]]; then MASTODON_SERVER="${MASTODON_SERVER:7}"; fi
	if [[ "${MASTODON_SERVER:0:8}" == "https://" ]]; then MASTODON_SERVER="${MASTODON_SERVER:8}"; fi
	mast_result="$(curl -m 5 -sSL -H "Authorization: Bearer $MASTODON_ACCESS_TOKEN" "https://${MASTODON_SERVER}/api/v1/accounts/verify_credentials")"
	if ! grep -iq "The access token is invalid\|<body class='error'>" <<<"$mast_result" >/dev/null 2>&1; then
		configure_both "MASTODON_NAME" "$(jq -r '.acct' <<<"$mast_result")"
	fi
	if chk_enabled "${PF_MASTODON,,}"; then
		configure_planefence "MASTODON_ACCESS_TOKEN" "$MASTODON_ACCESS_TOKEN"
		configure_planefence "MASTODON_SERVER" "$MASTODON_SERVER"
		configure_planefence "MASTODON_VISIBILITY" "${PF_MASTODON_VISIBILITY:-unlisted}"
	else
		configure_planefence "MASTODON_ACCESS_TOKEN" ""
		configure_planefence "MASTODON_SERVER" ""
	fi
	if chk_enabled "${PA_MASTODON,,}"; then
		configure_planealert "MASTODON_ACCESS_TOKEN" "$MASTODON_ACCESS_TOKEN"
		configure_planealert "MASTODON_SERVER" "$MASTODON_SERVER"
		configure_planealert "MASTODON_VISIBILITY" "${PA_MASTODON_VISIBILITY:-unlisted}"
		configure_planealert "MASTODON_MAXIMGS" "${PA_MASTODON_MAXIMGS:-1}"
		configure_planealert "MASTODON_RETENTION_TIME" "${MASTODON_RETENTION_TIME:-7}"
	else
		configure_planealert "MASTODON_ACCESS_TOKEN" ""
		configure_planealert "MASTODON_SERVER" ""
	fi
fi

# Configure Telegram parameters:
configure_planefence "TELEGRAM_ENABLED" "$PF_TELEGRAM_ENABLED"
configure_planealert "TELEGRAM_ENABLED" "$PA_TELEGRAM_ENABLED"
configure_both "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
configure_planefence "TELEGRAM_CHAT_ID" "$PF_TELEGRAM_CHAT_ID"
configure_planealert "TELEGRAM_CHAT_ID" "$PA_TELEGRAM_CHAT_ID"

configure_planealert "NAME" "${PF_NAME:-My}"
configure_planealert "ADSBLINK" "$PF_MAPURL"
configure_planealert "RANGE" "${PF_PARANGE:-999999}"
configure_planealert "SQUAWKS" "$PF_PA_SQUAWKS"

if chk_enabled "$PF_AUTOREFRESH"; then configure_planefence "AUTOREFRESH" "true"; else configure_planefence "AUTOREFRESH" "false"; fi
if chk_enabled "${PA_AUTOREFRESH:-$PF_AUTOREFRESH}"; then configure_planealert "AUTOREFRESH" "true"; else configure_planealert "AUTOREFRESH" "false"; fi

#
#--------------------------------------------------------------------------------
# Check if the dist/alt/speed units haven't changed. If they have changed,
# we need to restart socket30003 so these changes are picked up:
# First, give the socket30003 startup routine a headstart so this doesn't compete with it:
while [[ ! -f /run/socket30003.up ]]; do sleep 1; done
if [[ "$PF_DISTUNIT" != $(sed -n 's/^\s*distanceunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] ||
	[[ "$PF_ALTUNIT" != $(sed -n 's/^\s*altitudeunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] ||
	[[ "$PF_SPEEDUNIT" != $(sed -n 's/^\s*speedunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] ||
	[[ "$FEEDER_LAT" != $(sed -n 's/^\s*latitude=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] ||
	[[ "$FEEDER_LONG" != $(sed -n 's/^\s*longitude=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] ||
	[[ "$PF_SOCK30003HOST" != $(sed -n 's/^\s*PEER_HOST=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] ||
	[[ "${PF_SOCK30003PORT:-30003}" != $(sed -n 's/^\s*PEER_PORT=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]]; then
	[[ -n "$PF_DISTUNIT" ]] && sed -i 's/\(^\s*distanceunit=\).*/\1'"$PF_DISTUNIT"'/' /usr/share/socket30003/socket30003.cfg
	[[ -n "$PF_SPEEDUNIT" ]] && sed -i 's/\(^\s*speedunit=\).*/\1'"$PF_SPEEDUNIT"'/' /usr/share/socket30003/socket30003.cfg
	[[ -n "$PF_ALTUNIT" ]] && sed -i 's/\(^\s*altitudeunit=\).*/\1'"$PF_ALTUNIT"'/' /usr/share/socket30003/socket30003.cfg
	sed -i 's/\(^\s*latitude=\).*/\1'"$FEEDER_LAT"'/' /usr/share/socket30003/socket30003.cfg
	sed -i 's/\(^\s*longitude=\).*/\1'"$FEEDER_LONG"'/' /usr/share/socket30003/socket30003.cfg
	sed -i 's|\(^\s*PEER_HOST=\).*|\1'"$PF_SOCK30003HOST"'|' /usr/share/socket30003/socket30003.cfg
	sed -i 's|\(^\s*PEER_PORT=\).*|\1'"${PF_SOCK30003PORT:-30003}"'|' /usr/share/socket30003/socket30003.cfg
	pkill socket30003.pl
fi
#
#--------------------------------------------------------------------------------
# Check if the remote airlinename server is online
#[[ "$PF_CHECKREMOTEDB" != "OFF" ]] && a="$(curl -L -s https://get-airline.planefence.com/?flight=hello_from_$(grep 'PF_NAME' /usr/share/planefence/persist/planefence.config | awk -F '=' '{ print $2 }' | tr -dc '[:alnum:]')_bld_$([[ -f /usr/share/planefence/build ]] && cat /usr/share/planefence/build || cat /root/.buildtime | cut -c 1-23 | tr ' ' '_'))" || a=""
#shellcheck disable=SC2046
! chk_disabled "$PF_CHECKREMOTEDB" && a="$(curl -L -s "$REMOTEURL"/?flight=hello_from_$(grep 'PF_NAME' /usr/share/planefence/persist/planefence.config | awk -F '=' '{ print $2 }' | tr -dc '[:alnum:]')_bld_$([[ -f /usr/share/planefence/branch ]] && cat /usr/share/planefence/branch || cat /root/.buildtime))" || a=""
[[ "${a:0:4}" == "#100" ]] && sed -i 's|\(^\s*CHECKREMOTEDB=\).*|\1ON|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*CHECKREMOTEDB=\).*|\1OFF|' /usr/share/planefence/planefence.conf
#
#--------------------------------------------------------------------------------
# Move web page background pictures in place
[[ -f /usr/share/planefence/persist/pf_background.jpg ]] && cp -f /usr/share/planefence/persist/pf_background.jpg /usr/share/planefence/html || rm -f /usr/share/planefence/html/pf_background.jpg
[[ -f /usr/share/planefence/persist/pa_background.jpg ]] && cp -f /usr/share/planefence/persist/pa_background.jpg /usr/share/planefence/html/plane-alert || rm -f /usr/share/planefence/html/plane-alert/pa_background.jpg

#--------------------------------------------------------------------------------
# Put the MOTDs in place:
configure_planefence "PF_MOTD" "$PF_MOTD"
configure_planealert "PA_MOTD" "$PA_MOTD"
#
#--------------------------------------------------------------------------------
# Set TRACKSERVICE and TRACKLIMIT for Planefence and plane-alert.
# note that $PF_TRACKSVC has been deprecated/EOL'd
configure_planefence "TRACKSERVICE" "${PF_TRACKSERVICE:-globe.adsbexchange.com}"
configure_planealert "TRACKSERVICE" "${PA_TRACKSERVICE:-globe.adsbexchange.com}"
configure_planealert "TRACKLIMIT" "$PA_TRACKLIMIT"
if chk_disabled "$PA_TRACK_FIRSTSEEN"; then configure_planealert "TRACK_FIRSTSEEN" "disabled"; else configure_planealert "TRACK_FIRSTSEEN" "enabled"; fi
#
#--------------------------------------------------------------------------------
# Configure MQTT notifications for Planefence and plane-alert
configure_planefence "MQTT_URL" "$PF_MQTT_URL"
configure_planefence "MQTT_CLIENT_ID" "$PF_MQTT_CLIENT_ID"
configure_planefence "MQTT_TOPIC" "$PF_MQTT_TOPIC"
configure_planefence "MQTT_DATETIME_FORMAT" "$PF_MQTT_DATETIME_FORMAT"
configure_planefence "MQTT_USERNAME" "$PF_MQTT_USERNAME"
configure_planefence "MQTT_PASSWORD" "$PF_MQTT_PASSWORD"
configure_planefence "MQTT_QOS" "$PF_MQTT_QOS"
configure_planefence "MQTT_FIELDS" "$PF_MQTT_FIELDS"

configure_planealert "MQTT_URL" "$PA_MQTT_URL"
configure_planealert "MQTT_CLIENT_ID" "$PA_MQTT_CLIENT_ID"
configure_planealert "MQTT_TOPIC" "$PA_MQTT_TOPIC"
configure_planealert "MQTT_DATETIME_FORMAT" "$PA_MQTT_DATETIME_FORMAT"
configure_planealert "MQTT_USERNAME" "$PA_MQTT_USERNAME"
configure_planealert "MQTT_PASSWORD" "$PA_MQTT_PASSWORD"
configure_planealert "MQTT_QOS" "$PA_MQTT_QOS"
configure_planealert "MQTT_FIELDS" "$PA_MQTT_FIELDS"
#
#--------------------------------------------------------------------------------
# RSS related parameters:
configure_planefence "RSS_SITELINK" "$PF_RSS_SITELINK"
configure_planefence "RSS_FAVICONLINK" "$PF_RSS_FAVICONLINK"
configure_planealert "RSS_SITELINK" "$PA_RSS_SITELINK"
configure_planealert "RSS_FAVICONLINK" "$PA_RSS_FAVICONLINK"
#
#--------------------------------------------------------------------------------
# BlueSky related parameters:
if chk_enabled "$PF_BLUESKY_ENABLED" && [[ -n "$BLUESKY_HANDLE" ]]; then configure_planefence "BLUESKY_HANDLE" "$BLUESKY_HANDLE"; else configure_planefence "BLUESKY_HANDLE" ""; fi
if chk_enabled "$PF_BLUESKY_ENABLED" && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then configure_planefence "BLUESKY_APP_PASSWORD" "$BLUESKY_APP_PASSWORD"; else configure_planefence "BLUESKY_APP_PASSWORD" ""; fi
if chk_enabled "$PF_BLUESKY_ENABLED" && [[ -n "$BLUESKY_API" ]]; then configure_planefence "BLUESKY_API" "$BLUESKY_API"; else configure_planefence "BLUESKY_API" ""; fi

if chk_enabled "$PA_BLUESKY_ENABLED" && [[ -n "$BLUESKY_HANDLE" ]]; then configure_planealert "BLUESKY_HANDLE" "$BLUESKY_HANDLE"; else configure_planealert "BLUESKY_HANDLE" ""; fi
if chk_enabled "$PA_BLUESKY_ENABLED" && [[ -n "$BLUESKY_APP_PASSWORD" ]]; then configure_planealert "BLUESKY_APP_PASSWORD" "$BLUESKY_APP_PASSWORD"; else configure_planealert "BLUESKY_APP_PASSWORD" ""; fi
if chk_enabled "$PA_BLUESKY_ENABLED" && [[ -n "$BLUESKY_API" ]]; then configure_planealert "BLUESKY_API" "$BLUESKY_API"; else configure_planealert "BLUESKY_API" ""; fi
#
#--------------------------------------------------------------------------------
# Make sure that all past map links follow PA/PF_TRACKS
replacement="${PF_TRACKSERVICE:-https://globe.adsbexchange.com}"
replacement="${replacement,,}"
if [[ ${replacement::4} != "http" ]]; then replacement="https://$replacement"; fi
shopt -s nullglob
for file in /usr/share/planefence/html/*.csv; do
	sed -i 's|\(http[s]\?://\)[^/]\+[/]\?\(?icao=.*\)|'"$replacement"'/\2|gI' "$file"
done

if [[ -f /usr/share/planefence/html/plane-alert/plane-alert.csv ]]; then
	replacement="${PA_TRACKSERVICE:-https://globe.adsbexchange.com}"
	replacement="${replacement,,}"
	if [[ ${replacement::4} != "http" ]]; then replacement="https://$replacement"; fi
	sed -i 's|\(http[s]\?://\)[^/]\+[/]\?\(?icao=.*\)|'"$replacement"'/\2|gI' /usr/share/planefence/html/plane-alert/plane-alert.csv
fi

# ---------------------------------------------------------------------
# Set DARKMODE

if chk_enabled "$PF_DARKMODE"; then configure_planefence "DARKMODE" "true"; else configure_planefence "DARKMODE" "false"; fi
if chk_enabled "$PA_DARKMODE"; then configure_planealert "DARKMODE" "true"; else configure_planealert "DARKMODE" "false"; fi
#
# ---------------------------------------------------------------------
# Set default table sizes:
configure_planefence "TABLESIZE" "${PF_TABLESIZE:-50}"
configure_planealert "TABLESIZE" "${PA_TABLESIZE:-50}"
#--------------------------------------------------------------------------------
# Configure the Planefence/Plane-Alert Ignore button:
configure_planefence "SHOWIGNORE" "${PF_SHOWIGNORE:-false}"
configure_planealert "SHOWIGNORE" "${PA_SHOWIGNORE:-false}"
configure_planealert "EXCLUSIONS" "${PA_EXCLUSIONS}"
touch /tmp/.force_pa_webpage_update	# this is used to force a Plane-Alert webpage update upon change of parameters
#
# ---------------------------------------------------------------------
# Last thing - save the date we processed the config to disk. That way, if ~/.planefence/planefence.conf is changed,
# we know that we need to re-run this prep routine!
date +%s >/run/planefence/last-config-change
