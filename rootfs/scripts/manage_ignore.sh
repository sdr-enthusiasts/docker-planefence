#!/command/with-contenv bash
#shellcheck shell=bash disable=SC2015,SC2164,SC1090,SC2154,SC1091
#---------------------------------------------------------------------------------------------
# Copyright (C) 2025, Ramon F. Kolb (kx1t)
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
#---------------------------------------------------------------------------------------------
# This script searches for a term in the OpenSky database and returns formatted data

source /scripts/common
#set -x

argc="${#@}"

print_usage() {
  echo "$0: manage ignore list for Planefence and PlaneAlert"
  echo "Usage: $0 mode action term uuid"
  echo "Mode: pf (Planefence) or pa (PlaneAlert)"
  echo "Action: add or delete"
  echo "Term: the term to add or delete"
  echo "UUID: the UUID of the entry to modify"
}

if (( argc != 4 )); then
  print_usage
  exit 1
fi

mode="${1,,}"
action="${2,,}"
term="$3"
uuid="${4,,}"

if [[ ! -f /tmp/add_delete.uuid ]]; then
  echo "Error: cannot find /tmp/add_delete.uuid file. Aborting."
  exit 1
fi

if [[ -z "$uuid" || "$uuid" != "$(</tmp/add_delete.uuid)" ]]; then
  echo "For security reasons, you can only add/delete entries from the Ignore list for 5 minutes before you have to reload the PF/PA page. Please press <BACK>, reload the page, and try again."
  echo "(Token used was: $uuid; token expected is: $(</tmp/add_delete.uuid))"
  if [[ -f /tmp/add_delete.uuid.used ]]; then
    echo "Token expiration time was $(date --date="@$(( $(</tmp/add_delete.uuid.used) + 300 ))")"
  fi
  exit 1
fi

if [[ "$mode" != "pf" && "$mode" != "pa" ]]; then
  echo "Error: mode must be either 'pf' or 'pa'. Aborting."
  exit 1
fi

if [[ "$action" != "add" && "$action" != "delete" ]]; then
  echo "Error: action must be either 'add' or 'delete'. Aborting."
  exit 1
fi


if [[ "$mode" == "pa" ]]; then

  source /usr/share/planefence/persist/planefence.config
  if [[ "$action" == "add" ]]; then
    if [[ -z "$PA_EXCLUSIONS" ]]; then
      PA_EXCLUSIONS="$term"
    else
      PA_EXCLUSIONS+=",$term"
    fi
  elif [[ "$action" == "delete" ]]; then
    PA_EXCLUSIONS="$(sed -e 's/\b'"$term"'\b/,/g' -e 's/,,//g' <<< "$PA_EXCLUSIONS")"
  fi

  if grep -q "^\s*PA_EXCLUSIONS=" /usr/share/planefence/persist/planefence.config; then
    sed -i "s/^\s*PA_EXCLUSIONS=.*/PA_EXCLUSIONS=$PA_EXCLUSIONS/" /usr/share/planefence/persist/planefence.config
  else
    echo "PA_EXCLUSIONS=$PA_EXCLUSIONS" >> /usr/share/planefence/persist/planefence.config
  fi
  /usr/share/plane-alert/get-pa-alertlist.sh # Update the Plane-Alert alert list
  touch /tmp/.force_pa_webpage_update # Force a webpage update

elif [[ "$mode" == "pf" ]]; then

  if [[ "$action" == "add" ]]; then
    echo "$term" >> /usr/share/planefence/persist/planefence-ignore.txt
    # sed -i "/$term/d" "/usr/share/planefence/html/planefence-$(date --date="today" '+%y%m%d').csv"
  elif [[ "$action" == "delete" ]]; then
    sed -i "/$term/d" /usr/share/planefence/persist/planefence-ignore.txt
  fi

fi

# Update the UUID to prevent replay attacks
if [[ ! -f /tmp/add_delete.uuid.used ]]; then
  date +%s > /tmp/add_delete.uuid.used
fi