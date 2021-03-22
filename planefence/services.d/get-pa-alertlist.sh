#!/usr/bin/with-contenv bash
#shellcheck shell=bash

APPNAME="$(hostname)/get-pa-alertlist"
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
echo "[$APPNAME][$(date)] get-pa-alertlist.sh started"
#Get the list of alert files into ALERTLIST, or put the original file in it
ALERTLIST="$(sed -n 's|^\s*ALERTLIST=\(.*\)|\1|p' /usr/share/plane-alert/plane-alert.conf)"
[[ "$ALERTLIST" != "" ]] && IFS="," read -ra ALERTFILES <<< "$ALERTLIST" || ALERTFILES=("plane-alert-db.txt")

# now iterate though them an put them in sequential files:
rm -f /tmp/alertlist*.txt
for ((i=0; i<"${#ALERTFILES[@]}"; i++))
do
	if [[ "${ALERTFILES[i]:0:5}" == "http:" ]] || [[ "${ALERTFILES[i]:0:6}" == "https:" ]]
	then
		# it's a URL and we need to CURL it
		[[ "$(curl -L -s -fail -o /tmp/alertlist-$i.txt "${ALERTFILES[i]}" ; echo $?)" == "0" ]] && echo "[$APPNAME][$(date)] ALERTLIST ${ALERTFILES[i]} retrieval succeeded" || echo "[$APPNAME][$(date)] ALERTLIST ${ALERTFILES[i]} retrieval failed"
	else
		# it's a file and we need to concatenate it
		if [[ -f "/usr/share/planefence/${ALERTFILES[i]}" ]]
		then
			cp -f "/usr/share/planefence/${ALERTFILES[i]}" /tmp/alertlist-$i.txt
			echo "[$APPNAME][$(date)] ALERTLIST ${ALERTFILES[i]} retrieval succeeded"
		else
			echo "[$APPNAME][$(date)] ALERTLIST ${ALERTFILES[i]} retrieval failed"
		fi
	fi
done

cat /tmp/alertlist*.txt >/usr/share/planefence/persist/.internal/plane-alert-db.txt
rm -f /tmp/alertlist*.txt
