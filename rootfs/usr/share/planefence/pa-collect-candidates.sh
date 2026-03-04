#!/command/with-contenv bash
#shellcheck shell=bash
#shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2155
#
# PA-GET-UNLISTED-CANDIDATES - a Bash shell script to read SBS data and create a database of unlisted candidates for Plane-Alert mode. This script is part of the
#
# Copyright 2026 Ramon F. Kolb (kx1t) - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
#
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
# Only change the variables below if you know what you are doing.

## DEBUG stuff:
DEBUG="${DEBUG:-false}"

## initialization:
if [[ -r /scripts/pf-common ]]; then
	source /scripts/pf-common
else
	echo "[ERROR] /scripts/pf-common not found. Run this script inside the Planefence container environment." >&2
	exit 2
fi

TODAY="$(date +%y%m%d)"
CANDIDATE_FILE="/usr/share/planefence/persist/plane-alert-candidates.txt"
FILTER_FILE="/usr/share/planefence/persist/pa-candidates-filter.txt"
FILTER_FILE_DEFAULT="/usr/share/planefence/persist/pa-candidates-filter.txt"
HEADER='ICAO,Tail,Operator,Type,ICAO Type,CMPG,,,,Category,photo_link'

PA_FILE="$(GET_PARAM pa PA_FILE || true)"
if [[ -z "$PA_FILE" ]]; then
	PA_FILE="$(GET_PARAM pa PLANEFILE || true)"
fi
PA_FILE="${PA_FILE:-/usr/share/planefence/persist/.internal/plane-alert-db.txt}"

GET_TAIL() {
	local icao=${1^^}
	local tail=""

	if [[ -f "/usr/share/planefence/persist/.internal/icao2tail.cache" ]]; then
		tail="$(awk -F, -v icao="$icao" '$1 == icao {print $2; exit}' "/usr/share/planefence/persist/.internal/icao2tail.cache")"
		[[ -n "$tail" ]] && { printf '%s\n' "${tail// /}"; return; }
	fi

	if [[ -f /run/planefence/icao2plane.txt ]]; then
		tail="$(grep -m1 -i -F "$icao" /run/planefence/icao2plane.txt 2>/dev/null | awk -F, '{print $2}')"
	fi

	if [[ -z "$tail" && -f /run/OpenSkyDB.csv ]]; then
		tail="$(grep -m1 -i -F "$icao" /run/OpenSkyDB.csv | awk -F, '{print $27}')"
		tail="${tail//[ \"\']/}"
	fi

	if [[ -z "$tail" ]] && [[ "$icao" =~ ^A && ! "$icao" =~ ^AE && ! "$icao" =~ ^ADE && ! "$icao" =~ ^ADF ]]; then
		tail="$(/usr/share/planefence/icao2tail.py "$icao" 2>/dev/null || true)"
	fi

	if [[ -n "$tail" ]]; then
		echo "$icao,${tail// /}" >> "/usr/share/planefence/persist/.internal/icao2tail.cache"
		printf '%s\n' "${tail// /}"
	fi
}

GET_ADSB_META() {
	# Returns: ICAO_TYPE<TAB>TYPE_TEXT<TAB>OWNER_FALLBACK
	local icao=${1^^}
	curl -m 20 -sSL "https://api.adsb.lol/v2/hex/$icao" \
		| jq -r '[(.ac[0].t // ""), (.ac[0].desc // ""), (.ac[0].ownOp // "")] | @tsv' 2>/dev/null
}

GET_PS_PHOTO_LINK() {
	local icao=${1^^}
	local json link
	local ctime=$((3 * 24 * 3600))
	local dir="/usr/share/planefence/persist/planepix/cache"
	local lnk="$dir/$icao.link"
	local na="$dir/$icao.notavailable"

	# Default to enabled unless explicitly disabled.
	chk_enabled "${SHOWIMAGES:-true}" || return 0

	mkdir -p "$dir" 2>/dev/null || :
	[[ -f "$na" ]] && return 0

	if [[ -f "$lnk" ]] && (( $(date +%s) - $(stat -c %Y -- "$lnk") < ctime )); then
		cat "$lnk"
		return 0
	fi

	if json="$(curl -m 20 -fsSL --fail "https://api.planespotters.net/pub/photos/hex/$icao" 2>/dev/null)" && \
		 link="$(jq -r 'try .photos[].link | select(. != null) | .' <<< "$json" | head -n1)" && \
		 [[ -n "$link" ]]; then
		printf '%s\n' "$link" > "$lnk"
		printf '%s\n' "$link"
	else
		rm -f "$dir/$icao".* 2>/dev/null || :
		touch "$na"
	fi
}

DERIVE_CPMG() {
	local probe="${1^^} ${2^^}"
	if [[ "$probe" =~ MIL|MILITARY|AIR[[:space:]]FORCE|USAF|RAF|NAVY|ARMY|MARINE ]]; then
		printf 'Mil\n'
	fi
}

LOAD_CANDIDATE_FILTERS() {
	declare -g -a FILTER_ICAO_PATTERNS FILTER_CALLSIGN_PATTERNS
	declare -gA FILTER_ICAO_OWNER FILTER_CALLSIGN_OWNER
	FILTER_ICAO_PATTERNS=()
	FILTER_CALLSIGN_PATTERNS=()
	FILTER_ICAO_OWNER=()
	FILTER_CALLSIGN_OWNER=()

	if [[ ! -f "$FILTER_FILE" && -f "$FILTER_FILE_DEFAULT" ]]; then
		cp -f "$FILTER_FILE_DEFAULT" "$FILTER_FILE" 2>/dev/null || :
	fi

	if [[ ! -f "$FILTER_FILE" ]]; then
		log_print WARN "Filter file $FILTER_FILE not found; processing without pattern filtering"
		return
	fi

	local line key pattern owner rest
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		if [[ -z "$line" ]]; then
			continue
		fi
		if [[ "${line:0:1}" == "#" ]]; then
			continue
		fi

		if [[ "$line" == *:* ]]; then
			key="${line%%:*}"
			rest="${line#*:}"
			if [[ "$rest" == *:* ]]; then
				pattern="${rest%%:*}"
				owner="${rest#*:}"
			else
				pattern="$rest"
				owner=""
			fi
		else
			key="ICAO"
			pattern="$line"
			owner=""
		fi

		key="${key^^}"
		pattern="${pattern^^}"
		pattern="${pattern#"${pattern%%[![:space:]]*}"}"
		pattern="${pattern%"${pattern##*[![:space:]]}"}"
		owner="${owner#"${owner%%[![:space:]]*}"}"
		owner="${owner%"${owner##*[![:space:]]}"}"
		[[ -z "$pattern" ]] && continue

		case "$key" in
			ICAO)
				FILTER_ICAO_PATTERNS+=("$pattern")
				FILTER_ICAO_OWNER["$pattern"]="$owner"
				;;
			CALLSIGN|CS)
				FILTER_CALLSIGN_PATTERNS+=("$pattern")
				FILTER_CALLSIGN_OWNER["$pattern"]="$owner"
				;;
		esac
	done < "$FILTER_FILE"
}

MATCH_CANDIDATE_FILTER() {
	local icao="${1^^}"
	local callsign="${2^^}"
	local p
	CANDIDATE_MATCH_REASON=""
	CANDIDATE_MATCH_OWNER=""

	# No filters loaded -> keep legacy behavior (process all)
	if (( ${#FILTER_ICAO_PATTERNS[@]} == 0 && ${#FILTER_CALLSIGN_PATTERNS[@]} == 0 )); then
		CANDIDATE_MATCH_REASON="no-filters"
		CANDIDATE_MATCH_OWNER=""
		return 0
	fi

	for p in "${FILTER_ICAO_PATTERNS[@]}"; do
		# shellcheck disable=SC2053  # intentional glob matching from filter file patterns
		if [[ "$icao" == $p ]]; then
			CANDIDATE_MATCH_REASON="ICAO:$p"
			CANDIDATE_MATCH_OWNER="${FILTER_ICAO_OWNER[$p]:-}"
			return 0
		fi
	done
	if [[ -n "$callsign" ]]; then
		for p in "${FILTER_CALLSIGN_PATTERNS[@]}"; do
			# shellcheck disable=SC2053  # intentional glob matching from filter file patterns
			if [[ "$callsign" == $p ]]; then
				CANDIDATE_MATCH_REASON="CALLSIGN:$p"
				CANDIDATE_MATCH_OWNER="${FILTER_CALLSIGN_OWNER[$p]:-}"
				return 0
			fi
		done
	fi
	return 1
}

if chk_disabled "$(GET_PARAM base PF_PLANEALERT)" || chk_disabled "$(GET_PARAM base PA_COLLECT_CANDIDATES)"; then
	log_print DEBUG "PF_PLANEALERT or PA_COLLECT_CANDIDATES is disabled; not starting $0"
	exit 0
fi

log_print INFO "Starting $0"
script_start_epoch="$(date +%s)"
stage_epoch="$script_start_epoch"
log_print DEBUG "Config: TODAY=$TODAY, PA_FILE=$PA_FILE, CANDIDATE_FILE=$CANDIDATE_FILE"

mkdir -p "$(dirname "$CANDIDATE_FILE")" "/usr/share/planefence/persist/.internal" 2>/dev/null || :

LOAD_CANDIDATE_FILTERS
log_print DEBUG "Loaded ${#FILTER_ICAO_PATTERNS[@]} ICAO and ${#FILTER_CALLSIGN_PATTERNS[@]} callsign filter pattern(s) from $FILTER_FILE"

readarray -t dumpfiles < <(find /run/socket30003 -type f -name "dump1090-*-${TODAY}.txt" -print | sort)
if (( ${#dumpfiles[@]} == 0 )); then
	log_print INFO "No dump1090 input files found for $TODAY; exiting"
	exit 0
fi
log_print DEBUG "Found ${#dumpfiles[@]} dump1090 input file(s) for $TODAY"

declare -A listed_icao existing_candidates latest_callsign

if [[ -f "$PA_FILE" ]]; then
	while IFS= read -r i; do
		i="${i^^}"
		[[ -n "$i" ]] && listed_icao["$i"]=1
	done < <(awk -F',' '
		NR==1 && toupper($1) == "ICAO" { next }
		$1 ~ /^[[:space:]]*#/ { next }
		$1 != "" { gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $1); print $1 }
	' "$PA_FILE")
fi
log_print DEBUG "Loaded ${#listed_icao[@]} ICAO(s) from PA file exclusion list"

if [[ -f "$CANDIDATE_FILE" ]]; then
	while IFS=$'\t' read -r icao line; do
		[[ -z "$icao" || -z "$line" ]] && continue
		existing_candidates["$icao"]="$line"
	done < <(awk -F',' '
		NR==1 && toupper($1) == "ICAO" { next }
		$0 == "" { next }
		{
			icao = toupper($1)
			gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", icao)
			if (icao != "") print icao "\t" $0
		}
	' "$CANDIDATE_FILE")
fi
log_print DEBUG "Loaded ${#existing_candidates[@]} existing candidate record(s)"
now_epoch="$(date +%s)"
log_print DEBUG "Stage load-lists completed in $((now_epoch - stage_epoch))s"
stage_epoch="$now_epoch"

tmp_icaos="$(mktemp)"
tmp_callsigns="$(mktemp)"
awk -F, -v cfile="$tmp_icaos" -v sfile="$tmp_callsigns" '
	NF != 12 { next }
	$1 == "" { next }
	{
		icao = toupper($1)
		if (icao == "HEX_IDENT") next
		seen[icao] = 1
		cs = $12
		gsub(/[[:space:]]/, "", cs)
		# Prefer records that have a callsign: keep latest non-empty callsign per ICAO.
		if (cs != "") latest[icao] = cs
	}
	END {
		for (i in seen) print i > cfile
		for (i in latest) print i "\t" latest[i] > sfile
	}
' "${dumpfiles[@]}"

readarray -t candidate_icaos < <(LC_ALL=C sort -u "$tmp_icaos")
while IFS=$'\t' read -r icao callsign; do
	[[ -n "$icao" && -n "$callsign" ]] && latest_callsign["$icao"]="$callsign"
done < "$tmp_callsigns"
rm -f "$tmp_icaos" "$tmp_callsigns"

log_print DEBUG "Built latest callsign map for ${#latest_callsign[@]} ICAO(s)"
log_print DEBUG "Collapsed socket records into ${#candidate_icaos[@]} unique ICAO candidate(s)"
now_epoch="$(date +%s)"
log_print DEBUG "Stage scan-input completed in $((now_epoch - stage_epoch))s"
stage_epoch="$now_epoch"

declare -a new_rows
processed=0
skipped_known=0
skipped_existing=0
skipped_filter=0
declare -a new_candidate_icaos
declare -A candidate_match_owner candidate_match_reason
for icao in "${candidate_icaos[@]}"; do
	callsign="${latest_callsign["$icao"]:-}"
	if ! MATCH_CANDIDATE_FILTER "$icao" "$callsign"; then
		((skipped_filter++)) || true
		continue
	fi
	if [[ -n ${listed_icao["$icao"]} ]]; then
		((skipped_known++)) || true
		continue
	fi
	if [[ -n ${existing_candidates["$icao"]} ]]; then
		((skipped_existing++)) || true
		continue
	fi
	new_candidate_icaos+=("$icao")
	candidate_match_owner["$icao"]="${CANDIDATE_MATCH_OWNER:-}"
	candidate_match_reason["$icao"]="${CANDIDATE_MATCH_REASON:-}"
	log_print INFO "New candidate $icao matched filter ${CANDIDATE_MATCH_REASON:-unknown} (callsign=${callsign:-none})"
done
log_print INFO "Filter summary: total=${#candidate_icaos[@]}, new=${#new_candidate_icaos[@]}, skipped_filter=$skipped_filter, skipped_known=$skipped_known, skipped_existing=$skipped_existing"

declare -A adsb_icao_type adsb_type_long adsb_owner
if (( ${#new_candidate_icaos[@]} > 0 )); then
	prefetch_start_epoch="$(date +%s)"
	tmp_meta_dir="$(mktemp -d)"
	max_jobs=8
	running=0

	for icao in "${new_candidate_icaos[@]}"; do
		{
			IFS=$'\t' read -r icao_type type_long owner_fallback <<< "$(GET_ADSB_META "$icao" 2>/dev/null || true)"
			printf '%s\t%s\t%s\t%s\n' "$icao" "${icao_type:-}" "${type_long:-}" "${owner_fallback:-}" > "$tmp_meta_dir/$icao.tsv"
		} &
		((running++)) || true
		if (( running >= max_jobs )); then
			wait -n 2>/dev/null || true
			((running--)) || true
		fi
	done
	wait 2>/dev/null || true

	while IFS=$'\t' read -r icao icao_type type_long owner_fallback; do
		[[ -z "$icao" ]] && continue
		adsb_icao_type["$icao"]="$icao_type"
		adsb_type_long["$icao"]="$type_long"
		adsb_owner["$icao"]="$owner_fallback"
	done < <(cat "$tmp_meta_dir"/*.tsv 2>/dev/null || true)
	rm -rf "$tmp_meta_dir"
	prefetch_end_epoch="$(date +%s)"
	log_print DEBUG "Prefetched ADS-B metadata for ${#adsb_icao_type[@]} ICAO(s) in $((prefetch_end_epoch - prefetch_start_epoch))s (max_jobs=$max_jobs)"
fi

for icao in "${new_candidate_icaos[@]}"; do

	((processed++)) || true
	if (( processed % 50 == 0 )); then
		log_print DEBUG "Progress: processed $processed new ICAO(s); added ${#new_rows[@]} so far"
	fi

	callsign="${latest_callsign["$icao"]:-}"
	tail="$(GET_TAIL "$icao" 2>/dev/null || true)"
	icao_type="${adsb_icao_type["$icao"]:-}"
	type_long="${adsb_type_long["$icao"]:-}"
	owner_fallback="${adsb_owner["$icao"]:-}"
	owner_from_filter="${candidate_match_owner["$icao"]:-}"

	owner="$owner_fallback"
	# Re-check owner via airlinename.sh, but only for records that already passed all filters
	# and are being written to output (minimizes expensive lookups).
	if [[ -z "$owner" && -n "$callsign" ]]; then
		owner="$(/usr/share/planefence/airlinename.sh "$callsign" "$icao" 2>/dev/null || true)"
	fi
	if [[ -z "$owner" && -n "$tail" ]]; then
		owner="$(/usr/share/planefence/airlinename.sh "$tail" "$icao" 2>/dev/null || true)"
	fi
	if [[ -z "$owner" && -n "$owner_from_filter" ]]; then
		owner="$owner_from_filter"
	fi

	[[ -z "$type_long" ]] && type_long="$icao_type"

	photo_link="$(GET_PS_PHOTO_LINK "$icao" 2>/dev/null || true)"

	cpmg="$(DERIVE_CPMG "$owner" "$type_long")"
	category="$owner"

	row="$(csv_encode "$icao"),$(csv_encode "$tail"),$(csv_encode "$owner"),$(csv_encode "$type_long"),$(csv_encode "$icao_type"),$(csv_encode "$cpmg"),,,,$(csv_encode "$category"),$(csv_encode "$photo_link")"
	new_rows+=("$row")
	existing_candidates["$icao"]="$row"
done
log_print DEBUG "Loop summary: processed=$processed, skipped_known=$skipped_known, skipped_existing=$skipped_existing, new=${#new_rows[@]}"
now_epoch="$(date +%s)"
log_print DEBUG "Stage build-candidates completed in $((now_epoch - stage_epoch))s"
stage_epoch="$now_epoch"

tmpfile="$(mktemp)"
{
	printf '%s\n' "$HEADER"
	{
		for icao in "${!existing_candidates[@]}"; do
			printf '%s\n' "${existing_candidates[$icao]}"
		done
	} | LC_ALL=C sort -t',' -k1,1f
} > "$tmpfile"

mv -f "$tmpfile" "$CANDIDATE_FILE"
chmod a+r "$CANDIDATE_FILE"
now_epoch="$(date +%s)"
log_print DEBUG "Stage write-output completed in $((now_epoch - stage_epoch))s"

script_end_epoch="$(date +%s)"
log_print DEBUG "Execution time: $((script_end_epoch - script_start_epoch))s"
log_print INFO "Done. Wrote $((${#existing_candidates[@]})) candidate records to $CANDIDATE_FILE (new: ${#new_rows[@]})."
