#!/usr/bin/env sh
# run-indexer.sh — Load deploy artifacts then start the indexer.
#
# When running inside docker-compose.dev.yml the armature-deploy container
# writes ARMATURE_PACKAGE_ID to /shared/.env.armature.  Source it so the
# indexer knows which package to filter on.
set -eu

SHARED_DIR="${SHARED_DIR:-/shared}"

if [ -f "$SHARED_DIR/.env.armature" ]; then
    # Export all variables from the file (skip comment lines)
    # shellcheck disable=SC2046
    export $(grep -v '^#' "$SHARED_DIR/.env.armature" | xargs)
    echo "[indexer] Loaded package ID: ${ARMATURE_PACKAGE_ID:-<not set>}"
else
    echo "[indexer] No $SHARED_DIR/.env.armature found — using env as-is"
fi

exec armature-indexer "$@"
