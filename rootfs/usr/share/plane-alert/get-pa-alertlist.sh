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
if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "get-pa-alertlist.sh started"; fi
#Get the list of alert files into ALERTLIST, or put the original file in it
ALERTLIST="$(sed -n 's|^\s*PF_ALERTLIST=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
if [[ -z "$ALERTLIST" ]]; then IFS="," read -ra ALERTFILES <<< "$ALERTLIST" || ALERTFILES=("plane-alert-db.txt"); fi

# now iterate though them an put them in sequential files:
rm -f /tmp/alertlist*.txt
i=0
inhibit_update="false"
for ALERT in "${ALERTFILES[@]}"
do
	if [[ "${ALERT:0:5}" == "http:" ]] || [[ "${ALERT:0:6}" == "https:" ]]
	then
		# it's a URL and we need to CURL it
		if curl --compressed -L -s --fail -o /tmp/alertlist-$i.txt "$ALERT"
		then
			if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "ALERTLIST $ALERT ($i) retrieval succeeded"; fi
			((i++))
		else
			"${s6wrap[@]}" echo "ALERTLIST $ALERT retrieval failed"
			inhibit_update="true"
		fi
	else
		# it's a file and we need to concatenate it
		if [[ -f "/usr/share/planefence/persist/$ALERT" ]]
		then
			cp -f "/usr/share/planefence/persist/$ALERT" /tmp/alertlist-$i.txt
			if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "ALERTLIST $ALERT ($i) retrieval succeeded"; fi
			((i++))
		else
			"${s6wrap[@]}" echo "ALERTLIST $ALERT retrieval failed"
		fi
	fi
done

if [[ $inhibit_update == "false" ]]; then
	touch /usr/share/planefence/persist/.internal/plane-alert-db.txt
	cat /tmp/alertlist*.txt |  tr -dc "[:alnum:][:blank:]+':/?&=%#\$\\\[\].,\{\};\-_\n" | awk -F',' '!seen[$1]++'  >/usr/share/planefence/persist/.internal/plane-alert-db.txt 2>/dev/null
	EXCLUDE="$(sed -n 's|^\s*PA_EXCLUSIONS=\(.*\)|\1|p' /usr/share/planefence/persist/planefence.config)"
	if [[ -n "$EXCLUDE" ]]; then IFS="," read -ra EXCLUSIONS <<< "$EXCLUDE"; fi
	count_start="$(wc -l < /usr/share/planefence/persist/.internal/plane-alert-db.txt)"
	for TYPE in "${EXCLUSIONS[@]}"
	do
		if (("${#TYPE} >= 3")) && (("${#TYPE} <= 4"))
		then
			echo "$TYPE appears to be an ICAO type and is valid, entries excluded:" "$(grep -ci "$TYPE" /usr/share/planefence/persist/.internal/plane-alert-db.txt)"
			sed -i "/,$TYPE,/Id" /usr/share/planefence/persist/.internal/plane-alert-db.txt
		elif [[ "$TYPE" =~ ^[0-9a-fA-F]{6}$ ]]
		then
			echo "$TYPE appears to be an ICAO hex and is valid, entries excluded:" "$(grep -ci "$TYPE" /usr/share/planefence/persist/.internal/plane-alert-db.txt)"
			sed -r -i "/^$TYPE,/Id" /usr/share/planefence/persist/.internal/plane-alert-db.txt
		elif [[ -n "$TYPE" ]]
		then
			echo "$TYPE appears to be a freeform search pattern, entries excluded:" "$(grep -ci "$TYPE" /usr/share/planefence/persist/.internal/plane-alert-db.txt)"
			# shellcheck disable=SC1087
			sed -r -i "/,[A-Za-z0-9\-\.\+ ]*$TYPE[A-Za-z0-9\-\.\+ ]*,/Id" /usr/share/planefence/persist/.internal/plane-alert-db.txt
		else
			echo "$TYPE is invalid, skipping!"
		fi
	done
	count_end="$(wc -l < /usr/share/planefence/persist/.internal/plane-alert-db.txt)"
	if (( count_start - count_end > 0 )); then  
		echo "$(( count_start -  count_end )) entries excluded."
		chmod a+r /usr/share/planefence/persist/.internal/plane-alert-db.txt
	fi
	ln -sf /usr/share/planefence/persist/.internal/plane-alert-db.txt /usr/share/planefence/html/plane-alert/alertlist.txt
else
	"${s6wrap[@]}" echo "At least one http retrieval failed, using old list!"
fi

rm -f /tmp/alertlist*.txt
if [[ "$LOGLEVEL" != "ERROR" ]]; then "${s6wrap[@]}" echo "get-pa-alertlist.sh finished"; fi
