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

source /scripts/common

ACCESS_TOKEN=$MASTODON_ACCESS_TOKEN
INSTANCE_URL="https://$MASTODON_SERVER"

RETENTION_DAYS="${MASTODON_RETENTION_TIME:-7}"

delete_toot() {
    local toot_id="$1"
    local result
    if ! result="$(curl -s --fail -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" "$INSTANCE_URL/api/v1/statuses/$toot_id" 2>&1)"; then
        echo ""
        "${s6wrap[@]}" echo "error deleting $toot_id: $result"
    fi
}

if chk_disabled "$MASTODON_RETENTION_TIME"; then
    "${s6wrap[@]}" echo "MASTODON_RETENTION_TIME is set to $MASTODON_RETENTION_TIME (disabled); nothing to do!"
    exit 0
fi

if [[ -z "$MASTODON_RETENTION_TIME" ]]; then
    "${s6wrap[@]}" echo "Warning: MASTODON_RETENTION_TIME not set. Defaulting to $RETENTION_DAYS days."
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
counter=0
while : ; do
    expired=0
    unexpired=0
    oldest=33000000000
    newest=0
    output=("Indexing Toots")
    toots="$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$INSTANCE_URL/api/v1/accounts/$masto_id/statuses?limit=40${last_id:+&max_id=}${last_id}")"
    # shellcheck disable=SC2207
    toot_ids=($(jq -r '.[] | .id' <<< "$toots" 2>/dev/null || true))
    if (( ${#toot_ids[@]} == 0)); then
        "${s6wrap[@]}" echo "No more Toots; done!"
        exit 0
    fi
    last_id="${toot_ids[-1]}"

    output+=("$((counter+1)) - $((counter+${#toot_ids[@]})) (${#toot_ids[@]} toots).")
    (( counter+=${#toot_ids[@]} )) || true
    for t in "${toot_ids[@]}"; do
        if [[ -z "${toot_dates[$t]}" ]]; then
            toot_dates[$t]="$(date -d "$(jq -r 'map(select(.id == "'"$t"'"))[].created_at'  <<< "$toots")" +%s)"
            if (( toot_dates[$t] < oldest )); then oldest="${toot_dates[$t]}"; fi
            if (( toot_dates[$t]  > newest )); then newest="${toot_dates[$t]}"; fi
            if (( (now - toot_dates[$t])/(60*60*24) > RETENTION_DAYS )); then
                (( expired++ )) || true
                if [[ "$1" == "delete" ]]; then
                    delete_toot "$t";
                fi 
            else
                (( unexpired++ )) || true
            fi
        else
            if chk_enabled "$MASTODON_DEBUG"; then "${s6wrap[@]}" echo "No more Toots; done!"; fi
            exit
        fi
    done
    if chk_enabled "$MASTODON_DEBUG"; then 
        output+=("($unexpired unexpired; $expired expired; oldest $(date -d "@$oldest") ($(( (now - oldest)/(60*60*24) )) days); newest $(date -d "@$newest") ($(( (now - newest)/(60*60*24) )) days))")
        "${s6wrap[@]}" echo "${output[@]}"
    fi
done