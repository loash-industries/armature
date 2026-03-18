#!/usr/bin/env bash
# deploy-armature.sh — Publish armature_framework + armature_proposals on localnet.
#
# Can run standalone (generates its own key) or after world-deploy
# (reuses the governor key from /shared/.env.world).
#
# Outputs:
#   /shared/.env.armature  — package IDs + test DAO objects
#   /shared/ui.env.local   — ready-to-use .env.local for the UI
set -euo pipefail

SHARED_DIR="/shared"
ROOT_DIR="/workspace"
FRAMEWORK_DIR="$ROOT_DIR/packages/armature_framework"
PROPOSALS_DIR="$ROOT_DIR/packages/armature_proposals"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { echo -e "\033[1;34m[armature]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[armature]\033[0m $*"; }
err()   { echo -e "\033[1;31m[armature]\033[0m $*" >&2; }

# Extract a value from a JSON file using a node expression.
# Usage: json_extract <file> <js_expression_using_d>
json_extract() {
  node -e "
    const d = JSON.parse(require('fs').readFileSync('$1', 'utf8'));
    const val = $2;
    process.stdout.write(String(val ?? ''));
  "
}

# Extract JSON from a file that may have non-JSON lines before/after it.
# Finds the first '{' and parses from there.
json_extract_mixed() {
  node -e "
    const raw = require('fs').readFileSync('$1', 'utf8');
    const start = raw.indexOf('{');
    if (start === -1) { process.stdout.write(''); process.exit(0); }
    try {
      const d = JSON.parse(raw.slice(start));
      const val = $2;
      process.stdout.write(String(val ?? ''));
    } catch(e) { process.stdout.write(''); }
  "
}

# ── Source world deployment info (optional) ──────────────────────────────────
if [ -f "$SHARED_DIR/.env.world" ] && grep -q "GOVERNOR_PRIVATE_KEY=." "$SHARED_DIR/.env.world"; then
  set -a && source "$SHARED_DIR/.env.world" && set +a
  ok "Loaded world deployment: WORLD_PACKAGE_ID=${WORLD_PACKAGE_ID:-none}"
else
  info "No world deployment found — running standalone"
fi

RPC="${SUI_RPC_URL:-http://127.0.0.1:9000}"
FAUCET_URL="${SUI_FAUCET_URL:-http://127.0.0.1:9123}"

mkdir -p "$SHARED_DIR"

# ── Set up Sui client ────────────────────────────────────────────────────────
info "Configuring Sui client..."
mkdir -p "$HOME/.sui/sui_config"

cat > "$HOME/.sui/sui_config/client.yaml" <<EOF
---
keystore:
  File: $HOME/.sui/sui_config/sui.keystore
envs:
  - alias: localnet
    rpc: "$RPC"
    ws: ~
    basic_auth: ~
active_env: localnet
active_address: ~
EOF
echo "[]" > "$HOME/.sui/sui_config/sui.keystore"

# Import or generate key
if [ -n "${GOVERNOR_PRIVATE_KEY:-}" ]; then
  info "Importing key from world deployment..."
  ADDR=$(sui keytool import "$GOVERNOR_PRIVATE_KEY" ed25519 2>&1 | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
else
  info "Generating new keypair..."
  sui client new-address ed25519 --json > "$TMP_DIR/key.json" 2>/dev/null
  ADDR=$(json_extract "$TMP_DIR/key.json" "d.address")
fi
sui client switch --address "$ADDR" 2>/dev/null
ok "Active address: $ADDR"

# Fund via faucet
info "Requesting SUI from faucet..."
for i in 1 2 3; do
  curl -sf -X POST "$FAUCET_URL/gas" \
    -H 'Content-Type: application/json' \
    -d "{\"FixedAmountRequest\":{\"recipient\":\"$ADDR\"}}" \
    > /dev/null 2>&1 || true
  sleep 1
done
sleep 2
ok "Faucet funding complete"

# ── Clean ephemeral state ────────────────────────────────────────────────────
rm -f "$FRAMEWORK_DIR/.ephemeral.toml" "$PROPOSALS_DIR/.ephemeral.toml"
rm -f "$FRAMEWORK_DIR/Published.toml" "$PROPOSALS_DIR/Published.toml"

# ── Publish packages ─────────────────────────────────────────────────────────
info "Publishing armature packages (framework + proposals)..."

# test-publish bundles both packages into a single transaction.
# Move build progress lines mix with JSON output, so we extract the JSON.
EPH_FILE="$PROPOSALS_DIR/.ephemeral.toml"
PUB_FILE="$TMP_DIR/publish.out"
sui client test-publish "$PROPOSALS_DIR" \
  --gas-budget 500000000 \
  --skip-dependency-verification \
  --with-unpublished-dependencies \
  --build-env localnet \
  --pubfile-path "$EPH_FILE" \
  --json > "$PUB_FILE" 2>&1 || true

PACKAGE_ID=$(json_extract_mixed "$PUB_FILE" "(d.objectChanges || []).find(c => c.type === 'published')?.packageId")
MODULE_COUNT=$(json_extract_mixed "$PUB_FILE" "((d.objectChanges || []).find(c => c.type === 'published')?.modules || []).length")

if [ -z "$PACKAGE_ID" ]; then
  err "Failed to publish armature packages"
  cat "$PUB_FILE" | tail -30
  exit 1
fi

ok "Published: $PACKAGE_ID ($MODULE_COUNT modules)"

# ── Create test wallets ──────────────────────────────────────────────────────
info "Creating test wallets..."

sui client new-address ed25519 --json > "$TMP_DIR/user2.json" 2>/dev/null
USER2_ADDRESS=$(json_extract "$TMP_DIR/user2.json" "d.address")

sui client new-address ed25519 --json > "$TMP_DIR/user3.json" 2>/dev/null
USER3_ADDRESS=$(json_extract "$TMP_DIR/user3.json" "d.address")

# Fund all wallets
for addr in "$ADDR" "$USER2_ADDRESS" "$USER3_ADDRESS"; do
  curl -sf -X POST "$FAUCET_URL/gas" \
    -H 'Content-Type: application/json' \
    -d "{\"FixedAmountRequest\":{\"recipient\":\"$addr\"}}" \
    > /dev/null 2>&1 || true
done
sleep 3
ok "Wallets funded: $ADDR, $USER2_ADDRESS, $USER3_ADDRESS"

# ── Create test DAO ──────────────────────────────────────────────────────────
info "Creating test DAO..."

DAO_FILE="$TMP_DIR/dao.json"
sui client ptb \
  --make-move-vec "<address>" "[@${ADDR}, @${USER2_ADDRESS}, @${USER3_ADDRESS}]" \
  --assign members \
  --move-call "${PACKAGE_ID}::governance::init_board" members \
  --assign gov_init \
  --move-call "${PACKAGE_ID}::dao::create" gov_init '"Test DAO"' '"A test DAO for local e2e testing"' '"https://example.com/dao-logo.png"' \
  --gas-budget 100000000 \
  --json > "$DAO_FILE" 2>/dev/null

# PTB --json may use event_json (newer CLI) or events[].parsedJson (older)
DAO_ID=$(node -e "
  const d = JSON.parse(require('fs').readFileSync('$DAO_FILE', 'utf8'));
  // Try event_json first (newer sui ptb), then events[].parsedJson
  let evt;
  if (Array.isArray(d.event_json) && d.event_json[0]?.dao_id) {
    evt = d.event_json[0];
  } else if (Array.isArray(d.events)) {
    evt = d.events.find(e => e.type?.includes('::dao::DAOCreated'))?.parsedJson;
  }
  if (!evt) { process.stdout.write(''); process.exit(0); }
  process.stdout.write(evt.dao_id || '');
")
TREASURY_ID=$(node -e "
  const d = JSON.parse(require('fs').readFileSync('$DAO_FILE', 'utf8'));
  let evt;
  if (Array.isArray(d.event_json) && d.event_json[0]?.dao_id) evt = d.event_json[0];
  else if (Array.isArray(d.events)) evt = d.events.find(e => e.type?.includes('::dao::DAOCreated'))?.parsedJson;
  process.stdout.write(evt?.treasury_id || '');
")
CAP_VAULT_ID=$(node -e "
  const d = JSON.parse(require('fs').readFileSync('$DAO_FILE', 'utf8'));
  let evt;
  if (Array.isArray(d.event_json) && d.event_json[0]?.dao_id) evt = d.event_json[0];
  else if (Array.isArray(d.events)) evt = d.events.find(e => e.type?.includes('::dao::DAOCreated'))?.parsedJson;
  process.stdout.write(evt?.capability_vault_id || '');
")
CHARTER_ID=$(node -e "
  const d = JSON.parse(require('fs').readFileSync('$DAO_FILE', 'utf8'));
  let evt;
  if (Array.isArray(d.event_json) && d.event_json[0]?.dao_id) evt = d.event_json[0];
  else if (Array.isArray(d.events)) evt = d.events.find(e => e.type?.includes('::dao::DAOCreated'))?.parsedJson;
  process.stdout.write(evt?.charter_id || '');
")
FREEZE_ID=$(node -e "
  const d = JSON.parse(require('fs').readFileSync('$DAO_FILE', 'utf8'));
  let evt;
  if (Array.isArray(d.event_json) && d.event_json[0]?.dao_id) evt = d.event_json[0];
  else if (Array.isArray(d.events)) evt = d.events.find(e => e.type?.includes('::dao::DAOCreated'))?.parsedJson;
  process.stdout.write(evt?.emergency_freeze_id || '');
")

if [ -z "$DAO_ID" ]; then
  err "Failed to create test DAO"
  cat "$DAO_FILE" | tail -30
  exit 1
fi

ok "Test DAO created: $DAO_ID"
info "  Treasury:         $TREASURY_ID"
info "  Capability Vault: $CAP_VAULT_ID"
info "  Charter:          $CHARTER_ID"
info "  Emergency Freeze: $FREEZE_ID"

# ── Write shared outputs ─────────────────────────────────────────────────────
cat > "$SHARED_DIR/.env.armature" <<EOF
ARMATURE_PACKAGE_ID=$PACKAGE_ID
TEST_DAO_ID=$DAO_ID
TEST_TREASURY_ID=$TREASURY_ID
TEST_CAP_VAULT_ID=$CAP_VAULT_ID
TEST_CHARTER_ID=$CHARTER_ID
TEST_FREEZE_ID=$FREEZE_ID
USER1_ADDRESS=$ADDR
USER2_ADDRESS=$USER2_ADDRESS
USER3_ADDRESS=$USER3_ADDRESS
EOF

# Write UI-ready env file
cat > "$SHARED_DIR/ui.env.local" <<EOF
# Generated by docker/scripts/deploy-armature.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Mounted into the UI container as .env.local

VITE_NETWORK=localnet
VITE_PACKAGE_ID=$PACKAGE_ID
VITE_PROPOSALS_PACKAGE_ID=$PACKAGE_ID
VITE_TEST_DAO_ID=$DAO_ID
VITE_TEST_TREASURY_ID=$TREASURY_ID
VITE_TEST_CAP_VAULT_ID=$CAP_VAULT_ID
VITE_TEST_CHARTER_ID=$CHARTER_ID
VITE_TEST_FREEZE_ID=$FREEZE_ID
EOF

ok "Deployment complete! Artifacts in $SHARED_DIR/"
