#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2174,SC2015,SC2154
# -----------------------------------------------------------------------------------
# Copyright 2024 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/docker-planefence/
#
# This package may incorporate other software and license terms.
# -----------------------------------------------------------------------------------

if [[ -f /usr/share/planefence/persist/planefence.config ]]; then
    source /usr/share/planefence/persist/planefence.config
fi

ACCESS_TOKEN=$MASTODON_ACCESS_TOKEN
INSTANCE_URL="https://$MASTODON_SERVER"

RETENTION_DAYS="${MASTODON_RETENTION_TIME:-14}"

delete_toot() {
    local toot_id="$1"
    local result
    if result="$(curl -s --fail -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" "$INSTANCE_URL/api/v1/statuses/$toot_id" 2>&1)"; then
        [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo "successfully deleted" || true
    else
        "${s6wrap[@]}" echo "error: $result"
    fi
}

if [[ -z "$MASTODON_RETENTION_TIME" ]]; then
    "${s6wrap[@]}" echo "Warning: MASTODON_RETENTION_TIME not set. Defaulting to 14 days."
fi

if [[ -z "$MASTODON_ACCESS_TOKEN" ]]; then
    "${s6wrap[@]}" echo "MASTODON_ACCESS_TOKEN not set. Exiting."
    exit 1
fi

if [[ -z "$MASTODON_SERVER" ]]; then
    "${s6wrap[@]}" echo "MASTODON_SERVER not set. Exiting."
    exit 1
fi

unset toot_dates counter last_id
declare -A toot_dates

now="$(date +%s)"

masto_id="$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$INSTANCE_URL/api/v1/accounts/verify_credentials" | jq -r '.id')"

while : ; do
    [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo -n "Indexing Media IDs round $((++counter))" || true
    toots="$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$INSTANCE_URL/api/v1/accounts/$masto_id/statuses?limit=40${last_id:+&max_id=}${last_id}")"
    # shellcheck disable=SC2207
    toot_ids=($(jq -r '.[] | .id' <<< "$toots" 2>/dev/null))
    if (( ${#toot_ids[@]} == 0)); then
        [[ "${LOGLEVEL,,}" != "error" ]] && echo "No more toots, we are done!" || true
        exit
    fi
    last_id="${toot_ids[-1]}"
    [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo " ${#toot_ids[@]} toots" || true
    for t in "${toot_ids[@]}"; do
        if [[ -z "${toot_dates[$t]}" ]]; then
            toot_dates[$t]="$(date -d "$(jq -r 'map(select(.id == "'"$t"'"))[].created_at'  <<< "$toots")" +%s)"
            [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo -n "$t --> $(date -d @"${toot_dates[$t]}") " || true
            if (( (now - toot_dates[$t])/(60*60*24) > RETENTION_DAYS )); then
                [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo -n " expired (age: $(( (now - toot_dates[$t])/(60*60*24) )) days): " || true
                if [[ "$1" == "delete" ]]; then
                    [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo -n "deleting... " || true
                    delete_toot "$t";
                else
                    [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo "(not deleted)" || true
                fi 
            else
                [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo " not expired (age: $(( (now - toot_dates[$t])/(60*60*24) )) days)" || true
            fi
        else
            [[ "${LOGLEVEL,,}" != "error" ]] && "${s6wrap[@]}" echo "$t --> duplicate, we're done!" || true
            exit
        fi
    done
done