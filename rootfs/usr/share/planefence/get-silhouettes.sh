#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154,SC2174

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
OPFLAGS_DIR=/usr/share/planefence/html/assets/operatorflags

log_print INFO "get-silhouettes.sh started"

# Get the link to the silhouettes file, or add the default if empty.
# it it's set to OFF, then don't do any
SILLINK="$(sed -n 's|^\s*PA_SILHOUETTES_LINK=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
# SILLINK="${SILLINK:-https://github.com/rikgale/VRSOperatorFlags/raw/main/Silhouettes.zip}"
SILLINK="${SILLINK:-https://github.com/rikgale/VRSOperatorFlags/raw/main/TransparentDVSilhouettes.zip}"
OPFLINK="$(sed -n 's|^\s*PA_OPERATORFLAGS_LINK=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
OPFLINK="${OPFLINK:-https://github.com/rikgale/VRSOperatorFlags/raw/main/OperatorFlags.zip}"

if chk_disabled "${SILLINK}"; then inhibit_update=true; else inhibit_update=false; fi
# Get the latest silhouettes. If the CURL action fails for any reason, fall back to the file that was included with the build
if [[ "$inhibit_update" == false ]]
then
	if ! curl --compressed -sSL "$SILLINK" > /tmp/silhouettes.zip
	then
		log_print ERR "Retrieval of silhouettes from $SILLINK failed, using the existing list."
		log_print ERR "To fix, in planefence.config, please set PF_SILHOUETTES_LINK to OFF or to the correct retrieval URL."
		if [[ -f /tmp/silhouettes-org.zip ]]; then 
			cp -f /tmp/silhouettes-org.zip /tmp/silhouettes.zip
		else
			log_print ERR "No original silhouettes file found either, silhouettes will not be updated."
			exit
		fi
	else
		log_print DEBUG "Got $SILLINK"
	fi
else
	log_print INFO "Retrieval of silhouettes is disabled, using the existing list."
fi

if chk_disabled "${OPFLINK}"; then inhibit_update=true; else inhibit_update=false; fi
# Get the latest silhouettes. If the CURL action fails for any reason, fall back to the file that was included with the build
if [[ "$inhibit_update" == false ]]
then
	if ! curl --compressed -sSL "$OPFLINK" > /tmp/operatorflags.zip
	then
		log_print ERR "Retrieval of Operator Flags from $OPFLINK failed, using the existing list."
		log_print ERR "To fix, in planefence.config, please set PF_OPERATORFLAGS_LINK to OFF or to the correct retrieval URL."
		if [[ -f /tmp/operatorflags-org.zip ]]; then 
			cp -f /tmp/operatorflags-org.zip /tmp/operatorflags.zip
		else
			log_print ERR "No original operator flags file found either, operator flags will not be updated."
			exit
		fi
	else
		log_print DEBUG "Got $OPFLINK"
	fi
else
	log_print INFO "Retrieval of Operator Flags is disabled, using the existing list."
fi

# Unzip files to the target directory
mkdir -p -m 0777 "$SILHOUETTES_DIR" # probably not necessary, but making sure the dir exists "just in case"
if ! unzip -qq -o -d "$SILHOUETTES_DIR" /tmp/silhouettes.zip
then
	log_print ERR "Unzipping of silhouettes from $SILLINK failed. Could the URL source be corrupt? Using the existing list."
else
	log_print DEBUG "Unzipped silhouettes to $SILHOUETTES_DIR"
fi

mkdir -p -m 0777 "$OPFLAGS_DIR" # probably not necessary, but making sure the dir exists "just in case"
if ! unzip -qq -o -d "$OPFLAGS_DIR" /tmp/operatorflags.zip
then
	log_print ERR "Unzipping of operator flags from $OPFLINK failed. Could the URL source be corrupt? Using the existing list."
else
	# delete any bitmaps that aren't 3-letter airline codes to avoid clutter
	find "$OPFLAGS_DIR" -type f ! -name '[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9].bmp' -exec rm -f {} +
	log_print DEBUG "Unzipped operator flags to $OPFLAGS_DIR"
fi

rm -f /tmp/silhouettes.zip /tmp/operatorflags.zip
log_print INFO "get-silhouettes.sh finished"
