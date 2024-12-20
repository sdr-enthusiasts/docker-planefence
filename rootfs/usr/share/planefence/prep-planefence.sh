#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2268,SC2174,SC1091,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2020-2024 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence4docker/
#
# Programmers note: when using sed for URLs or file names, make sure NOT to use '/'
# as command separator, but use something else instead, for example '|'
#
# -----------------------------------------------------------------------------------
#
source /scripts/common 

REMOTEURL=$(sed -n 's/\(^\s*REMOTEURL=\)\(.*\)/\2/p' /usr/share/planefence/planefence.conf)

function configure_planefence() {
	local SETTING_NAME="$1"
	local SETTING_VALUE="$2"
	if [[ -n "$SETTING_VALUE" ]]; then
		sed -i "s~\(^\s*${SETTING_NAME}=\).*~\1${SETTING_VALUE}~" /usr/share/planefence/planefence.conf
	else
		sed -i "s|\(^\s*${SETTING_NAME}=\).*|\1|" /usr/share/planefence/planefence.conf
	fi
}
function configure_planealert() {
	local SETTING_NAME="$1"
	local SETTING_VALUE="$2"
	if [[ -n "$SETTING_VALUE" ]]; then
		sed -i "s~\(^\s*${SETTING_NAME}=\).*~\1${SETTING_VALUE}~" /usr/share/plane-alert/plane-alert.conf
	else
		sed -i "s|\(^\s*${SETTING_NAME}=\).*|\1|" /usr/share/plane-alert/plane-alert.conf
	fi
}
function configure_both() {
	configure_planefence "$1" "$2"
	configure_planealert "$1" "$2"
}

[[ "$LOGLEVEL" != "ERROR" ]] && "${s6wrap[@]}" echo "Running PlaneFence configuration - either the container is restarted or a config change was detected." || true
# Sometimes, variables are passed in through .env in the Docker-compose directory
# However, if there is a planefence.config file in the ..../persist directory
# (by default exposed to ~/.planefence) then export all of those variables as well
# note that the grep strips off any spaces at the beginning of a line, and any commented line
mkdir -p /usr/share/planefence/persist/.internal
mkdir -p /usr/share/planefence/persist/planepix
chmod -f a=rwx /usr/share/planefence/persist
chmod -fR a+rw /usr/share/planefence/persist/{.[!.]*,*}
chmod u=rwx,go=rx /usr/share/planefence/persist/.internal

chmod a=rwx /usr/share/planefence/persist/planepix
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
# Move the jscript files from the staging directory into the html directory.
# this cannot be done at build time because the directory is exposed and it is
# overwritten by the host at start of runtime

mkdir -p /usr/share/planefence/html/plane-alert/silhouettes
mv -f /usr/share/planefence/html/Silhouettes.zip /tmp/silhouettes-org.zip

cp -f /usr/share/planefence/stage/* /usr/share/planefence/html
rm -f /usr/share/planefence/html/planefence.config /usr/share/planefence/html/*.template /usr/share/planefence/html/aircraft-database-complete-
mv -f /usr/share/planefence/html/pa_query.php /usr/share/planefence/html/plane-alert
[[ ! -f /usr/share/planefence/persist/pf_background.jpg ]] && cp -f /usr/share/planefence/html/background.jpg /usr/share/planefence/persist/pf_background.jpg
[[ ! -f /usr/share/planefence/persist/pa_background.jpg ]] && cp -f /usr/share/planefence/html/background.jpg /usr/share/planefence/persist/pa_background.jpg
rm -f /usr/share/planefence/html/background.jpg
[[ ! -f /usr/share/planefence/persist/planefence-ignore.txt ]] && mv -f /usr/share/planefence/html/planefence-ignore.txt /usr/share/planefence/persist/ || rm -f /usr/share/planefence/html/planefence-ignore.txt
#
# Copy the airlinecodes.txt file to the persist directory
cp -n /usr/share/planefence/airlinecodes.txt /usr/share/planefence/persist
chmod a+rw /usr/share/planefence/persist/airlinecodes.txt

cp -u --backup=numbered /usr/share/planefence/stage/*.template /usr/share/planefence/persist >/dev/null 2>&1
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
# LOOPTIME is the time between two runs of PlaneFence (in seconds)
if [[ "$PF_INTERVAL" != "" ]]; then
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
		"${s6wrap[@]}" echo "!!! STOP !!!! You haven\'t configured FEEDER_LON and/or FEEDER_LAT for PlaneFence !!!!"
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
[[ -n "$FEEDER_LAT" ]] && sed -i 's/\(^\s*LAT=\).*/\1'"\"$FEEDER_LAT\""'/' /usr/share/planefence/planefence.conf || { "${s6wrap[@]}" echo "Error - \$FEEDER_LAT ($FEEDER_LAT) not defined"; while :; do sleep 2073600; done; }
[[ -n "$FEEDER_LONG" ]] && sed -i 's/\(^\s*LON=\).*/\1'"\"$FEEDER_LONG\""'/' /usr/share/planefence/planefence.conf || { "${s6wrap[@]}" echo "Error - \$FEEDER_LONG not defined"; while :; do sleep 2073600; done; }
[[ -n "$PF_MAXALT" ]] && sed -i 's/\(^\s*MAXALT=\).*/\1'"\"$PF_MAXALT\""'/' /usr/share/planefence/planefence.conf
[[ -n "$PF_MAXDIST" ]] && sed -i 's/\(^\s*DIST=\).*/\1'"\"$PF_MAXDIST\""'/' /usr/share/planefence/planefence.conf
[[ -n "$PF_ELEVATION" ]] && sed -i 's/\(^\s*ALTCORR=\).*/\1'"\"$PF_ELEVATION\""'/' /usr/share/planefence/planefence.conf
[[ -n "$PF_NAME" ]] && sed -i 's/\(^\s*MY=\).*/\1'"\"$PF_NAME\""'/' /usr/share/planefence/planefence.conf || sed -i 's/\(^\s*MY=\).*/\1\"My\"/' /usr/share/planefence/planefence.conf
[[ -n "$PF_TRACKSVC" ]] && sed -i 's|\(^\s*TRACKSERVICE=\).*|\1'"\"$PF_TRACKSVC\""'|' /usr/share/planefence/planefence.conf
[[ -n "$PF_MAPURL" ]] && sed -i 's|\(^\s*MYURL=\).*|\1'"\"$PF_MAPURL\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*MYURL=\).*|\1|' /usr/share/planefence/planefence.conf
[[ -n "$PF_NOISECAPT" ]] && sed -i 's|\(^\s*REMOTENOISE=\).*|\1'"\"$PF_NOISECAPT\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*REMOTENOISE=\).*|\1|' /usr/share/planefence/planefence.conf
[[ -n "$PF_FUDGELOC" ]] && sed -i 's|\(^\s*FUDGELOC=\).*|\1'"\"$PF_FUDGELOC\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*FUDGELOC=\).*|\1|' /usr/share/planefence/planefence.conf
chk_enabled "$PF_OPENAIP_LAYER" && sed -i 's|\(^\s*OPENAIP_LAYER=\).*|\1'"\"ON\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*OPENAIP_LAYER=\).*|\1'"\"OFF\""'|' /usr/share/planefence/planefence.conf
[[ -n "$PF_TWEET_MINTIME" ]] && sed -i 's|\(^\s*TWEET_MINTIME=\).*|\1'"$PF_TWEET_MINTIME"'|' /usr/share/planefence/planefence.conf
[[ "$PF_TWEET_BEHAVIOR" == "PRE" ]] && sed -i 's|\(^\s*TWEET_BEHAVIOR=\).*|\1PRE|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*TWEET_BEHAVIOR=\).*|\1POST|' /usr/share/planefence/planefence.conf
chk_enabled "$PF_PLANEALERT" && sed -i 's|\(^\s*PA_LINK=\).*|\1\"'"$PF_PA_LINK"'\"|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*PA_LINK=\).*|\1|' /usr/share/planefence/planefence.conf
chk_enabled "$PF_TWEETEVERY" && sed -i 's|\(^\s*TWEETEVERY=\).*|\1true|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*TWEETEVERY=\).*|\1false|' /usr/share/planefence/planefence.conf
[[ -n "$PA_HISTTIME" ]] && sed -i 's|\(^\s*HISTTIME=\).*|\1\"'"$PA_HISTTIME"'\"|' /usr/share/plane-alert/plane-alert.conf
[[ -n "$PF_ALERTHEADER" ]] && sed -i "s|\(^\s*ALERTHEADER=\).*|\1\'$PF_ALERTHEADER\'|" /usr/share/plane-alert/plane-alert.conf

if [[ -n "$PF_SOCK30003HOST" ]]; then
	# shellcheck disable=SC2001
	a=$(sed 's|\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)|\1\_\2\_\3\_\4|g' <<< "$PF_SOCK30003HOST")
	sed -i 's|\(^\s*LOGFILEBASE=/run/socket30003/dump1090-\).*|\1'"$a"'-|' /usr/share/planefence/planefence.conf
	sed -i 's/127_0_0_1/'"$a"'/' /usr/share/planefence/planeheat.sh
	unset a
else
	sleep 10s
	"${s6wrap[@]}" echo "----------------------------------------------------------"
	"${s6wrap[@]}" echo "!!! STOP !!!! You haven't configured PF_SOCK30003HOST for PlaneFence !!!!"
	"${s6wrap[@]}" echo "Planefence will not run unless you edit it configuration."
	"${s6wrap[@]}" echo "You can do this by pressing CTRL-c now and typing:"
	"${s6wrap[@]}" echo "sudo nano -l ~/.planefence/planefence.config"
	"${s6wrap[@]}" echo "Once done, restart the container and this message should disappear."
	"${s6wrap[@]}" echo "----------------------------------------------------------"
	while true
	do
			sleep 99999
	done
fi
#
# Deal with duplicates. Put IGNOREDUPES in its place and create (or delete) the link to the ignorelist:
[[ -n "$PF_IGNOREDUPES" ]] && sed -i 's|\(^\s*IGNOREDUPES=\).*|\1ON|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*IGNOREDUPES=\).*|\1OFF|' /usr/share/planefence/planefence.conf
[[ -n "$PF_COLLAPSEWITHIN" ]] && sed -i 's|\(^\s*COLLAPSEWITHIN=\).*|\1'"$PF_COLLAPSEWITHIN"'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*IGNOREDUPES=\).*|\1300|' /usr/share/planefence/planefence.conf
a="$(sed -n 's/^\s*IGNORELIST=\(.*\)/\1/p' /usr/share/planefence/planefence.conf  | sed 's/\"//g')"
[[ -n "$a" ]] && ln -sf "$a" /usr/share/planefence/html/ignorelist.txt || rm -f /usr/share/planefence/html/ignorelist.txt
unset a
#
# -----------------------------------------------------------------------------------
#
# same for planeheat.sh
#
sed -i 's/\(^\s*LAT=\).*/\1'"\"$FEEDER_LAT\""'/' /usr/share/planefence/planeheat.sh
sed -i 's/\(^\s*LON=\).*/\1'"\"$FEEDER_LONG\""'/' /usr/share/planefence/planeheat.sh
[[ -n "$PF_MAXALT" ]] && sed -i 's/\(^\s*MAXALT=\).*/\1'"\"$PF_MAXALT\""'/' /usr/share/planefence/planeheat.sh
[[ -n "$PF_MAXDIST" ]] && sed -i 's/\(^\s*DIST=\).*/\1'"\"$PF_MAXDIST\""'/' /usr/share/planefence/planeheat.sh
# -----------------------------------------------------------------------------------
#

# One-time action for builds after 20210218-094500EST: we moved the backup of .twurlrc from /run/planefence to /usr/share/planefence/persist
# so /run/* can be TMPFS. As a result, if .twurlrc is still there, move it to its new location.
# This one-time action can be obsoleted once all users have moved over.
[[ -f /run/planefence/.twurlrc ]] && mv -n /run/planefence/.twurlrc /usr/share/planefence/persist
# Now update the .twurlrc in /root if there is a newer version in the persist directory
[[ -f /usr/share/planefence/persist/.twurlrc ]] && cp -u /usr/share/planefence/persist/.twurlrc /root
# If there's still nothing in the persist directory or it appears out of date, back up the .twurlrc from /root to there
[[ -f /root/.twurlrc ]] && cp -n /root/.twurlrc /usr/share/planefence/persist
#
# -----------------------------------------------------------------------------------
#
# enable or disable tweeting:
#
chk_disabled "${PF_TWEET}" && sed -i 's/\(^\s*PLANETWEET=\).*/\1/' /usr/share/planefence/planefence.conf
if chk_enabled "${PF_TWEET,,}"; then
	if [[ ! -f ~/.twurlrc ]]; then
			"${s6wrap[@]}" echo "Warning: PF_TWEET is set to ON in .env file, but the Twitter account is not configured."
			"${s6wrap[@]}" echo "Sign up for a developer account at Twitter, create an app, and get a Consumer Key / Secret."
			"${s6wrap[@]}" echo "Then run this from the host machine: \"docker exec -it planefence /root/config_tweeting.sh\""
			"${s6wrap[@]}" echo "For more information on how to sign up for a Twitter Developer Account, see this link:"
			"${s6wrap[@]}" echo "https://elfsight.com/blog/2020/03/how-to-get-twitter-api-key/"
			"${s6wrap[@]}" echo "PlaneFence will continue to start without Twitter functionality."
			sed -i 's/\(^\s*PLANETWEET=\).*/\1/' /usr/share/planefence/planefence.conf
	else
			sed -i 's|\(^\s*PLANETWEET=\).*|\1'"$(sed -n '/profiles:/{n;p;}' /root/.twurlrc | tr -d '[:blank:][=:=]')"'|' /usr/share/planefence/planefence.conf
      [[ -n "$PF_TWATTRIB" ]] && sed -i 's|\(^\s*ATTRIB=\).*|\1'"\"$PF_TWATTRIB\""'|' /usr/share/planefence/planefence.conf
  fi
fi

# Despite the name, this variable also works for Mastodon and Discord notifications:
# You can use PF_TWATTRIB/PA_TWATTRIB or PF_ATTRIB/PA_ATTRIB or simply $ATTRIB
# If PA_[TW]ATTRIB isn't set, but PF_[TW]ATTRIB has a value, then the latter will also be used for Plane-Alert
# Finally, if you set ATTRIB to a value, we will use that for both PA and PF and ignore any PF_[TW]ATTRIB/PA_[TW]ATTRIB values
[[ -n "$PF_TWATTRIB$PF_ATTRIB" ]] && configure_planefence "ATTRIB" "\"$PF_TWATTRIB$PF_ATTRIB\""
[[ -n "$PA_TWATTRIB$PA_ATTRIB" ]] && configure_planealert "ATTRIB" "\"$PA_TWATTRIB$PA_ATTRIB\""
[[ -z "$PA_TWATTRIB$PA_ATTRIB" ]] && [[ -n "$PF_TWATTRIB$PF_ATTRIB" ]] && configure_planealert "ATTRIB" "\"$PF_TWATTRIB$PF_ATTRIB\""
[[ -n "$ATTRIB" ]] && configure_both "ATTRIB" "\"$ATTRIB\""


# -----------------------------------------------------------------------------------
#
# enable/disable planeheat;
chk_disabled "$PF_HEATMAP" && configure_planefence "PLANEHEAT" "OFF" || configure_planefence "PLANEHEAT" "ON"
# Change the heatmap height and width if they are defined in the .env parameter file:
[[ -n "$PF_MAPHEIGHT" ]] && sed -i 's|\(^\s*HEATMAPHEIGHT=\).*|\1'"\"$PF_MAPHEIGHT\""'|' /usr/share/planefence/planefence.conf
[[ -n "$PF_MAPWIDTH" ]] && sed -i 's|\(^\s*HEATMAPWIDTH=\).*|\1'"\"$PF_MAPWIDTH\""'|' /usr/share/planefence/planefence.conf
[[ -n "$PF_MAPZOOM" ]] && sed -i 's|\(^\s*HEATMAPZOOM=\).*|\1'"\"$PF_MAPZOOM\""'|' /usr/share/planefence/planefence.conf
#
# Also do this for files in the past -- /usr/share/planefence/html/planefence-??????.html
if compgen -G "$1/planefence-??????.html" >/dev/null; then
	for i in /usr/share/planefence/html/planefence-??????.html; do
		[[ -n "$PF_MAPWIDTH" ]] && sed  -i 's|\(^\s*<div id=\"map\" style=\"width:.*;\)|<div id=\"map\" style=\"width:'"$PF_MAPWIDTH"';|' "$i"
		[[ -n "$PF_MAPHEIGHT" ]] && sed -i 's|\(; height:[^\"]*\)|; height: '"$PF_MAPHEIGHT"'\"|' "$i"
		[[ -n "$PF_MAPZOOM" ]] && sed -i 's|\(^\s*var map =.*], \)\(.*\)|\1'"$PF_MAPZOOM"');|' "$i"
	done
fi

# place the screenshotting URL in place:

if [[ -n "$PF_SCREENSHOTURL" ]]; then
	sed -i 's|\(^\s*SCREENSHOTURL=\).*|\1'"\"$PF_SCREENSHOTURL\""'|' /usr/share/planefence/planefence.conf
	sed -i 's|\(^\s*SCREENSHOTURL=\).*|\1'"\"$PF_SCREENSHOTURL\""'|' /usr/share/plane-alert/plane-alert.conf
fi
if [[ -n "$PF_SCREENSHOT_TIMEOUT" ]]; then
	sed -i 's|\(^\s*SCREENSHOT_TIMEOUT=\).*|\1'"\"$PF_SCREENSHOT_TIMEOUT\""'|' /usr/share/planefence/planefence.conf
	sed -i 's|\(^\s*SCREENSHOT_TIMEOUT=\).*|\1'"\"$PF_SCREENSHOT_TIMEOUT\""'|' /usr/share/plane-alert/plane-alert.conf
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
chk_enabled "$PF_PLANEALERT" && sed -i 's|\(^\s*PLANEALERT=\).*|\1'"\"ON\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*PLANEALERT=\).*|\1'"\"OFF\""'|' /usr/share/planefence/planefence.conf
# Go get the plane-alert-db files:
/usr/share/plane-alert/get-pa-alertlist.sh
/usr/share/plane-alert/get-silhouettes.sh

# Now make sure that the file containing the twitter IDs is rewritten with 1 ID per line
[[ -n "$PF_PA_TWID" ]] && tr , "\n" <<< "$PF_PA_TWID" > /usr/share/plane-alert/plane-alert.twitterid || rm -f /usr/share/plane-alert/plane-alert.twitterid
# and write the rest of the parameters into their place
[[ -n "$PF_PA_TWID" ]] && [[ "$PF_PA_TWEET" == "DM" ]] && sed -i 's|\(^\s*TWITTER=\).*|\1DM|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*TWITTER=\).*|\1false|' /usr/share/plane-alert/plane-alert.conf
[[ "$PF_PA_TWEET" == "TWEET" ]] && sed -i 's|\(^\s*TWITTER=\).*|\1TWEET|' /usr/share/plane-alert/plane-alert.conf
[[ "$PF_PA_TWEET" != "TWEET" ]] && [[ "$PF_PA_TWEET" != "DM" ]] && sed -i 's|\(^\s*TWITTER=\).*|\1false|' /usr/share/plane-alert/plane-alert.conf
configure_planefence "PF_DISCORD" "$PF_DISCORD"
configure_planealert "PA_DISCORD" "$PA_DISCORD"
configure_planealert "PA_DISCORD_WEBHOOKS" "\"${PA_DISCORD_WEBHOOKS}\""
configure_planefence "PF_DISCORD_WEBHOOKS" "\"${PF_DISCORD_WEBHOOKS}\""
configure_both "DISCORD_FEEDER_NAME" "\"${DISCORD_FEEDER_NAME}\""
configure_both "DISCORD_MEDIA" "\"${DISCORD_MEDIA}\""
configure_both "NOTIFICATION_SERVER" "\"NOTIFICATION_SERVER\""

# Add OPENAIPKEY for use with OpenAIP, necessary for it to work if PF_OPENAIP_LAYER is ON
configure_planefence "OPENAIPKEY" "$PF_OPENAIPKEY"

# Configure Mastodon parameters:
if [[ -n "$MASTODON_SERVER" ]] && [[ -n "$MASTODON_ACCESS_TOKEN" ]]; then
	MASTODON_SERVER="${MASTODON_SERVER,,}"
	# strip http:// https://
	[[ "${MASTODON_SERVER:0:7}" == "http://" ]] && MASTODON_SERVER="${MASTODON_SERVER:7}" || true
	[[ "${MASTODON_SERVER:0:8}" == "https://" ]] && MASTODON_SERVER="${MASTODON_SERVER:8}" || true
	mast_result="$(curl -m 5 -sSL -H "Authorization: Bearer $MASTODON_ACCESS_TOKEN" "https://${MASTODON_SERVER}/api/v1/accounts/verify_credentials")"
	if  ! grep -iq "The access token is invalid\|<body class='error'>"  <<< "$mast_result" >/dev/null 2>&1; then
		configure_both "MASTODON_NAME" "$(jq -r '.acct' <<< "$mast_result")" 
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

[[ -n "$PF_NAME" ]] && sed -i 's|\(^\s*NAME=\).*|\1'"\"$PF_NAME\""'|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*NAME=\).*|\1My|' /usr/share/plane-alert/plane-alert.conf
[[ -n "$PF_MAPURL" ]] && sed -i 's|\(^\s*ADSBLINK=\).*|\1'"\"$PF_MAPURL\""'|' /usr/share/plane-alert/plane-alert.conf
# removed for now - hardcoding PlaneAlert map zoom to 7 in plane-alert.conf: [[ -n "$PF_MAPZOOM" ]] && sed -i 's|\(^\s*MAPZOOM=\).*|\1'"\"$PF_MAPZOOM\""'|' /usr/share/plane-alert/plane-alert.conf
[[ -n "$PF_PARANGE" ]] && sed -i 's|\(^\s*RANGE=\).*|\1'"$PF_PARANGE"'|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*RANGE=\).*|\1999999|' /usr/share/plane-alert/plane-alert.conf
[[ -n "$PF_PA_SQUAWKS" ]] && sed -i 's|\(^\s*SQUAWKS=\).*|\1'"$PF_PA_SQUAWKS"'|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*SQUAWKS=\).*|\1|' /usr/share/plane-alert/plane-alert.conf

configure_both "AUTOREFRESH" "${PF_AUTOREFRESH,,}"

# Write the sort-table.js into the web directory as we cannot create it during build:
cp -f /usr/share/planefence/stage/sort-table.js /usr/share/planefence/html/plane-alert
#
#--------------------------------------------------------------------------------
# Check if the dist/alt/speed units haven't changed. If they have changed,
# we need to restart socket30003 so these changes are picked up:
# First, give the socket30003 startup routine a headstart so this doesn't compete with it:
sleep 1
if [[ "$PF_DISTUNIT" != $(sed -n 's/^\s*distanceunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] \
	|| [[ "$PF_ALTUNIT" != $(sed -n 's/^\s*altitudeunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]] \
	|| [[ "$PF_SPEEDUNIT" != $(sed -n 's/^\s*speedunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]]; then
	[[ -n "$PF_DISTUNIT" ]] &&	sed -i 's/\(^\s*distanceunit=\).*/\1'"$PF_DISTUNIT"'/' /usr/share/socket30003/socket30003.cfg
	[[ -n "$PF_SPEEDUNIT" ]] && sed -i 's/\(^\s*speedunit=\).*/\1'"$PF_SPEEDUNIT"'/' /usr/share/socket30003/socket30003.cfg
	[[ -n "$PF_ALTUNIT" ]] && sed -i 's/\(^\s*altitudeunit=\).*/\1'"$PF_ALTUNIT"'/' /usr/share/socket30003/socket30003.cfg
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
# get the sample planepix file
# if curl -L -s https://raw.githubusercontent.com/sdr-enthusiasts/plane-alert-db/main/planepix.txt > /usr/share/planefence/persist/planepix.txt.samplefile
# then
# 	chmod a+r /usr/share/planefence/persist/planepix.txt.samplefile
# 	"${s6wrap[@]}" echo "Successfully downloaded planepix sample file to ~/.planefence/planepix.txt.samplefile directory."
# 	"${s6wrap[@]}" echo "To use it, rename it to, or incorporate it into ~/.planefence/planepix.txt. Any entries in this file will replace the tar1090 screenshot with a picture of the plane."
# fi
#--------------------------------------------------------------------------------
# Put the MOTDs in place:
configure_planefence "PF_MOTD" "\"$PF_MOTD\""
configure_planealert "PA_MOTD" "\"$PA_MOTD\""
#
#--------------------------------------------------------------------------------
# Set TRACKSERVICE and TRACKLIMIT for Planefence and plane-alert.
[[ -n "$PF_TRACKSERVICE" ]] && configure_planefence "TRACKSERVICE" "$PF_TRACKSERVICE" || configure_planefence "TRACKSERVICE" "globe.adsbexchange.com"
[[ -n "$PA_TRACKSERVICE" ]] && configure_planealert "TRACKSERVICE" "$PA_TRACKSERVICE" || true
[[ -n "$PA_TRACKLIMIT" ]] && configure_planealert "TRACKLIMIT" "$PA_TRACKLIMIT" || true
#
#--------------------------------------------------------------------------------
# Configure MQTT notifications for Planefence and plane-alert
[[ -n "$PF_MQTT_URL" ]] && configure_planefence "MQTT_URL" "$PF_MQTT_URL" || true
[[ -n "$PF_MQTT_CLIENT_ID" ]] && configure_planefence "MQTT_CLIENT_ID" "$PF_MQTT_CLIENT_ID" || true
[[ -n "$PF_MQTT_TOPIC" ]] && configure_planefence "MQTT_TOPIC" "$PF_MQTT_TOPIC" || true
[[ -n "$PF_MQTT_DATETIME_FORMAT" ]] && configure_planefence "MQTT_DATETIME_FORMAT" "\"$PF_MQTT_DATETIME_FORMAT\"" || true
[[ -n "$PF_MQTT_USERNAME" ]] && configure_planefence "MQTT_USERNAME" "$PF_MQTT_USERNAME" || true
[[ -n "$PF_MQTT_PASSWORD" ]] && configure_planefence "MQTT_PASSWORD" "$PF_MQTT_PASSWORD" || true
[[ -n "$PF_MQTT_QOS" ]] && configure_planefence "MQTT_QOS" "$PF_MQTT_QOS" || true

[[ -n "$PA_MQTT_URL" ]] && configure_planealert "MQTT_URL" "$PA_MQTT_URL" || true
[[ -n "$PA_MQTT_CLIENT_ID" ]] && configure_planealert "MQTT_CLIENT_ID" "$PA_MQTT_CLIENT_ID" || true
[[ -n "$PA_MQTT_TOPIC" ]] && configure_planealert "MQTT_TOPIC" "$PA_MQTT_TOPIC" || true
[[ -n "$PA_MQTT_DATETIME_FORMAT" ]] && configure_planealert "MQTT_DATETIME_FORMAT" "\"$PA_MQTT_DATETIME_FORMAT\"" || true
[[ -n "$PA_MQTT_USERNAME" ]] && configure_planealert "MQTT_USERNAME" "$PA_MQTT_USERNAME" || true
[[ -n "$PA_MQTT_PASSWORD" ]] && configure_planealert "MQTT_PASSWORD" "$PA_MQTT_PASSWORD" || true
[[ -n "$PA_MQTT_QOS" ]] && configure_planealert "MQTT_QOS" "$PA_MQTT_QOS" || true
#
#--------------------------------------------------------------------------------
# RSS related parameters:
[[ -n "$PF_RSS_SITELINK" ]] && configure_planefence "RSS_SITELINK" "$PF_RSS_SITELINK" || true
[[ -n "$PF_RSS_FAVICONLINK" ]] && configure_planefence "RSS_FAVICONLINK" "$PF_RSS_FAVICONLINK" || true
[[ -n "$PA_RSS_SITELINK" ]] && configure_planealert "RSS_SITELINK" "$PA_RSS_SITELINK" || true
[[ -n "$PA_RSS_FAVICONLINK" ]] && configure_planealert "RSS_FAVICONLINK" "$PA_RSS_FAVICONLINK" || true
#
#--------------------------------------------------------------------------------
# Last thing - save the date we processed the config to disk. That way, if ~/.planefence/planefence.conf is changed,
# we know that we need to re-run this prep routine!

configure_planealert "PF_LINK" "$PA_PF_LINK"

date +%s > /run/planefence/last-config-change
