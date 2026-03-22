#!/bin/bash
set -euo pipefail

export RUST_BACKTRACE=1
export RUST_LOG=${RUST_LOG:-info}

KEEPALIVE_ON_EXIT=${KEEPALIVE_ON_EXIT:-false}

echo "[entry.sh] starting armature-indexer" >&2
echo "[entry.sh] NETWORK=${NETWORK:-<unset>}" >&2
echo "[entry.sh] FIRST_CHECKPOINT=${FIRST_CHECKPOINT:-<unset>} LAST_CHECKPOINT=${LAST_CHECKPOINT:-<unset>}" >&2
echo "[entry.sh] START_FROM_SCRATCH=${START_FROM_SCRATCH:-<unset>}" >&2
echo "[entry.sh] HEARTBEAT_INTERVAL_SECONDS=${HEARTBEAT_INTERVAL_SECONDS:-5}" >&2

if [ -z "${DATABASE_URL:-}" ]; then
    echo "[entry.sh] DATABASE_URL is empty/unset" >&2
else
    echo "[entry.sh] DATABASE_URL is set (redacted)" >&2
fi

# Build command arguments
args=(
    --database-url "$DATABASE_URL"
    --env "$NETWORK"
)

if [ -n "${FIRST_CHECKPOINT:-}" ]; then
    args+=(--first-checkpoint "$FIRST_CHECKPOINT")
fi
if [ -n "${LAST_CHECKPOINT:-}" ]; then
    args+=(--last-checkpoint "$LAST_CHECKPOINT")
fi
if [ "${START_FROM_SCRATCH:-}" = "true" ]; then
    args+=(--start-from-scratch)
fi
if [ -n "${HEARTBEAT_INTERVAL_SECONDS:-}" ]; then
    args+=(--heartbeat-interval-seconds "$HEARTBEAT_INTERVAL_SECONDS")
fi

/opt/streams/bin/armature-indexer "${args[@]}"
code=$?

echo "[entry.sh] armature-indexer exited with code ${code}" >&2
if [ "${KEEPALIVE_ON_EXIT}" = "true" ]; then
    echo "[entry.sh] KEEPALIVE_ON_EXIT=true; sleeping for debugging" >&2
    sleep infinity
fi
exit "${code}"