#!/usr/bin/bash

# Exit abnormally for any error
set -eo pipefail

# Set default exit code
EXITCODE=0

# see if planefence actually responds in an expected manner
# (originally I only checked to see if someething listens on port 80,
# this check is a little more sophisticaed and checks that we actually
# get a 200 OK response from the service.
#
PLANEFENCE_EXPECTED_STATUS="200"
PLANEFENCE_STATUS=$(curl --silent -o /dev/null --head --write-out '%{http_code}' localhost)
if [ "${PLANEFENCE_STATUS}" -eq "${PLANEFENCE_EXPECTED_STATUS}" ]; then
    echo "[$(date)][HEALTHY] Planefence is UP (Status: ${PLANEFENCE_STATUS})"
else
    echo "[$(date)][UNHEALTHY] Planefence is DOWN (Status: ${PLANEFENCE_STATUS})"
    EXITCODE=1
fi

# Exit with determined exit status
exit "$EXITCODE"
