#!/usr/bin/env bash
# delete_record.sh - delete a Planefence or Plane-Alert record by index
# Usage: ./delete_record.sh <index> [PA/PF]

set -euo pipefail

usage() {
	echo "Usage: $0 <index> [PA/PF]" >&2
	exit 1
}

fail() {
	echo "Error: $1" >&2
	exit 1
}

reindex_records() {
	local idx_to_remove=$1
	# shellcheck disable=SC2178
	local -n rec=target_records
	local -A rebuilt=()
	local key old_idx suffix new_idx new_key
	local max_idx=${rec[maxindex]:--1}

	for key in "${!rec[@]}"; do
		[[ $key == maxindex ]] && continue
		if [[ $key =~ ^([0-9]+)(:.*)?$ ]]; then
			old_idx=${BASH_REMATCH[1]}
			suffix=${BASH_REMATCH[2]}
			if (( old_idx == idx_to_remove )); then
				continue
			fi
			if (( old_idx > idx_to_remove )); then
				new_idx=$(( old_idx - 1 ))
			else
				new_idx=$old_idx
			fi
			new_key="${new_idx}${suffix:-}"
			rebuilt["$new_key"]="${rec[$key]}"
		else
			rebuilt["$key"]="${rec[$key]}"
		fi
	done

	local updated_max=$(( max_idx - 1 ))
	(( updated_max < 0 )) && updated_max=-1
	rebuilt[maxindex]=$updated_max

	for key in "${!rec[@]}"; do
		unset "rec[$key]"
	done
	for key in "${!rebuilt[@]}"; do
		rec["$key"]="${rebuilt[$key]}"
	done
}

refresh_index_maps() {
	# shellcheck disable=SC2178
	local -n rec=target_records
	# shellcheck disable=SC2178
	local -n idx_map=target_idx_map
	local max_idx=${rec[maxindex]:--1}
	local key

	for key in "${!idx_map[@]}"; do
		unset "idx_map[$key]"
	done

	if $has_lastseen_map; then
		local -n lastseen_map=target_lastseen_map
		for key in "${!lastseen_map[@]}"; do
			unset "lastseen_map[$key]"
		done
		if (( max_idx < 0 )); then
			return
		fi
		local i icao last_ts first_ts stamp
		for (( i=0; i<=max_idx; i++ )); do
			icao="${rec["$i":icao]:-}"
			[[ -z $icao ]] && continue
			idx_map["$icao"]="$i"
			last_ts="${rec["$i":time:lastseen]:-}"
			first_ts="${rec["$i":time:firstseen]:-}"
			stamp="${last_ts:-$first_ts}"
			[[ -n $stamp ]] && lastseen_map["$icao"]="$stamp"
		done
		return
	fi

	(( max_idx < 0 )) && return
	local i icao
	for (( i=0; i<=max_idx; i++ )); do
		icao="${rec["$i":icao]:-}"
		[[ -z $icao ]] && continue
		idx_map["$icao"]="$i"
	done
}

backup_records_file() {
	if [[ -f "$RECORDSFILE" ]]; then
		local backup
		backup="${RECORDSFILE}.bkup-$(date +%s)"
		cp -p -- "$RECORDSFILE" "$backup"
	else
		log_print WARN "Records file $RECORDSFILE not found, skipping backup"
	fi
}

[[ $# -ge 1 ]] || usage

INDEX="$1"
[[ $INDEX =~ ^[0-9]+$ ]] || fail "Index must be a non-negative integer"

MODE="${2:-PF}"
MODE="${MODE^^}"
[[ $MODE == PF || $MODE == PA ]] || fail "Mode must be either PF or PA"

TODAY="${TODAY:-$(date +%y%m%d)}"
RECORDSDIR="${RECORDSDIR:-/usr/share/planefence/persist/records}"
RECORDSFILE="${RECORDSFILE:-$RECORDSDIR/planefence-records-${TODAY}.gz}"

# shellcheck source=pf-common
# shellcheck disable=SC1091
source /scripts/pf-common

LOCK_RECORDS
trap 'UNLOCK_RECORDS' EXIT
READ_RECORDS ignore-lock

has_lastseen_map=false

case "$MODE" in
	PF)
		declare -n target_records="records"
		# shellcheck disable=SC2034
		declare -n target_idx_map="last_idx_for_icao"
		# shellcheck disable=SC2034
		declare -n target_lastseen_map="lastseen_for_icao"
		has_lastseen_map=true
		label="Planefence"
		;;
	PA)
		declare -n target_records="pa_records"
		# shellcheck disable=SC2034
		declare -n target_idx_map="pa_last_idx_for_icao"
		label="Plane-Alert"
		;;
esac

max_index=${target_records[maxindex]:--1}
(( max_index >= 0 )) || fail "$label has no stored records"
(( INDEX <= max_index )) || fail "Index $INDEX exceeds current maximum index $max_index for $label"

reindex_records "$INDEX"
refresh_index_maps

backup_records_file
WRITE_RECORDS ignore-lock

echo "$label record $INDEX deleted"
