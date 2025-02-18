#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154

source /scripts/common
# -----------------------------------------------------------------------------------
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence4docker/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
#
# Make sure the /run directory exists
if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "get-silhouettes.sh started"; fi
# Get the link to the silhouettes file, or add the default if empty.
# it it's set to OFF, then don't do any
LINK="$(sed -n 's|^\s*PA_SILHOUETTES_LINK=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
if [[ "$LINK" == "" ]]; then LINK="https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip"; fi
if [[ "${LINK^^}" == "OFF" ]]; then inhibit_update="true"; else inhibit_update="false"; fi

# Get the latest silhouettes. If the CURL action fails for any reason, fall back to the file that was included with the build
if [[ "$inhibit_update" == "false" ]]
then
	if ! curl --compressed -s -L -o /tmp/silhouettes.zip "$LINK"
	then
		"${s6wrap[@]}" echo "Retrieval of silhouettes from $LINK failed, using the existing list."
		"${s6wrap[@]}" echo "To fix, in planefence.config, please set PF_SILHOUETTES_LINK to OFF or to the correct retrieval URL."
		cp -f /tmp/silhouettes-org.zip /tmp/silhouettes.zip
	else
		if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "Got $LINK"; fi
	fi
else
	if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "Retrieval of silhouettes is disabled, using the existing list."; fi
fi

# Unzip files to the target directory
mkdir -p /usr/share/planefence/html/plane-alert/silhouettes # probably not necessary, but making sure the dir exists "just in case"
if ! unzip -qq -o -d /usr/share/planefence/html/plane-alert/silhouettes /tmp/silhouettes.zip
then
	"${s6wrap[@]}" echo "Unzipping of silhouettes from $LINK failed. Could the URL source be corrupt? Using the existing list."
else
	if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "Unzipped silhouettes to /usr/share/planefence/html/plane-alert/silhouettes"; fi
fi

rm -f /tmp/silhouettes.zip
if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "get-silhouettes.sh finished"; fi
