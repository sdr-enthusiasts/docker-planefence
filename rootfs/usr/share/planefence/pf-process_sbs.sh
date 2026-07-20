#!/command/with-contenv bash
# shellcheck shell=bash
# -------------------------------------------------------------------
# pf-process_sbs.sh – wrapper that invokes the Python rewrite
# Zero external dependencies: python3 + sqlite3 are in the base image.
# -------------------------------------------------------------------
set -euo pipefail

# Source common helpers (if they exist – harmless if not)
# shellcheck disable=SC1091
source /scripts/pf-common 2>/dev/null || true
# shellcheck disable=SC1091
source /usr/share/planefence/planefence.conf 2>/dev/null || true

PY_SCRIPT="/usr/share/planefence/pf-process_sbs.py"

# Ensure python3 is present (sdr-enthusiasts base images include it)
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found in container" >&2
    exit 1
fi

# Run the Python processor, passing all arguments
exec python3 "$PY_SCRIPT" "$@"
