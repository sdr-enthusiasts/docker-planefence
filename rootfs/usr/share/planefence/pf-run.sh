#!/command/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034,SC2154,SC2155
#
# #-----------------------------------------------------------------------------------
# PF-RUN.SH
# Do a Planefence Run
#
# Copyright 2020-2025 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
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

PF_PATH="/usr/share/planefence"
PA_PATH="/usr/share/planefence"
NOTIFY_PATH="$PF_PATH/notifiers"
DELETEAFTER="10"  # minutes

# -----------------------------------------------------------------------------------
#       SETTINGS STUFF
# -----------------------------------------------------------------------------------
set -eo pipefail
shopt -s nullglob

#DEBUG=true



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
DELETEAFTER="10"
  # Limit depth to prevent descending into other directories.
  find /tmp -maxdepth 1 -mindepth 1 \
    \( -name '.pf-noisecache-*' -o -name 'tmp.*' -o -name 'pa_key_*' \) \
    -mmin +"${DELETEAFTER}" \
    -exec rm -rf -- {} + 2>/dev/null || :
# ./pf-create-html.sh	&	# create PF HTML page

# Run heatmap script in the background
./pf-heatmap.sh &

# Run notifiers scripts in the background
if script_array="$(compgen -G "$NOTIFY_PATH/send*.sh" 2>/dev/null)"; then
  while read -r script; do
      bash "$script" || true &  
  done <<< "$script_array"
fi
wait # wait for all background processes to finish

#/usr/share/plane-alert/plane-alert.sh	# run plane-alert
