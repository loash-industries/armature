#!/usr/bin/env bash
# upgrade-testnet-stillness.sh — Upgrade selected armature packages on testnet_stillness
# and sync the new published-at IDs into triex-app-api/src/constants/tenants.ts.
#
# By default only upgrades the packages you explicitly select via flags.
# Run with --all to upgrade everything (e.g. after a framework change).
#
# Usage:
#   ./scripts/upgrade-testnet-stillness.sh --trading              # most common: new trading modules
#   ./scripts/upgrade-testnet-stillness.sh --framework --proposals --trading
#   ./scripts/upgrade-testnet-stillness.sh --all
#   ./scripts/upgrade-testnet-stillness.sh --all --dry-run        # preview only
#
# Prerequisites:
#   - sui CLI installed; active env pointing to Sui testnet
#   - Active address owns the upgrade capabilities for selected packages
#   - node installed (for JSON parsing)
#   - Sibling repos: ../armature-trading, ../armature-vault
#   - triex-app-api at: ../../triex/triex/triex-app-api

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARMATURE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(cd "$ARMATURE_DIR/.." && pwd)"

FRAMEWORK_DIR="$ARMATURE_DIR/packages/armature_framework"
PROPOSALS_DIR="$ARMATURE_DIR/packages/armature_proposals"
WORLD_BRIDGE_DIR="$ARMATURE_DIR/packages/armature_world_bridge"
TRADING_DIR="$PARENT_DIR/armature-trading/packages/armature_trading"
VAULT_DIR="$PARENT_DIR/armature-vault/packages/armature_vault"
TENANTS_FILE="$(cd "$PARENT_DIR/../../triex/triex/triex-app-api" && pwd)/src/constants/tenants.ts"

ENV_NAME="testnet_stillness"
GAS_BUDGET=500000000

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ── Upgrade capabilities (testnet_stillness) ──────────────────────────────────

FRAMEWORK_CAP="0x660bab2695e427257d37210473117cd290dba13c615d8b69db824193bbc6257a"
PROPOSALS_CAP="0xd25ef44f645a8b4c491c351606860ac2bde9f8bbe8d4c1df4392b3d9cf47f33c"
WORLD_BRIDGE_CAP="0xbc250d5942222770e6641ac8b9c508e68788fede9e024bbca5a14df0430a3e11"
TRADING_CAP="0x34e2f2e9cbd4bbdfbdd1a2b53728a8c2ba7042244bd5535a488826a11dfa71cc"
VAULT_CAP="0xf0d0b626402dedc485a57bc279c4dc9fa0593defa0ab0fd430b3493665ab06f7"

# ── Flags ─────────────────────────────────────────────────────────────────────

DO_FRAMEWORK=false
DO_PROPOSALS=false
DO_WORLD_BRIDGE=false
DO_TRADING=false
DO_VAULT=false
DRY_RUN=false

if [ $# -eq 0 ]; then
  echo "Usage: $0 [--framework] [--proposals] [--world-bridge] [--trading] [--vault] [--all] [--dry-run]"
  echo ""
  echo "Select which packages to upgrade. Most common:"
  echo "  $0 --trading              # added new trading proposal modules"
  echo "  $0 --framework --proposals --trading  # framework-level changes"
  echo "  $0 --all --dry-run        # preview a full upgrade"
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    --framework)   DO_FRAMEWORK=true ;;
    --proposals)   DO_PROPOSALS=true ;;
    --world-bridge) DO_WORLD_BRIDGE=true ;;
    --trading)     DO_TRADING=true ;;
    --vault)       DO_VAULT=true ;;
    --all)         DO_FRAMEWORK=true; DO_PROPOSALS=true; DO_WORLD_BRIDGE=true; DO_TRADING=true; DO_VAULT=true ;;
    --dry-run)     DRY_RUN=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { echo -e "\033[1;34m[armature]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[armature]\033[0m $*"; }
err()   { echo -e "\033[1;31m[armature]\033[0m $*" >&2; }
step()  { echo -e "\n\033[1;33m==> $*\033[0m"; }

toml_field() {
  local file="$1" env="$2" field="$3"
  node -e "
    const content = require('fs').readFileSync('$file', 'utf8');
    const lines = content.split('\n');
    let inSection = false;
    for (const line of lines) {
      if (line.trim() === '[published.$env]') { inSection = true; continue; }
      if (inSection && line.startsWith('[')) break;
      if (inSection) {
        const m = line.match(/^$field\s*=\s*\"([^\"]+)\"/);
        if (m) { process.stdout.write(m[1]); break; }
      }
    }
  "
}

parse_new_package_id() {
  local file="$1"
  node -e "
    const raw = require('fs').readFileSync('$file', 'utf8');
    const start = raw.indexOf('{');
    if (start === -1) { process.stdout.write(''); process.exit(0); }
    const d = JSON.parse(raw.slice(start));
    const pub = (d.objectChanges || []).find(c => c.type === 'published');
    process.stdout.write(pub ? pub.packageId : '');
  "
}

replace_in_tenants() {
  local old_id="$1" new_id="$2" label="$3"
  if [ "$old_id" = "$new_id" ]; then
    info "  $label: unchanged"
    return
  fi
  if [ "$DRY_RUN" = true ]; then
    info "  [dry-run] $label: $old_id → $new_id"
    return
  fi
  sed -i.bak "s|${old_id}|${new_id}|g" "$TENANTS_FILE"
  rm -f "${TENANTS_FILE}.bak"
  ok "  $label: $old_id → $new_id"
}

do_upgrade() {
  local label="$1" pkg_dir="$2" cap_id="$3"
  local out="$TMP_DIR/${label}.json"

  if [ "$DRY_RUN" = true ]; then
    info "  [dry-run] would upgrade $label" >&2
    # Return current published-at so summary shows no change
    toml_field "$pkg_dir/Published.toml" "$ENV_NAME" "published-at"
    return
  fi

  # This function is called inside $() so its stdout is captured as the return
  # value. All diagnostic output must go to stderr (>&2) to appear on screen.
  info "  Upgrading $label..." >&2
  sui client upgrade \
    --upgrade-capability "$cap_id" \
    --gas-budget "$GAS_BUDGET" \
    --skip-dependency-verification \
    --json \
    "$pkg_dir" > "$out" 2>&1 || true

  local new_id
  new_id=$(parse_new_package_id "$out")
  if [ -z "$new_id" ]; then
    err "Failed to upgrade $label — raw output:" >&2
    cat "$out" >&2
    exit 1
  fi

  ok "  $label → $new_id" >&2
  echo "$new_id"
}

# ── Preflight ─────────────────────────────────────────────────────────────────

step "Preflight"

command -v sui  &>/dev/null || { err "sui CLI not found"; exit 1; }
command -v node &>/dev/null || { err "node not found"; exit 1; }
[ -f "$TENANTS_FILE" ]      || { err "tenants.ts not found: $TENANTS_FILE"; exit 1; }

ACTIVE_ADDR=$(sui client active-address 2>/dev/null)
ACTIVE_ENV=$(sui client active-env 2>/dev/null)
ok "Address: $ACTIVE_ADDR  |  Env: $ACTIVE_ENV"

if [[ "$ACTIVE_ENV" != *"testnet"* ]]; then
  err "Active env '$ACTIVE_ENV' does not look like testnet"
  err "Switch with: sui client switch --env <testnet-alias>"
  exit 1
fi

$DRY_RUN && info "DRY RUN — no transactions or file writes"

# ── Warn if framework is being upgraded but dependents are not ────────────────

if $DO_FRAMEWORK; then
  SKIPPED=()
  $DO_PROPOSALS   || SKIPPED+=("--proposals")
  $DO_WORLD_BRIDGE || SKIPPED+=("--world-bridge")
  $DO_TRADING     || SKIPPED+=("--trading")
  $DO_VAULT       || SKIPPED+=("--vault")
  if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo ""
    echo "  WARNING: upgrading armature_framework but not: ${SKIPPED[*]}"
    echo "  Dependents that expose framework types in their public signatures"
    echo "  may need upgrading too. Press Enter to continue or Ctrl-C to abort."
    read -r
  fi
fi

# ── Snapshot current IDs ──────────────────────────────────────────────────────

step "Current published-at IDs"

OLD_FRAMEWORK=$(toml_field "$FRAMEWORK_DIR/Published.toml"   "$ENV_NAME" "published-at")
OLD_PROPOSALS=$(toml_field "$PROPOSALS_DIR/Published.toml"   "$ENV_NAME" "published-at")
OLD_WORLD_BRIDGE=$(toml_field "$WORLD_BRIDGE_DIR/Published.toml" "$ENV_NAME" "published-at")
OLD_TRADING=$(toml_field "$TRADING_DIR/Published.toml"       "$ENV_NAME" "published-at")
OLD_VAULT=$(toml_field "$VAULT_DIR/Published.toml"           "$ENV_NAME" "published-at")

$DO_FRAMEWORK   && info "  framework:    $OLD_FRAMEWORK"
$DO_PROPOSALS   && info "  proposals:    $OLD_PROPOSALS"
$DO_WORLD_BRIDGE && info "  world_bridge: $OLD_WORLD_BRIDGE"
$DO_TRADING     && info "  trading:      $OLD_TRADING"
$DO_VAULT       && info "  vault:        $OLD_VAULT"

# ── Upgrade (dependency-first: framework before its dependents) ───────────────

step "Upgrading packages"

NEW_FRAMEWORK="$OLD_FRAMEWORK"
NEW_PROPOSALS="$OLD_PROPOSALS"
NEW_WORLD_BRIDGE="$OLD_WORLD_BRIDGE"
NEW_TRADING="$OLD_TRADING"
NEW_VAULT="$OLD_VAULT"

$DO_FRAMEWORK   && NEW_FRAMEWORK=$(do_upgrade   "armature_framework"   "$FRAMEWORK_DIR"   "$FRAMEWORK_CAP")
$DO_PROPOSALS   && NEW_PROPOSALS=$(do_upgrade   "armature_proposals"   "$PROPOSALS_DIR"   "$PROPOSALS_CAP")
$DO_WORLD_BRIDGE && NEW_WORLD_BRIDGE=$(do_upgrade "armature_world_bridge" "$WORLD_BRIDGE_DIR" "$WORLD_BRIDGE_CAP")
$DO_VAULT       && NEW_VAULT=$(do_upgrade       "armature_vault"       "$VAULT_DIR"       "$VAULT_CAP")
$DO_TRADING     && NEW_TRADING=$(do_upgrade     "armature_trading"     "$TRADING_DIR"     "$TRADING_CAP")

# ── Sync tenants.ts ───────────────────────────────────────────────────────────

step "Syncing tenants.ts"

replace_in_tenants "$OLD_FRAMEWORK"    "$NEW_FRAMEWORK"    "armaturePackageId"
replace_in_tenants "$OLD_PROPOSALS"    "$NEW_PROPOSALS"    "armatureProposalsPackageId"
replace_in_tenants "$OLD_WORLD_BRIDGE" "$NEW_WORLD_BRIDGE" "armatureWorldBridgePackageId"
replace_in_tenants "$OLD_TRADING"      "$NEW_TRADING"      "armatureTradingPackageId"
replace_in_tenants "$OLD_VAULT"        "$NEW_VAULT"        "armatureVaultPackageId"

# ── Summary ───────────────────────────────────────────────────────────────────

step "Done${DRY_RUN:+ (dry run)}"

[ "$OLD_FRAMEWORK"    != "$NEW_FRAMEWORK"    ] && echo "  framework:    $OLD_FRAMEWORK → $NEW_FRAMEWORK"
[ "$OLD_PROPOSALS"    != "$NEW_PROPOSALS"    ] && echo "  proposals:    $OLD_PROPOSALS → $NEW_PROPOSALS"
[ "$OLD_WORLD_BRIDGE" != "$NEW_WORLD_BRIDGE" ] && echo "  world_bridge: $OLD_WORLD_BRIDGE → $NEW_WORLD_BRIDGE"
[ "$OLD_TRADING"      != "$NEW_TRADING"      ] && echo "  trading:      $OLD_TRADING → $NEW_TRADING"
[ "$OLD_VAULT"        != "$NEW_VAULT"        ] && echo "  vault:        $OLD_VAULT → $NEW_VAULT"

if [ "$DRY_RUN" = false ] && ( $DO_TRADING || $DO_FRAMEWORK ); then
  echo ""
  info "Existing DAOs may have stale trading type keys — use 'Enable Trading Types' in the UI."
fi
