#!/command/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034,SC2154,SC2155
#
# #-----------------------------------------------------------------------------------
# PF-RUN.SH
# Do a Planefence Run
#
# Copyright 2020-2026 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
##
# Summary of License Terms
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see https://www.gnu.org/licenses/.
# -----------------------------------------------------------------------------------

source /scripts/pf-common

nicevalue="$(GET_PARAM base PF_PROCESS_NICE)"
PF_PROCESS_NICE="${PF_PROCESS_NICE:-${nicevalue:-10}}"

renice -n "$PF_PROCESS_NICE" -p $$ >/dev/null 2>&1 || true

PF_PATH="/usr/share/planefence"
PA_PATH="/usr/share/planefence"
NOTIFY_PATH="$PF_PATH/notifiers"
DELETEAFTER="10"  # minutes

TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/usr/share/planefence/persist/records}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"
BACKUPTIME=600  # seconds

# shellcheck disable=SC2174
mkdir -p -m 0750 /run/planefence

# -----------------------------------------------------------------------------------
#       SETTINGS STUFF
# -----------------------------------------------------------------------------------
set -eo pipefail
shopt -s nullglob

if [[ -f "$RECORDSFILE" ]]; then
  cp -n "$RECORDSFILE" "/run/planefence/"
fi
if [[ ! -f "/run/planefence/planefence-${TODAY}.json" && -f "/usr/share/planefence/html/planefence-${TODAY}.json" ]]; then
  cp -n "/usr/share/planefence/html/planefence-${TODAY}.json" "/run/planefence/planefence-${TODAY}.json"
fi

if [[ ! -f "/run/planefence/plane-alert-${TODAY}.json" && -f "/usr/share/planefence/html/plane-alert-${TODAY}.json" ]]; then
  cp -n "/usr/share/planefence/html/plane-alert-${TODAY}.json" "/run/planefence/plane-alert-${TODAY}.json"
fi

if [[ ! -f /tmp/.pf-lastrun ]] || (( $(date +%s) - $(stat -c %Y /tmp/.pf-lastrun) > BACKUPTIME )); then
  # Must back up the data files!
  backup_data_files=true
  touch /tmp/.pf-lastrun
else
  backup_data_files=false
fi

# -----------------------------------------------------------------------------------
#      RUN PLANEFENCE
# -----------------------------------------------------------------------------------

cd "$PF_PATH"

if [[ -f /run/planefence/last-config-change ]] && \
   (( $(</run/planefence/last-config-change) < $(stat -c %Z /usr/share/planefence/persist/planefence.config) )); then
  log_print INFO "Detected a change in the config file since last run. Applying config changes."
  /usr/share/planefence/prep-planefence.sh
  date +%s >/run/planefence/last-config-change
elif [[ -f /run/planefence/last-config-change ]] && [[ -f /usr/share/planefence/persist/plane-alert-candidates.txt ]] && \
   (( $(</run/planefence/last-config-change) < $(stat -c %Z /usr/share/planefence/persist/plane-alert-candidates.txt) )); then
  log_print INFO "Detected a change in the plane-alert-candidates file since last run. Applying config changes."
  /usr/share/planefence/get-pa-alertlist.sh
  date +%s >/run/planefence/last-config-change
fi

./pf-process_sbs.sh	&	# read and process SBS data
pid=$!
echo "$pid" > /run/pf-process_sbs.pid
wait "$pid" &>/dev/null || true
rm -f "/run/pf-process_sbs.pid" "/tmp/.records.lock"

# Remove noisecache
find /tmp -maxdepth 1 -mindepth 1 \
  \( -name '.pf-noisecache-*' -o -name 'tmp.*' -o -name 'pa_key_*' \) \
  -mmin +"${DELETEAFTER}" \
  -exec rm -rf -- {} + 2>/dev/null || :

# Run notifier scripts sequentially with timeout protection.
# Sequential execution avoids lock contention on /tmp/.records.lock between notifiers.
NOTIFIER_TIMEOUT="${NOTIFIER_TIMEOUT:-600}"  # default 10 minute timeout per notifier

if script_array="$(compgen -G "$NOTIFY_PATH/send*.sh" 2>/dev/null)"; then
  while read -r script; do
    [[ -n "$script" ]] || continue

    if ! timeout "$NOTIFIER_TIMEOUT" bash "$script"; then
      exitcode=$?
      if [[ $exitcode -eq 124 ]]; then
        log_print WARN "Notifier ${script##*/} timed out after ${NOTIFIER_TIMEOUT}s and was terminated"
      fi
    fi
  done <<< "$script_array"
fi

# Sync notifier results from records into runtime JSON so stream/UI can render links.
sync_notifier_links_into_json() {
  local mode="$1" json_file="$2"
  local max idx tmp_map tmp_json tmp_map_new
  local discord_link discord_notified bsky_link bsky_notified telegram_link telegram_notified mastodon_link mastodon_notified mqtt_notified

  [[ -f "$json_file" ]] || return 0

  tmp_map="$(mktemp)"
  printf '{}' > "$tmp_map"

  if [[ "$mode" == "pa" ]]; then
    max="${pa_records[maxindex]:--1}"
  else
    max="${records[maxindex]:--1}"
  fi

  if [[ "$max" =~ ^[0-9]+$ ]] && (( max >= 0 )); then
    for ((idx=0; idx<=max; idx++)); do
      if [[ "$mode" == "pa" ]]; then
        discord_link="${pa_records["$idx:discord:link"]}"
        discord_notified="${pa_records["$idx:discord:notified"]}"
        bsky_link="${pa_records["$idx:bsky:link"]}"
        bsky_notified="${pa_records["$idx:bsky:notified"]}"
        telegram_link="${pa_records["$idx:telegram:link"]}"
        telegram_notified="${pa_records["$idx:telegram:notified"]}"
        mastodon_link="${pa_records["$idx:mastodon:link"]}"
        mastodon_notified="${pa_records["$idx:mastodon:notified"]}"
        mqtt_notified="${pa_records["$idx:mqtt:notified"]}"
      else
        discord_link="${records["$idx:discord:link"]}"
        discord_notified="${records["$idx:discord:notified"]}"
        bsky_link="${records["$idx:bsky:link"]}"
        bsky_notified="${records["$idx:bsky:notified"]}"
        telegram_link="${records["$idx:telegram:link"]}"
        telegram_notified="${records["$idx:telegram:notified"]}"
        mastodon_link="${records["$idx:mastodon:link"]}"
        mastodon_notified="${records["$idx:mastodon:notified"]}"
        mqtt_notified="${records["$idx:mqtt:notified"]}"
      fi

      if [[ -n "$discord_link$discord_notified$bsky_link$bsky_notified$telegram_link$telegram_notified$mastodon_link$mastodon_notified$mqtt_notified" ]]; then
        tmp_map_new="$(mktemp)"
        jq \
          --arg idx "$idx" \
          --arg dlink "$discord_link" \
          --arg dnot "$discord_notified" \
          --arg blink "$bsky_link" \
          --arg bnot "$bsky_notified" \
          --arg tlink "$telegram_link" \
          --arg tnot "$telegram_notified" \
          --arg mlink "$mastodon_link" \
          --arg mnot "$mastodon_notified" \
          --arg qnot "$mqtt_notified" \
          '. + {($idx): {
            "discord:link": $dlink,
            "discord:notified": $dnot,
            "bsky:link": $blink,
            "bsky:notified": $bnot,
            "telegram:link": $tlink,
            "telegram:notified": $tnot,
            "mastodon:link": $mlink,
            "mastodon:notified": $mnot,
            "mqtt:notified": $qnot
          }}' \
          "$tmp_map" > "$tmp_map_new" && mv -f "$tmp_map_new" "$tmp_map"
      fi
    done
  fi

  tmp_json="$(mktemp)"
  if jq --slurpfile notify "$tmp_map" '
      map(
        if (type == "object" and (.index? != null)) then
          (.index|tostring) as $idx
          | if (($notify[0][$idx] // null) != null) then . + $notify[0][$idx] else . end
        else . end
      )
    ' "$json_file" > "$tmp_json"; then
    mv -f "$tmp_json" "$json_file"
  else
    log_print WARN "Unable to sync notifier links into $json_file"
    rm -f "$tmp_json"
  fi

  rm -f "$tmp_map"
}

LOCK_RECORDS
READ_RECORDS ignore-lock
sync_notifier_links_into_json pf "/run/planefence/planefence-${TODAY}.json"
sync_notifier_links_into_json pa "/run/planefence/plane-alert-${TODAY}.json"
UNLOCK_RECORDS

# Backup data files if needed
if [[ "$backup_data_files" == true ]]; then
  if [[ -f "/run/planefence/${RECORDSFILE##*/}" ]]; then  cp -f "/run/planefence/${RECORDSFILE##*/}" "$RECORDSDIR/"; fi
  if [[ -f "/run/planefence/planefence-${TODAY}.json" ]]; then  cp -f "/run/planefence/planefence-${TODAY}.json" "/usr/share/planefence/html/planefence-${TODAY}.json"; fi
  if [[ -f "/run/planefence/plane-alert-${TODAY}.json" ]]; then  cp -f "/run/planefence/plane-alert-${TODAY}.json" "/usr/share/planefence/html/plane-alert-${TODAY}.json"; fi
  if [[ -f "/run/planefence/planefence-${TODAY}.csv" ]]; then  cp -f "/run/planefence/planefence-${TODAY}.csv" "/usr/share/planefence/html/planefence-${TODAY}.csv"; fi
  if [[ -f "/run/planefence/plane-alert-${TODAY}.csv" ]]; then  cp -f "/run/planefence/plane-alert-${TODAY}.csv" "/usr/share/planefence/html/plane-alert-${TODAY}.csv"; fi
fi
