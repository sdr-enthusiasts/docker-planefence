#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

exec /bin/bash /usr/share/planefence/stream.sh "$@"
