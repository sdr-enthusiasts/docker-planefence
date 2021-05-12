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
[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] get-pa-alertlist.sh started"
#Get the list of alert files into ALERTLIST, or put the original file in it
ALERTLIST="$(sed -n 's|^\s*PF_ALERTLIST=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
[[ "$ALERTLIST" != "" ]] && IFS="," read -ra ALERTFILES <<< "$ALERTLIST" || ALERTFILES=("plane-alert-db.txt")

# now iterate though them an put them in sequential files:
rm -f /tmp/alertlist*.txt
i=0
for ALERT in "${ALERTFILES[@]}"
do
	if [[ "${ALERT:0:5}" == "http:" ]] || [[ "${ALERT:0:6}" == "https:" ]]
	then
		# it's a URL and we need to CURL it
		if [[ "$(curl -L -s --fail -o /tmp/alertlist-$i.txt "$ALERT" ; echo $?)" == "0" ]]
		then
			[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] ALERTLIST $ALERT ($i) retrieval succeeded"
			((i++))
		else
			echo "[$APPNAME][$(date)] ALERTLIST $ALERT retrieval failed"
		fi
	else
		# it's a file and we need to concatenate it
		if [[ -f "/usr/share/planefence/persist/$ALERT" ]]
		then
			cp -f "/usr/share/planefence/persist/$ALERT" /tmp/alertlist-$i.txt
			[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] ALERTLIST $ALERT ($i) retrieval succeeded"
			((i++))
		else
			echo "[$APPNAME][$(date)] ALERTLIST $ALERT retrieval failed"
		fi
	fi
done

touch /usr/share/planefence/persist/.internal/plane-alert-db.txt
cat /tmp/alertlist*.txt | tr -dc '[:print:]\n' | awk -F',' '!seen[$1]++'  >/usr/share/planefence/persist/.internal/plane-alert-db.txt 2>/dev/null
chmod a+r /usr/share/planefence/persist/.internal/plane-alert-db.txt
ln -sf /usr/share/planefence/persist/.internal/plane-alert-db.txt /usr/share/planefence/html/plane-alert/alertlist.txt

rm -f /tmp/alertlist*.txt
[[ "$LOGLEVEL" != "ERROR" ]] && echo "[$APPNAME][$(date)] get-pa-alertlist.sh finished"
