#!/usr/bin/env bash
# localnet-setup.sh — Publish packages, create test DAO, output .env.local
#
# Usage:
#   ./scripts/localnet-setup.sh          # full setup
#   ./scripts/localnet-setup.sh --skip-localnet  # skip starting localnet
#
# Prerequisites:
#   - sui CLI installed (sui --version)
#   - node (for JSON parsing)
#   - Localnet running or --skip-localnet not passed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/ui/.env.local"
FRAMEWORK_DIR="$ROOT_DIR/packages/armature_framework"
PROPOSALS_DIR="$ROOT_DIR/packages/armature_proposals"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

SKIP_LOCALNET=false
for arg in "$@"; do
  case "$arg" in
    --skip-localnet) SKIP_LOCALNET=true ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m   $*"; }
err()   { echo -e "\033[1;31m[ERR]\033[0m  $*" >&2; }
step()  { echo -e "\n\033[1;33m==> $*\033[0m"; }

# Cross-platform JSON field extractor (works on Windows/MINGW and Unix)
# Usage: json_get <json_string> <dot.separated.path>
json_get() {
  local json_file="$TMP_DIR/json_in.json"
  printf '%s' "$1" > "$json_file"
  node -p "
    const d = JSON.parse(require('fs').readFileSync('${json_file//\\/\\\\}', 'utf8'));
    const keys = '${2}'.split('.');
    let v = d;
    for (const k of keys) {
      if (v == null) break;
      v = Array.isArray(v) ? v[parseInt(k)] : v[k];
    }
    String(v ?? '');
  "
}

# Parse piped JSON from a file (for large outputs like publish results)
# Usage: json_get_file <file_path> <js_expression using 'd' as data>
json_get_file() {
  node -p "
    const d = JSON.parse(require('fs').readFileSync('${1//\\/\\\\}', 'utf8'));
    ${2}
  "
}

# ---------------------------------------------------------------------------
# Step 1: Check prerequisites
# ---------------------------------------------------------------------------

step "Checking prerequisites"

if ! command -v sui &>/dev/null; then
  err "sui CLI not found. Install from https://docs.sui.io/guides/developer/getting-started/sui-install"
  exit 1
fi
ok "sui CLI: $(sui --version 2>&1)"

if ! command -v node &>/dev/null; then
  err "node not found. Required for JSON parsing."
  exit 1
fi
ok "node: $(node --version)"

# ---------------------------------------------------------------------------
# Step 2: Ensure localnet is running
# ---------------------------------------------------------------------------

step "Checking localnet"

if [ "$SKIP_LOCALNET" = false ]; then
  # Check if localnet env exists
  ENVS_JSON=$(sui client envs --json 2>/dev/null || echo "[]")
  HAS_LOCALNET=$(node -p "
    try {
      const d = JSON.parse('$(echo "$ENVS_JSON" | tr -d '\n' | sed "s/'/\\\\'/g")');
      const arr = Array.isArray(d[0]) ? d[0] : d;
      arr.some(e => e.alias === 'localnet');
    } catch { false; }
  ")

  if [ "$HAS_LOCALNET" = "true" ]; then
    info "localnet env already configured"
  else
    info "Adding localnet env..."
    sui client new-env --alias localnet --rpc http://127.0.0.1:9000 2>/dev/null || true
  fi

  sui client switch --env localnet 2>/dev/null || true

  # Test connectivity
  if ! sui client gas --json &>/dev/null; then
    err "Cannot connect to localnet at http://127.0.0.1:9000"
    err "Start it with: sui start --with-faucet --force-regenesis"
    exit 1
  fi
  ok "localnet is reachable"
else
  info "Skipping localnet check (--skip-localnet)"
fi

# ---------------------------------------------------------------------------
# Step 3: Create and fund test wallets
# ---------------------------------------------------------------------------

step "Setting up test wallets"

ACTIVE_ADDRESS=$(sui client active-address 2>/dev/null)
ok "Active address (User 1 / Creator): $ACTIVE_ADDRESS"

# Export the active address private key
EXPORT_OUT="$TMP_DIR/export.json"
sui keytool export --key-identity "$ACTIVE_ADDRESS" --json > "$EXPORT_OUT" 2>/dev/null || echo "{}" > "$EXPORT_OUT"
WALLET_KEY_1=$(json_get_file "$EXPORT_OUT" "d.exportedPrivateKey || ''" 2>/dev/null || echo "")
if [ -z "$WALLET_KEY_1" ] || [ "$WALLET_KEY_1" = "undefined" ]; then
  WALLET_KEY_1=""
  info "Could not export key for active address — will use address only"
fi

# Create User 2
USER2_FILE="$TMP_DIR/user2.json"
sui client new-address ed25519 --json > "$USER2_FILE" 2>/dev/null
USER2_ADDRESS=$(json_get_file "$USER2_FILE" "d.address || ''")
USER2_KEY=$(json_get_file "$USER2_FILE" "d.secretKey || d.privateKey || ''" 2>/dev/null || echo "")
ok "User 2 (Board member): $USER2_ADDRESS"

# Create User 3
USER3_FILE="$TMP_DIR/user3.json"
sui client new-address ed25519 --json > "$USER3_FILE" 2>/dev/null
USER3_ADDRESS=$(json_get_file "$USER3_FILE" "d.address || ''")
USER3_KEY=$(json_get_file "$USER3_FILE" "d.secretKey || d.privateKey || ''" 2>/dev/null || echo "")
ok "User 3 (Board member): $USER3_ADDRESS"

# Fund all wallets via faucet
info "Funding wallets via faucet..."
for addr in "$ACTIVE_ADDRESS" "$USER2_ADDRESS" "$USER3_ADDRESS"; do
  sui client faucet --address "$addr" 2>/dev/null || true
done
sleep 2
ok "Wallets funded"

# ---------------------------------------------------------------------------
# Step 4: Publish armature_framework
# ---------------------------------------------------------------------------

step "Publishing armature_framework"

FW_FILE="$TMP_DIR/fw_publish.json"
sui client publish "$FRAMEWORK_DIR" --gas-budget 500000000 --json --skip-dependency-verification > "$FW_FILE" 2>/dev/null

FRAMEWORK_PACKAGE_ID=$(json_get_file "$FW_FILE" "
  const pub = d.objectChanges.find(c => c.type === 'published');
  pub ? pub.packageId : 'PUBLISH_FAILED'
")

if [ "$FRAMEWORK_PACKAGE_ID" = "PUBLISH_FAILED" ] || [ -z "$FRAMEWORK_PACKAGE_ID" ]; then
  err "Failed to publish armature_framework. Check sui client output:"
  cat "$FW_FILE"
  exit 1
fi
ok "armature_framework published: $FRAMEWORK_PACKAGE_ID"

# ---------------------------------------------------------------------------
# Step 5: Publish armature_proposals
# ---------------------------------------------------------------------------

step "Publishing armature_proposals"

PROP_FILE="$TMP_DIR/prop_publish.json"
sui client publish "$PROPOSALS_DIR" --gas-budget 500000000 --json --skip-dependency-verification > "$PROP_FILE" 2>/dev/null

PROPOSALS_PACKAGE_ID=$(json_get_file "$PROP_FILE" "
  const pub = d.objectChanges.find(c => c.type === 'published');
  pub ? pub.packageId : 'PUBLISH_FAILED'
")

if [ "$PROPOSALS_PACKAGE_ID" = "PUBLISH_FAILED" ] || [ -z "$PROPOSALS_PACKAGE_ID" ]; then
  err "Failed to publish armature_proposals. Check sui client output:"
  cat "$PROP_FILE"
  exit 1
fi
ok "armature_proposals published: $PROPOSALS_PACKAGE_ID"

# ---------------------------------------------------------------------------
# Step 6: Create test DAO
# ---------------------------------------------------------------------------

step "Creating test DAO"

DAO_FILE="$TMP_DIR/dao_create.json"
sui client ptb \
  --make-move-vec "<address>" "[@${ACTIVE_ADDRESS}, @${USER2_ADDRESS}, @${USER3_ADDRESS}]" \
  --assign members \
  --move-call "${FRAMEWORK_PACKAGE_ID}::governance::init_board" members \
  --assign gov_init \
  --move-call "${FRAMEWORK_PACKAGE_ID}::dao::create" gov_init '"Test DAO"' '"A test DAO for local e2e testing"' '"https://example.com/dao-logo.png"' \
  --gas-budget 100000000 \
  --json > "$DAO_FILE" 2>/dev/null

# Parse DAOCreated event
DAO_ID=$(json_get_file "$DAO_FILE" "
  const evt = d.events.find(e => e.type.includes('::dao::DAOCreated'));
  evt ? evt.parsedJson.dao_id : 'EVENT_NOT_FOUND'
")

if [ "$DAO_ID" = "EVENT_NOT_FOUND" ] || [ -z "$DAO_ID" ]; then
  err "DAOCreated event not found in transaction output:"
  cat "$DAO_FILE"
  exit 1
fi

TREASURY_ID=$(json_get_file "$DAO_FILE" "d.events.find(e=>e.type.includes('::dao::DAOCreated')).parsedJson.treasury_id")
CAP_VAULT_ID=$(json_get_file "$DAO_FILE" "d.events.find(e=>e.type.includes('::dao::DAOCreated')).parsedJson.capability_vault_id")
CHARTER_ID=$(json_get_file "$DAO_FILE" "d.events.find(e=>e.type.includes('::dao::DAOCreated')).parsedJson.charter_id")
FREEZE_ID=$(json_get_file "$DAO_FILE" "d.events.find(e=>e.type.includes('::dao::DAOCreated')).parsedJson.emergency_freeze_id")

ok "DAO created: $DAO_ID"
info "  Treasury:         $TREASURY_ID"
info "  Capability Vault: $CAP_VAULT_ID"
info "  Charter:          $CHARTER_ID"
info "  Emergency Freeze: $FREEZE_ID"

# ---------------------------------------------------------------------------
# Step 7: Write .env.local
# ---------------------------------------------------------------------------

step "Writing $ENV_FILE"

cat > "$ENV_FILE" <<ENVEOF
# Generated by scripts/localnet-setup.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Do not commit this file.

# Network
VITE_NETWORK=localnet

# Package IDs (update after each publish/upgrade)
VITE_PACKAGE_ID=$FRAMEWORK_PACKAGE_ID
VITE_PROPOSALS_PACKAGE_ID=$PROPOSALS_PACKAGE_ID

# Test wallets (suiprivkey format — use with WalletSignerProvider)
VITE_WALLET_KEY_1=$WALLET_KEY_1
VITE_WALLET_KEY_2=$USER2_KEY
VITE_WALLET_KEY_3=$USER3_KEY

# Test DAO object IDs
VITE_TEST_DAO_ID=$DAO_ID
VITE_TEST_TREASURY_ID=$TREASURY_ID
VITE_TEST_CAP_VAULT_ID=$CAP_VAULT_ID
VITE_TEST_CHARTER_ID=$CHARTER_ID
VITE_TEST_FREEZE_ID=$FREEZE_ID

# Test wallet addresses (for reference)
# User 1 (creator): $ACTIVE_ADDRESS
# User 2 (board):   $USER2_ADDRESS
# User 3 (board):   $USER3_ADDRESS
ENVEOF

ok "Wrote $ENV_FILE"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

step "Setup complete!"
echo ""
info "To start the UI:"
info "  cd ui && npm run dev"
echo ""
info "Test wallets:"
info "  User 1 (creator): $ACTIVE_ADDRESS"
info "  User 2 (board):   $USER2_ADDRESS"
info "  User 3 (board):   $USER3_ADDRESS"
echo ""
info "DAO ID: $DAO_ID"
echo ""
