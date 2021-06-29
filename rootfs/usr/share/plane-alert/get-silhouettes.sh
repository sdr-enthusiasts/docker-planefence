#!/usr/bin/with-contenv bash
#shellcheck shell=bash

APPNAME="$(hostname)/get-silhouettes"
# -----------------------------------------------------------------------------------
# Copyright 2020, 2021 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence4docker/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
#
# Make sure the /run directory exists
[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] get-silhouettes.sh started" || true
# Get the link to the silhouettes file, or add the default if empty.
# it it's set to OFF, then don't do any
LINK="$(sed -n 's|^\s*PA_SILHOUETTES_LINK=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
[[ "$LINK" == "" ]] && LINK="https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip"
[[ "${LINK^^}" == "OFF" ]] && inhibit_update="true" || inhibit_update="false"

# Get the latest silhouettes. If the CURL action fails for any reason, fall back to the file that was included with the build
if [[ "$inhibit_update" == "false" ]]
then
	if ! curl --compressed -s -L -o /tmp/silhouettes.zip $LINK
	then
		echo "[$APPNAME][$(date)] Retrieval of silhouettes from $LINK failed, using the existing list."
		echo "[$APPNAME][$(date)] To fix, in planefence.config, please set PF_SILHOUETTES_LINK to OFF or to the correct retrieval URL."
		cp -f /tmp/silhouettes-org.zip /tmp/silhouettes.zip
	fi
else
	[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] Retrieval of silhouettes is disabled, using the existing list."
fi

# Unzip only the newer files to the target directory
mkdir -p /usr/share/planefence/html/silhouettes # probably not necessary, but making sure the dir exists "just in case"
if ! unzip -u -qq -o -d /usr/share/planefence/html/plane-alert/silhouettes /tmp/silhouettes.zip
then
	echo "[$APPNAME][$(date)] Unzipping of silhouettes from $LINK failed. Could the URL source be corrupt? Using the existing list."
fi

rm -f /tmp/silhouettes.zip
[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] get-silhouettes.sh finished" || true
