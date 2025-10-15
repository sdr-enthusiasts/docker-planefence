#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154

source /scripts/pf-common
# -----------------------------------------------------------------------------------
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence4docker/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------
#

SILHOUETTES_DIR=/usr/share/planefence/html/assets/silhouettes

log_print INFO "get-silhouettes.sh started"

# Get the link to the silhouettes file, or add the default if empty.
# it it's set to OFF, then don't do any
LINK="$(sed -n 's|^\s*PA_SILHOUETTES_LINK=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
LINK="${LINK:-https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip}"
if chk_disabled "${LINK}"; then inhibit_update=true; else inhibit_update=false; fi

# Get the latest silhouettes. If the CURL action fails for any reason, fall back to the file that was included with the build
if [[ "$inhibit_update" == false ]]
then
	if ! curl --compressed -sSL "$LINK" > /tmp/silhouettes.zip
	then
		log_print ERR "Retrieval of silhouettes from $LINK failed, using the existing list."
		log_print ERR "To fix, in planefence.config, please set PF_SILHOUETTES_LINK to OFF or to the correct retrieval URL."
		if [[ -f /tmp/silhouettes-org.zip ]]; then 
			cp -f /tmp/silhouettes-org.zip /tmp/silhouettes.zip
		else
			log_print ERR "No original silhouettes file found either, silhouettes will not be updated."
			exit
		fi
	else
		log_print DEBUG "Got $LINK"
	fi
else
	log_print INFO "Retrieval of silhouettes is disabled, using the existing list."
fi

# Unzip files to the target directory
# shellcheck disable=SC2174
mkdir -p -m 0777 "$SILHOUETTES_DIR" # probably not necessary, but making sure the dir exists "just in case"
if ! unzip -qq -o -d "$SILHOUETTES_DIR" /tmp/silhouettes.zip
then
	log_print ERR "Unzipping of silhouettes from $LINK failed. Could the URL source be corrupt? Using the existing list."
else
	log_print DEBUG "Unzipped silhouettes to $SILHOUETTES_DIR"
fi

rm -f /tmp/silhouettes.zip
log_print INFO "get-silhouettes.sh finished"
