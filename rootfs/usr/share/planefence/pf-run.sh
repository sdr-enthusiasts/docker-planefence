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

PFDIR="/usr/share/planefence"
PADIR="/usr/share/plane-alert"

# -----------------------------------------------------------------------------------
#      TEMP DEBUG STUFF
# -----------------------------------------------------------------------------------
set -eo pipefail
DEBUG=true

# -----------------------------------------------------------------------------------
#      RUN PLANEFENCE
# -----------------------------------------------------------------------------------

cd "$PFDIR"

./pf-process_sbs.sh	&	# read and process SBS data
pid=$!
echo "$pid" > /run/pf-process_sbs.pid
wait "$pid"
rm -f /run/pf-process_sbs.pid

./pf-create-html.sh		# create PF HTML page

# Run notifiers scripts in the background
# if compgen -G "notifiers/send*.sh" > /dev/null; then
# 	scripts=( notifiers/send*.sh )
#   for script in "${scripts[@]}"; do
#     if [ -f "$script" ]; then
#       bash "$script" || true &
#     fi
#   done
# fi

#/usr/share/plane-alert/plane-alert.sh	# run plane-alert
