#!/usr/bin/with-contenv bash
#shellcheck shell=bash
# -----------------------------------------------------------------------------------
# Copyright 2020, 2021 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence4docker/
#
# Programmers note: when using sed for URLs or file names, make sure NOT to use '/'
# as command separator, but use something else instead, for example '|'
#
# -----------------------------------------------------------------------------------
#
PLANEFENCEDIR=/usr/share/planefence
APPNAME="$(hostname)/planefence"
REMOTEURL=$(sed -n 's/\(^\s*REMOTEURL=\)\(.*\)/\2/p' /usr/share/planefence/planefence.conf)

[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] Running PlaneFence configuration - either the container is restarted or a config change was detected." || true
# Sometimes, variables are passed in through .env in the Docker-compose directory
# However, if there is a planefence.config file in the ..../persist directory
# (by default exposed to ~/.planefence) then export all of those variables as well
# note that the grep strips off any spaces at the beginning of a line, and any commented line
mkdir -p /usr/share/planefence/persist/.internal
chmod -fR a+rw /usr/share/planefence/persist /usr/share/planefence/persist/{.[!.]*,*}
chmod -f u=rwx,go=rx /usr/share/planefence/persist/.internal
if [[ -f /usr/share/planefence/persist/planefence.config ]]
then
	set -o allexport
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
rm -f /usr/share/planefence/html/planefence.config
mv -f /usr/share/planefence/html/pa_query.php /usr/share/planefence/html/plane-alert
[[ ! -f /usr/share/planefence/persist/pf-background.jpg ]] && cp -f /usr/share/planefence/html/background.jpg /usr/share/planefence/persist/pf_background.jpg
[[ ! -f /usr/share/planefence/persist/pa-background.jpg ]] && cp -f /usr/share/planefence/html/background.jpg /usr/share/planefence/persist/pa_background.jpg
rm -f /usr/share/planefence/html/background.jpg
[[ ! -f /usr/share/planefence/persist/planefence-ignore.txt ]] && mv -f /usr/share/planefence/html/planefence-ignore.txt /usr/share/planefence/persist/ || rm -f /usr/share/planefence/html/planefence-ignore.txt
#
# Copy the airlinecodes.txt file to the persist directory
cp -n /usr/share/planefence/airlinecodes.txt /usr/share/planefence/persist
chmod a+rw /usr/share/planefence/persist/airlinecodes.txt
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
if [[ "$PF_INTERVAL" != "" ]]
then
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
if [[ "x$FEEDER_LAT" == "x" ]] || [[ "$FEEDER_LAT" == "90.12345" ]]
then
		sleep 10s
		echo "[$APPNAME][$(date)] ----------------------------------------------------------"
		echo "[$APPNAME][$(date)] !!! STOP !!!! You haven't configured FEEDER_LON and/or FEEDER_LAT for PlaneFence !!!!"
		echo "[$APPNAME][$(date)] Planefence will not run unless you edit it configuration."
		echo "[$APPNAME][$(date)] You can do this by pressing CTRL-c now and typing:"
		echo "[$APPNAME][$(date)] sudo nano -l ~/.planefence/planefence.config"
		echo "[$APPNAME][$(date)] Once done, restart the container and this message should disappear."
		echo "[$APPNAME][$(date)] ----------------------------------------------------------"
		while true
		do
				sleep 99999
		done
fi

#
# Set logging in planefence.conf:
#
if [[ "$PF_LOG" == "off" ]]
then
	export LOGFILE=/dev/null
	sed -i 's/\(^\s*VERBOSE=\).*/\1'""'/' /usr/share/planefence/planefence.conf
else
	[[ "x$PF_LOG" == "x" ]] && export LOGFILE="/tmp/planefence.log" || export LOGFILE="$PF_LOG"
fi
# echo pflog=$PF_LOG and logfile=$LOGFILE
sed -i 's|\(^\s*LOGFILE=\).*|\1'"$LOGFILE"'|' /usr/share/planefence/planefence.conf
#
# -----------------------------------------------------------------------------------
#
# read the environment variables and put them in the planefence.conf file:
[[ "x$FEEDER_LAT" != "x" ]] && sed -i 's/\(^\s*LAT=\).*/\1'"\"$FEEDER_LAT\""'/' /usr/share/planefence/planefence.conf || { echo "[$APPNAME][$(date)] Error - \$FEEDER_LAT ($FEEDER_LAT) not defined"; while :; do sleep 2073600; done; }
[[ "x$FEEDER_LONG" != "x" ]] && sed -i 's/\(^\s*LON=\).*/\1'"\"$FEEDER_LONG\""'/' /usr/share/planefence/planefence.conf || { echo "[$APPNAME][$(date)] Error - \$FEEDER_LONG not defined"; while :; do sleep 2073600; done; }
[[ "x$PF_MAXALT" != "x" ]] && sed -i 's/\(^\s*MAXALT=\).*/\1'"\"$PF_MAXALT\""'/' /usr/share/planefence/planefence.conf
[[ "x$PF_MAXDIST" != "x" ]] && sed -i 's/\(^\s*DIST=\).*/\1'"\"$PF_MAXDIST\""'/' /usr/share/planefence/planefence.conf
[[ "x$PF_ELEVATION" != "x" ]] && sed -i 's/\(^\s*ALTCORR=\).*/\1'"\"$PF_ELEVATION\""'/' /usr/share/planefence/planefence.conf
[[ "x$PF_NAME" != "x" ]] && sed -i 's/\(^\s*MY=\).*/\1'"\"$PF_NAME\""'/' /usr/share/planefence/planefence.conf || sed -i 's/\(^\s*MY=\).*/\1\"My\"/' /usr/share/planefence/planefence.conf
[[ "x$PF_TRACKSVC" != "x" ]] && sed -i 's|\(^\s*TRACKSERVICE=\).*|\1'"\"$PF_TRACKSVC\""'|' /usr/share/planefence/planefence.conf
[[ "x$PF_MAPURL" != "x" ]] && sed -i 's|\(^\s*MYURL=\).*|\1'"\"$PF_MAPURL\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*MYURL=\).*|\1|' /usr/share/planefence/planefence.conf
[[ "x$PF_NOISECAPT" != "x" ]] && sed -i 's|\(^\s*REMOTENOISE=\).*|\1'"\"$PF_NOISECAPT\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*REMOTENOISE=\).*|\1|' /usr/share/planefence/planefence.conf
[[ "x$PF_FUDGELOC" != "x" ]] && sed -i 's|\(^\s*FUDGELOC=\).*|\1'"\"$PF_FUDGELOC\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*FUDGELOC=\).*|\1|' /usr/share/planefence/planefence.conf
[[ "$PF_OPENAIP_LAYER" == "ON" ]] && sed -i 's|\(^\s*OPENAIP_LAYER=\).*|\1'"\"ON\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*OPENAIP_LAYER=\).*|\1'"\"OFF\""'|' /usr/share/planefence/planefence.conf
[[ "x$PF_TWEET_MINTIME" != "x" ]] && sed -i 's|\(^\s*TWEET_MINTIME=\).*|\1'"$PF_TWEET_MINTIME"'|' /usr/share/planefence/planefence.conf
[[ "$PF_TWEET_BEHAVIOR" == "PRE" ]] && sed -i 's|\(^\s*TWEET_BEHAVIOR=\).*|\1PRE|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*TWEET_BEHAVIOR=\).*|\1POST|' /usr/share/planefence/planefence.conf
[[ "$PF_PLANEALERT" == "ON" ]] && sed -i 's|\(^\s*PA_LINK=\).*|\1\"'"$PF_PA_LINK"'\"|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*PA_LINK=\).*|\1|' /usr/share/planefence/planefence.conf
[[ "$PF_TWEETEVERY" == "true" ]] && sed -i 's|\(^\s*TWEETEVERY=\).*|\1true|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*TWEETEVERY=\).*|\1false|' /usr/share/planefence/planefence.conf
[[ "x$PA_HISTTIME" != "x" ]] && sed -i 's|\(^\s*HISTTIME=\).*|\1\"'"$PA_HISTTIME"'\"|' /usr/share/plane-alert/plane-alert.conf
[[ "x$PF_ALERTHEADER" != "x" ]] && sed -i "s|\(^\s*ALERTHEADER=\).*|\1\'$PF_ALERTHEADER\'|" /usr/share/plane-alert/plane-alert.conf



if [[ "x$PF_SOCK30003HOST" != "x" ]]
then
	a=$(sed 's|\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)|\1\_\2\_\3\_\4|g' <<< "$PF_SOCK30003HOST")
	sed -i 's|\(^\s*LOGFILEBASE=/run/socket30003/dump1090-\).*|\1'"$a"'-|' /usr/share/planefence/planefence.conf
	sed -i 's/127_0_0_1/'"$a"'/' /usr/share/planefence/planeheat.sh
	unset a
else
	sleep 10s
	echo "[$APPNAME][$(date)] ----------------------------------------------------------"
	echo "[$APPNAME][$(date)] !!! STOP !!!! You haven't configured PF_SOCK30003HOST for PlaneFence !!!!"
	echo "[$APPNAME][$(date)] Planefence will not run unless you edit it configuration."
	echo "[$APPNAME][$(date)] You can do this by pressing CTRL-c now and typing:"
	echo "[$APPNAME][$(date)] sudo nano -l ~/.planefence/planefence.config"
	echo "[$APPNAME][$(date)] Once done, restart the container and this message should disappear."
	echo "[$APPNAME][$(date)] ----------------------------------------------------------"
	while true
	do
			sleep 99999
	done
fi
#
# Deal with duplicates. Put IGNOREDUPES in its place and create (or delete) the link to the ignorelist:
[[ "x$PF_IGNOREDUPES" != "x" ]] && sed -i 's|\(^\s*IGNOREDUPES=\).*|\1ON|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*IGNOREDUPES=\).*|\1OFF|' /usr/share/planefence/planefence.conf
[[ "x$PF_COLLAPSEWITHIN" != "x" ]] && sed -i 's|\(^\s*COLLAPSEWITHIN=\).*|\1'"$PF_COLLAPSEWITHIN"'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*IGNOREDUPES=\).*|\1300|' /usr/share/planefence/planefence.conf
a=$(sed -n 's/^\s*IGNORELIST=\(.*\)/\1/p' /usr/share/planefence/planefence.conf  | sed 's/\"//g')
[[ "$a" != "" ]] && ln -sf $a /usr/share/planefence/html/ignorelist.txt || rm -f /usr/share/planefence/html/ignorelist.txt
unset a
#
# -----------------------------------------------------------------------------------
#
# same for planeheat.sh
#
sed -i 's/\(^\s*LAT=\).*/\1'"\"$FEEDER_LAT\""'/' /usr/share/planefence/planeheat.sh
sed -i 's/\(^\s*LON=\).*/\1'"\"$FEEDER_LONG\""'/' /usr/share/planefence/planeheat.sh
[[ "x$PF_MAXALT" != "x" ]] && sed -i 's/\(^\s*MAXALT=\).*/\1'"\"$PF_MAXALT\""'/' /usr/share/planefence/planeheat.sh
[[ "x$PF_MAXDIST" != "x" ]] && sed -i 's/\(^\s*DIST=\).*/\1'"\"$PF_MAXDIST\""'/' /usr/share/planefence/planeheat.sh
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
[[ "x$PF_TWEET" == "xOFF" ]] && sed -i 's/\(^\s*PLANETWEET=\).*/\1/' /usr/share/planefence/planefence.conf
if [[ "x$PF_TWEET" == "xON" ]]
then
	if [[ ! -f ~/.twurlrc ]]
	then
			echo "[$APPNAME][$(date)] Warning: PF_TWEET is set to ON in .env file, but the Twitter account is not configured."
			echo "[$APPNAME][$(date)] Sign up for a developer account at Twitter, create an app, and get a Consumer Key / Secret."
			echo "[$APPNAME][$(date)] Then run this from the host machine: \"docker exec -it planefence /root/config_tweeting.sh\""
			echo "[$APPNAME][$(date)] For more information on how to sign up for a Twitter Developer Account, see this link:"
			echo "[$APPNAME][$(date)] https://elfsight.com/blog/2020/03/how-to-get-twitter-api-key/"
			echo "[$APPNAME][$(date)] PlaneFence will continue to start without Twitter functionality."
			sed -i 's/\(^\s*PLANETWEET=\).*/\1/' /usr/share/planefence/planefence.conf
	else
			sed -i 's|\(^\s*PLANETWEET=\).*|\1'"$(sed -n '/profiles:/{n;p;}' /root/.twurlrc | tr -d '[:blank:][=:=]')"'|' /usr/share/planefence/planefence.conf
            [[ "x$PF_TWATTRIB" != "x" ]] && sed -i 's|\(^\s*ATTRIB=\).*|\1'"\"$PF_TWATTRIB\""'|' /usr/share/planefence/planefence.conf
        fi
fi
# -----------------------------------------------------------------------------------
#
# enable or disable discord:
#
[[ "x$PF_DISCORD" == "xOFF" ]] && sed -i 's/\(^\s*PF_DISCORD=\).*/\1/' /usr/share/planefence/planefence.conf
if [[ "$PF_DISCORD" == "ON" ]]
then
	sed -i 's/\(^\s*PF_DISCORD=\).*/\1ON/' /usr/share/planefence/planefence.conf
	[[ "x$PF_DISCORD_WEBHOOKS" != "x" ]] && sed -i "s~\(^\s*PF_DISCORD_WEBHOOKS=\).*~\1${PF_DISCORD_WEBHOOKS}~" /usr/share/planefence/planefence.conf
fi
[[ "$PF_DISCORD" != "ON" ]] && sed -i 's|\(^\s*PF_DISCORD=\).*|\1OFF|' /usr/share/plane-alert/plane-alert.conf
# -----------------------------------------------------------------------------------
#
# Change the heatmap height and width if they are defined in the .env parameter file:
[[ "x$PF_MAPHEIGHT" != "x" ]] && sed -i 's|\(^\s*HEATMAPHEIGHT=\).*|\1'"\"$PF_MAPHEIGHT\""'|' /usr/share/planefence/planefence.conf
[[ "x$PF_MAPWIDTH" != "x" ]] && sed -i 's|\(^\s*HEATMAPWIDTH=\).*|\1'"\"$PF_MAPWIDTH\""'|' /usr/share/planefence/planefence.conf
[[ "x$PF_MAPZOOM" != "x" ]] && sed -i 's|\(^\s*HEATMAPZOOM=\).*|\1'"\"$PF_MAPZOOM\""'|' /usr/share/planefence/planefence.conf
#
# Also do this for files in the past -- /usr/share/planefence/html/planefence-??????.html
if find /usr/share/planefence/html/planefence-??????.html >/dev/null 2>&1
then
	for i in /usr/share/planefence/html/planefence-??????.html
	do
		[[ "x$PF_MAPWIDTH" != "x" ]] && sed  -i 's|\(^\s*<div id=\"map\" style=\"width:.*;\)|<div id=\"map\" style=\"width:'"$PF_MAPWIDTH"';|' $i
		[[ "x$PF_MAPHEIGHT" != "x" ]] && sed -i 's|\(; height:[^\"]*\)|; height: '"$PF_MAPHEIGHT"'\"|' $i
		[[ "x$PF_MAPZOOM" != "x" ]] && sed -i 's|\(^\s*var map =.*], \)\(.*\)|\1'"$PF_MAPZOOM"');|' $i
	done
fi

# place the screenshotting URL in place:

if [[ "x$PF_SCREENSHOTURL" != "x" ]]
then
	sed -i 's|\(^\s*SCREENSHOTURL=\).*|\1'"\"$PF_SCREENSHOTURL\""'|' /usr/share/planefence/planefence.conf
	sed -i 's|\(^\s*SCREENSHOTURL=\).*|\1'"\"$PF_SCREENSHOTURL\""'|' /usr/share/plane-alert/plane-alert.conf
fi
if [[ "x$PF_SCREENSHOT_TIMEOUT" != "x" ]]
then
	sed -i 's|\(^\s*SCREENSHOT_TIMEOUT=\).*|\1'"\"$PF_SCREENSHOT_TIMEOUT\""'|' /usr/share/planefence/planefence.conf
	sed -i 's|\(^\s*SCREENSHOT_TIMEOUT=\).*|\1'"\"$PF_SCREENSHOT_TIMEOUT\""'|' /usr/share/plane-alert/plane-alert.conf
fi

# if it still doesn't exist, something went drastically wrong and we need to set $PF_PLANEALERT to OFF!
if [[ ! -f /usr/share/planefence/persist/plane-alert-db.txt ]] && [[ "$PF_PLANEALERT" == "ON" ]]
then
		echo "[$APPNAME][$(date)] Cannot find or create the plane-alert-db.txt file. Disabling Plane-Alert."
		echo "[$APPNAME][$(date)] Do this on the host to get a base file:"
		echo "[$APPNAME][$(date)] curl --compressed -s https://raw.githubusercontent.com/kx1t/docker-planefence/plane-alert/plane-alert-db.txt >~/.planefence/plane-alert-db.txt"
		echo "[$APPNAME][$(date)] and then restart this docker container"
		PF_PLANEALERT="OFF"
fi

# make sure $PLANEALERT is set to ON in the planefence.conf file, so it will be invoked:
[[ "$PF_PLANEALERT" == "ON" ]] && sed -i 's|\(^\s*PLANEALERT=\).*|\1'"\"ON\""'|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*PLANEALERT=\).*|\1'"\"OFF\""'|' /usr/share/planefence/planefence.conf
# Go get the plane-alert-db files:
/usr/share/plane-alert/get-pa-alertlist.sh
/usr/share/plane-alert/get-silhouettes.sh

# Now make sure that the file containing the twitter IDs is rewritten with 1 ID per line
[[ "x$PF_PA_TWID" != "x" ]] && tr , "\n" <<< "$PF_PA_TWID" > /usr/share/plane-alert/plane-alert.twitterid || rm -f /usr/share/plane-alert/plane-alert.twitterid
# and write the rest of the parameters into their place
[[ "x$PF_PA_TWID" != "x" ]] && [[ "$PF_PA_TWEET" == "DM" ]] && sed -i 's|\(^\s*TWITTER=\).*|\1DM|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*TWITTER=\).*|\1false|' /usr/share/plane-alert/plane-alert.conf
[[ "$PF_PA_TWEET" == "TWEET" ]] && sed -i 's|\(^\s*TWITTER=\).*|\1TWEET|' /usr/share/plane-alert/plane-alert.conf
[[ "$PF_PA_TWEET" != "TWEET" ]] && [[ "$PF_PA_TWEET" != "DM" ]] && sed -i 's|\(^\s*TWITTER=\).*|\1false|' /usr/share/plane-alert/plane-alert.conf
[[ "$PA_DISCORD" == "ON" ]] && sed -i 's|\(^\s*PA_DISCORD=\).*|\1true|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*PA_DISCORD=\).*|\1false|' /usr/share/plane-alert/plane-alert.conf
[[ "$PA_DISCORD" == "ON" ]] && sed -i 's|\(^\s*PA_DISCORD=\).*|\1true|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*PA_DISCORD=\).*|\1false|' /usr/share/planefence/planefence.conf
[[ "$PF_DISCORD" == "ON" ]] && sed -i 's|\(^\s*PF_DISCORD=\).*|\1true|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*PF_DISCORD=\).*|\1false|' /usr/share/planefence/planefence.conf
[[ "x$PA_DISCORD_WEBHOOKS" != "x" ]] && sed -i "s~\(^\s*PA_DISCORD_WEBHOOKS=\).*~\1${PA_DISCORD_WEBHOOKS}~" /usr/share/plane-alert/plane-alert.conf
[[ "x$PA_DISCORD_WEBHOOKS" != "x" ]] && sed -i "s~\(^\s*PA_DISCORD_WEBHOOKS=\).*~\1${PA_DISCORD_WEBHOOKS}~" /usr/share/planefence/planefence.conf
[[ "x$PF_DISCORD_WEBHOOKS" != "x" ]] && sed -i "s~\(^\s*PF_DISCORD_WEBHOOKS=\).*~\1${PF_DISCORD_WEBHOOKS}~" /usr/share/planefence/planefence.conf
[[ "x$DISCORD_FEEDER_NAME" != "x" ]] && sed -i "s|\(^\s*DISCORD_FEEDER_NAME=\).*|\1\"${DISCORD_FEEDER_NAME}\"|" /usr/share/planefence/planefence.conf
[[ "x$DISCORD_FEEDER_NAME" != "x" ]] && sed -i "s|\(^\s*DISCORD_FEEDER_NAME=\).*|\1\"${DISCORD_FEEDER_NAME}\"|" /usr/share/plane-alert/plane-alert.conf
[[ "x$DISCORD_MEDIA" != "x" ]] && sed -i "s~\(^\s*DISCORD_MEDIA=\).*~\1${DISCORD_MEDIA}~" /usr/share/plane-alert/plane-alert.conf
[[ "x$DISCORD_MEDIA" != "x" ]] && sed -i "s~\(^\s*DISCORD_MEDIA=\).*~\1${DISCORD_MEDIA}~" /usr/share/planefence/planefence.conf
[[ "x$PF_NAME" != "x" ]] && sed -i 's|\(^\s*NAME=\).*|\1'"\"$PF_NAME\""'|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*NAME=\).*|\1My|' /usr/share/plane-alert/plane-alert.conf
[[ "x$PF_MAPURL" != "x" ]] && sed -i 's|\(^\s*ADSBLINK=\).*|\1'"\"$PF_MAPURL\""'|' /usr/share/plane-alert/plane-alert.conf
# removed for now - hardcoding PlaneAlert map zoom to 7 in plane-alert.conf: [[ "x$PF_MAPZOOM" != "x" ]] && sed -i 's|\(^\s*MAPZOOM=\).*|\1'"\"$PF_MAPZOOM\""'|' /usr/share/plane-alert/plane-alert.conf
[[ "x$PF_PARANGE" != "x" ]] && sed -i 's|\(^\s*RANGE=\).*|\1'"$PF_PARANGE"'|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*RANGE=\).*|\1999999|' /usr/share/plane-alert/plane-alert.conf
[[ "x$PF_PA_SQUAWKS" != "x" ]] && sed -i 's|\(^\s*SQUAWKS=\).*|\1'"$PF_PA_SQUAWKS"'|' /usr/share/plane-alert/plane-alert.conf || sed -i 's|\(^\s*SQUAWKS=\).*|\1|' /usr/share/plane-alert/plane-alert.conf

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
	|| [[ "$PF_SPEEDUNIT" != $(sed -n 's/^\s*speedunit=\(.*\)/\1/p' /usr/share/socket30003/socket30003.cfg) ]]
then
	[[ "x$PF_DISTUNIT" != "x" ]] &&	sed -i 's/\(^\s*distanceunit=\).*/\1'"$PF_DISTUNIT"'/' /usr/share/socket30003/socket30003.cfg
	[[ "x$PF_SPEEDUNIT" != "x" ]] && sed -i 's/\(^\s*speedunit=\).*/\1'"$PF_SPEEDUNIT"'/' /usr/share/socket30003/socket30003.cfg
	[[ "x$PF_ALTUNIT" != "x" ]] && sed -i 's/\(^\s*altitudeunit=\).*/\1'"$PF_ALTUNIT"'/' /usr/share/socket30003/socket30003.cfg
fi
#
#--------------------------------------------------------------------------------
# Check if the remote airlinename server is online
#[[ "$PF_CHECKREMOTEDB" != "OFF" ]] && a="$(curl -L -s https://get-airline.planefence.com/?flight=hello_from_$(grep 'PF_NAME' /usr/share/planefence/persist/planefence.config | awk -F '=' '{ print $2 }' | tr -dc '[:alnum:]')_bld_$([[ -f /usr/share/planefence/build ]] && cat /usr/share/planefence/build || cat /root/.buildtime | cut -c 1-23 | tr ' ' '_'))" || a=""
[[ "$PF_CHECKREMOTEDB" != "OFF" ]] && a="$(curl -L -s $REMOTEURL/?flight=hello_from_$(grep 'PF_NAME' /usr/share/planefence/persist/planefence.config | awk -F '=' '{ print $2 }' | tr -dc '[:alnum:]')_bld_$([[ -f /usr/share/planefence/branch ]] && cat /usr/share/planefence/branch || cat /root/.buildtime))" || a=""

[[ "${a:0:4}" == "#100" ]] && sed -i 's|\(^\s*CHECKREMOTEDB=\).*|\1ON|' /usr/share/planefence/planefence.conf || sed -i 's|\(^\s*CHECKREMOTEDB=\).*|\1OFF|' /usr/share/planefence/planefence.conf
#
#--------------------------------------------------------------------------------
# Move web page background pictures in place
[[ -f /usr/share/planefence/persist/pf_background.jpg ]] && cp -f /usr/share/planefence/persist/pf_background.jpg /usr/share/planefence/html || rm -f /usr/share/planefence/html/pf_background.jpg
[[ -f /usr/share/planefence/persist/pa_background.jpg ]] && cp -f /usr/share/planefence/persist/pa_background.jpg /usr/share/planefence/html/plane-alert || rm -f /usr/share/planefence/html/plane-alert/pa_background.jpg

#--------------------------------------------------------------------------------
# Last thing - save the date we processed the config to disk. That way, if ~/.planefence/planefence.conf is changed,
# we know that we need to re-run this prep routine!
date +%s > /run/planefence/last-config-change
