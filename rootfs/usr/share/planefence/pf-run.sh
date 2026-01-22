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

renice -n 10 -p $$ >/dev/null 2>&1 || true

source /scripts/pf-common

PF_PATH="/usr/share/planefence"
PA_PATH="/usr/share/planefence"
NOTIFY_PATH="$PF_PATH/notifiers"
DELETEAFTER="10"  # minutes

TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/usr/share/planefence/persist/records}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"
BACKUPTIME=600  # seconds

# shellcheck disable=SC2174
mkdir -p -m 0777 /run/planefence

# -----------------------------------------------------------------------------------
#       SETTINGS STUFF
# -----------------------------------------------------------------------------------
set -eo pipefail
shopt -s nullglob

cp -n "$RECORDSFILE" "/run/planefence/"
if [[ ! -f "/run/planefence/planefence.json" && -f "/usr/share/planefence/html/planefence-${TODAY}.json" ]]; then
  cp -n "/usr/share/planefence/html/planefence-${TODAY}.json" "/run/planefence/planefence.json"
fi

if [[ ! -f "/run/planefence/plane-alert.json" && -f "/usr/share/planefence/html/plane-alert-${TODAY}.json" ]]; then
  cp -n "/usr/share/planefence/html/plane-alert-${TODAY}.json" "/run/planefence/plane-alert.json"
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

if [[ -f /run/planefence/last-config-change ]] && (( $(</run/planefence/last-config-change) < $(stat -c %Z /usr/share/planefence/persist/planefence.config) )); then
  log_print INFO "Detected a change in the config file since last run. Applying config changes."
  /usr/share/planefence/prep-planefence.sh
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

# Run notifiers scripts in the background
if script_array="$(compgen -G "$NOTIFY_PATH/send*.sh" 2>/dev/null)"; then
  while read -r script; do
      bash "$script" || true &  
  done <<< "$script_array"
fi
wait # wait for all notifier background processes to finish

# Backup data files if needed
if [[ "$backup_data_files" == true ]]; then
  if [[ -f "/run/planefence/${RECORDSFILE##*/}" ]]; then  cp -f "/run/planefence/${RECORDSFILE##*/}" "$RECORDSDIR/"; fi
  if [[ -f "/run/planefence/planefence.json" ]]; then  cp -f "/run/planefence/planefence.json" "/usr/share/planefence/html/planefence-${TODAY}.json"; fi
  if [[ -f "/run/planefence/plane-alert.json" ]]; then  cp -f "/run/planefence/plane-alert.json" "/usr/share/planefence/html/plane-alert-${TODAY}.json"; fi
  if [[ -f "/run/planefence/planefence.csv" ]]; then  cp -f "/run/planefence/planefence.csv" "/usr/share/planefence/html/planefence-${TODAY}.csv"; fi
  if [[ -f "/run/planefence/plane-alert.csv" ]]; then  cp -f "/run/planefence/plane-alert.csv" "/usr/share/planefence/html/plane-alert-${TODAY}.csv"; fi
fi
