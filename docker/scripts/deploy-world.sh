#!/usr/bin/env bash
# deploy-world.sh — Deploy world-contracts to the Sui localnet.
#
# Expects world-contracts to be mounted at /workspace/world-contracts
# (clone happens on the host via Makefile, not inside Docker).
#
# Expected env vars:
#   SUI_RPC_URL          — Sui JSON-RPC endpoint (e.g. http://sui-localnet:9000)
#   GOVERNOR_PRIVATE_KEY — (optional) If empty, a new keypair is generated.
#
# Outputs:
#   /shared/world-deployment.json — deployed object IDs
#   /shared/.env.world            — env vars for downstream services
set -euo pipefail

SHARED_DIR="/shared"
WORLD_DIR="/workspace/world-contracts"
RPC="${SUI_RPC_URL:-http://sui-localnet:9000}"

mkdir -p "$SHARED_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { echo -e "\033[1;34m[world]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[world]\033[0m $*"; }
err()   { echo -e "\033[1;31m[world]\033[0m $*" >&2; }

# ── Verify world-contracts is mounted ────────────────────────────────────────
if [ ! -f "$WORLD_DIR/package.json" ]; then
  err "world-contracts not found at $WORLD_DIR"
  err "Run 'make dev-deps' on the host first to clone it."
  exit 1
fi
ok "world-contracts found at $WORLD_DIR"

cd "$WORLD_DIR"

# ── Set up Sui client ────────────────────────────────────────────────────────
info "Configuring Sui client for localnet..."
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

# ── Generate or import governor key ──────────────────────────────────────────
if [ -n "${GOVERNOR_PRIVATE_KEY:-}" ]; then
  info "Importing provided GOVERNOR_PRIVATE_KEY..."
  GOVERNOR_ADDRESS=$(sui keytool import "$GOVERNOR_PRIVATE_KEY" ed25519 2>&1 | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
else
  info "No GOVERNOR_PRIVATE_KEY set — generating new keypair..."
  KEY_OUTPUT=$(sui client new-address ed25519 --json 2>/dev/null)
  GOVERNOR_ADDRESS=$(echo "$KEY_OUTPUT" | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).address")
  GOVERNOR_PRIVATE_KEY=$(sui keytool export --key-identity "$GOVERNOR_ADDRESS" --json 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).exportedPrivateKey")
  ok "Generated governor: $GOVERNOR_ADDRESS"
fi

sui client switch --address "$GOVERNOR_ADDRESS" 2>/dev/null
ok "Active address: $GOVERNOR_ADDRESS"

# ── Fund governor via faucet ─────────────────────────────────────────────────
info "Requesting SUI from faucet..."
FAUCET_URL="${SUI_FAUCET_URL:-http://sui-localnet:9123}"
for i in 1 2 3; do
  curl -sf -X POST "$FAUCET_URL/gas" \
    -H 'Content-Type: application/json' \
    -d "{\"FixedAmountRequest\":{\"recipient\":\"$GOVERNOR_ADDRESS\"}}" \
    > /dev/null 2>&1 || true
  sleep 1
done
sleep 2
ok "Faucet requests sent"

# ── Write world-contracts .env ───────────────────────────────────────────────
cat > "$WORLD_DIR/.env" <<ENVEOF
SUI_NETWORK=localnet
SUI_RPC_URL=$RPC
GOVERNOR_PRIVATE_KEY=$GOVERNOR_PRIVATE_KEY
ADMIN_PRIVATE_KEY=$GOVERNOR_PRIVATE_KEY
ADMIN_ADDRESS=$GOVERNOR_ADDRESS
SPONSOR_ADDRESSES=$GOVERNOR_ADDRESS
TENANT=${TENANT:-dev}
FUEL_TYPE_IDS=${FUEL_TYPE_IDS:-78437,78515,78516,84868,88319,88335}
FUEL_EFFICIENCIES=${FUEL_EFFICIENCIES:-90,80,40,40,15,10}
ASSEMBLY_TYPE_IDS=${ASSEMBLY_TYPE_IDS:-77917,84556,84955,87119,87120,88063,88064,88067,88068,88069,88070,88071,88082,88083,90184,91978,92279,92401,92404}
ENERGY_REQUIRED_VALUES=${ENERGY_REQUIRED_VALUES:-500,10,950,50,250,100,200,100,200,300,50,100,1,100,10,20,40}
GATE_TYPE_IDS=${GATE_TYPE_IDS:-88086,84955}
MAX_DISTANCES=${MAX_DISTANCES:-520340175991902420,1040680351983804840}
ENVEOF

# ── Install deps & deploy ───────────────────────────────────────────────────
info "Installing world-contracts dependencies..."
pnpm install --no-frozen-lockfile

info "Deploying world contracts..."
chmod +x ./scripts/*.sh
./scripts/deploy-world.sh localnet

info "Configuring world..."
./scripts/configure-world.sh localnet

# ── Extract deployment info ──────────────────────────────────────────────────
DEPLOY_DIR="$WORLD_DIR/deployments/localnet"
WORLD_PACKAGE_ID="unknown"

# Copy all deployment JSON files to shared volume
for f in "$DEPLOY_DIR"/*.json; do
  [ -f "$f" ] && cp "$f" "$SHARED_DIR/"
done

# Extract package ID — try world_package.json first, then extracted-object-ids.json
if [ -f "$DEPLOY_DIR/world_package.json" ]; then
  cp "$DEPLOY_DIR/world_package.json" "$SHARED_DIR/world-deployment.json"
  WORLD_PACKAGE_ID=$(node -e "
    const d = JSON.parse(require('fs').readFileSync('$DEPLOY_DIR/world_package.json', 'utf8'));
    const pub = (d.objectChanges || []).find(c => c.type === 'published');
    process.stdout.write(pub?.packageId || d.packageId || 'unknown');
  ")
fi

if [ "$WORLD_PACKAGE_ID" = "unknown" ] && [ -f "$DEPLOY_DIR/extracted-object-ids.json" ]; then
  WORLD_PACKAGE_ID=$(node -e "
    const d = JSON.parse(require('fs').readFileSync('$DEPLOY_DIR/extracted-object-ids.json', 'utf8'));
    process.stdout.write(d.packageId || d.WORLD_PACKAGE_ID || 'unknown');
  ")
fi

# Write shared env for downstream services
cat > "$SHARED_DIR/.env.world" <<EOF
WORLD_PACKAGE_ID=$WORLD_PACKAGE_ID
GOVERNOR_ADDRESS=$GOVERNOR_ADDRESS
GOVERNOR_PRIVATE_KEY=$GOVERNOR_PRIVATE_KEY
SUI_RPC_URL=$RPC
EOF

ok "World deployed! Package ID: $WORLD_PACKAGE_ID"
ok "Artifacts written to $SHARED_DIR/"
