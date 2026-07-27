#!/bin/bash
# Start Data API Builder once its runtime configuration is available.
#
# DAB's configuration (dab-config.json) is provisioned into the container at
# deployment time. To guarantee a clean, deterministic startup, this script
# waits for the configuration to be present before launching DAB rather than
# starting against a placeholder, then execs the engine.
set -eu

CONFIG_PATH="${CONFIG_PATH:-/App/dab-config.json}"
POLL_INTERVAL="${POLL_INTERVAL:-0.2}"
TIMEOUT="${TIMEOUT:-300}"

echo "Waiting for DAB config at ${CONFIG_PATH} (timeout ${TIMEOUT}s, poll every ${POLL_INTERVAL}s)..."

# Epoch-based deadline so the poll interval can be sub-second (bash integer
# arithmetic can't accumulate fractional seconds). The loop tests for the file
# before sleeping, so an already-present config starts DAB with no delay.
deadline=$(( $(date +%s) + TIMEOUT ))
while [ ! -f "$CONFIG_PATH" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "ERROR: timed out after ${TIMEOUT}s waiting for ${CONFIG_PATH}" >&2
        exit 1
    fi
    sleep "$POLL_INTERVAL"
done

echo "Config found at ${CONFIG_PATH}. Starting Data API Builder..."
exec dotnet Azure.DataApiBuilder.Service.dll
