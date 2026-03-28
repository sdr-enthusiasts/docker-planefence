#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

exec /usr/share/planefence/stream.sh "$@"
