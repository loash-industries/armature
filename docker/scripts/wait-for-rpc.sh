#!/usr/bin/env bash
# wait-for-rpc.sh — Block until the Sui JSON-RPC endpoint is healthy.
# Usage: wait-for-rpc.sh <rpc_url> [timeout_seconds]
#
# Tries curl first, falls back to perl TCP check.
set -euo pipefail

RPC_URL="${1:-http://sui-localnet:9000}"
TIMEOUT="${2:-120}"
INTERVAL=2
ELAPSED=0

echo "[wait] Waiting for Sui RPC at $RPC_URL (timeout ${TIMEOUT}s)..."

# Extract host:port from URL
HOST_PORT=$(echo "$RPC_URL" | sed -E 's|https?://||;s|/.*||')

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  # Try curl if available
  if command -v curl &>/dev/null; then
    if curl -sf -X POST "$RPC_URL" \
      -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"sui_getLatestCheckpointSequenceNumber","params":[]}' \
      > /dev/null 2>&1; then
      echo "[wait] Sui RPC is ready."
      exit 0
    fi
  else
    # Fallback: perl TCP check
    if perl -e "use IO::Socket::INET; exit(IO::Socket::INET->new(PeerAddr=>q($HOST_PORT),Timeout=>2) ? 0 : 1)" 2>/dev/null; then
      echo "[wait] Sui RPC is ready (TCP check)."
      exit 0
    fi
  fi
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "[wait] ERROR: Sui RPC not ready after ${TIMEOUT}s"
exit 1
