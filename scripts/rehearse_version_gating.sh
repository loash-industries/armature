#!/usr/bin/env bash
# rehearse_version_gating.sh — localnet rehearsal of version gating (ARMATURE-45).
#
# Publishes armature_framework v1 to a throwaway localnet, links a dependent to
# it, then runs a routine upgrade (VERSION 2, MIN_SUPPORTED 1) and a security
# upgrade (VERSION 3, MIN_SUPPORTED 3) with a partial sweep, and checks:
#
#   routine:  v1 calls and v1-linked dependents keep working on every object;
#             floors don't move.
#   security: on the swept OU, v1, v2 and the v1-linked dependent abort with
#             version::EVersionRetired; on the unswept OU they still work; v3
#             works on both and raises the unswept OU's floor as it goes.
#
# Dependents linked to v1: `armature_proposals` (published, to show it links
# and publishes against v1) and a one-function probe package whose call reaches
# a gated framework function, so the rehearsal can observe old linkage at run
# time. armature_world_bridge needs world-contracts on localnet and is not
# published here; old linkage behaves the same for any dependent.
#
# Everything runs in a temp dir with its own client config, so your ~/.sui
# config and the repo's packages are not touched.
#
# Usage: scripts/rehearse_version_gating.sh [--keep]   (--keep leaves the
# localnet running and the temp dir in place)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEEP=false
[[ "${1:-}" == "--keep" ]] && KEEP=true
WORK=$(mktemp -d)
CFG="$WORK/client.yaml"
RPC=http://127.0.0.1:9000
LOCALNET_PID=""

info() { echo -e "\033[1;34m[info]\033[0m $*"; }
pass() { echo -e "\033[1;32m[pass]\033[0m $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m $*" >&2; FAILED=1; }
FAILED=0

cleanup() {
  if ! $KEEP; then
    [[ -n "$LOCALNET_PID" ]] && kill "$LOCALNET_PID" 2>/dev/null || true
    rm -rf "$WORK"
  else
    info "kept: localnet pid $LOCALNET_PID, work dir $WORK"
  fi
}
trap cleanup EXIT

S() { sui client --client.config "$CFG" "$@"; }

# --- localnet + client ------------------------------------------------------

if curl -s -o /dev/null "$RPC"; then
  echo "Something is already listening on $RPC; stop it first." >&2
  exit 1
fi
info "starting localnet (logs: $WORK/localnet.log)"
(cd "$WORK" && exec sui start --with-faucet --force-regenesis) >"$WORK/localnet.log" 2>&1 </dev/null &
LOCALNET_PID=$!
for _ in $(seq 1 90); do
  curl -s -X POST -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"sui_getLatestCheckpointSequenceNumber"}' "$RPC" \
    | grep -q result && break
  sleep 1
done

S -y envs >/dev/null 2>&1 || true
S new-env --alias localnet --rpc "$RPC" >/dev/null 2>&1 || true
S switch --env localnet >/dev/null
ADDR=$(S active-address)
for _ in $(seq 1 30); do
  S faucet >/dev/null 2>&1 && break
  sleep 1
done
sleep 3
CHAIN=$(S chain-identifier)
info "localnet chain $CHAIN, sender $ADDR"

# --- workspace copies ---------------------------------------------------------

add_env() { # add `localnet = "<chain>"` to a copied Move.toml
  python3 - "$1" "$CHAIN" <<'PY'
import sys, re
p, chain = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace('env = "testnet_stillness"', 'env = "localnet"')
s = s.replace('[environments]\n', f'[environments]\nlocalnet = "{chain}"\n', 1)
open(p, 'w').write(s)
PY
}

cp -R "$ROOT/packages/armature_framework" "$WORK/armature_framework"
cp -R "$ROOT/packages/armature_proposals" "$WORK/armature_proposals"
rm -rf "$WORK"/armature_*/build "$WORK"/armature_*/Published.toml "$WORK"/armature_*/Move.lock
add_env "$WORK/armature_framework/Move.toml"
add_env "$WORK/armature_proposals/Move.toml"
mkdir -p "$WORK/probe/sources"
cat >"$WORK/probe/Move.toml" <<EOF
[package]
name = "vg_probe"
edition = "2024"

[dependencies]
armature = { local = "../armature_framework" }

[environments]
localnet = "$CHAIN"
EOF
cat >"$WORK/probe/sources/probe.move" <<'EOF'
/// A dependent linked to whatever framework version it was published against.
module vg_probe::probe;

use armature::ou::OU;

public fun rotate(ou: &mut OU, ctx: &TxContext) {
    armature::encrypted_entry::rotate_encryption_epoch(ou, ctx)
}
EOF

PUB="$WORK/pub.toml"
VERSION_FILE="$WORK/armature_framework/sources/version.move"
set_version() { # set_version <VERSION> <MIN_SUPPORTED>
  python3 - "$VERSION_FILE" "$1" "$2" <<'PY'
import sys, re
p, v, m = sys.argv[1:]
s = open(p).read()
s = re.sub(r"const VERSION: u64 = \d+;", f"const VERSION: u64 = {v};", s)
s = re.sub(r"const MIN_SUPPORTED: u64 = \d+;", f"const MIN_SUPPORTED: u64 = {m};", s)
open(p, 'w').write(s)
PY
}

json() { node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const j=JSON.parse(d);console.log(eval(process.argv[1]))})" "$1"; }

publish() { # publish <dir> -> prints the JSON result
  S test-publish "$1" --build-env localnet --pubfile-path "$PUB" --gas-budget 2000000000 --json 2>/dev/null
}

# --- v1 -----------------------------------------------------------------------

info "publishing armature_framework v1"
set_version 1 1
OUT=$(publish "$WORK/armature_framework")
FW1=$(echo "$OUT" | json "j.objectChanges.find(c=>c.type==='published').packageId")
CAP=$(echo "$OUT" | json "j.objectChanges.find(c=>c.objectType&&c.objectType.endsWith('::package::UpgradeCap')).objectId")
info "framework v1 $FW1 (UpgradeCap $CAP)"

OUT=$(publish "$WORK/probe")
PROBE=$(echo "$OUT" | json "j.objectChanges.find(c=>c.type==='published').packageId")
info "probe linked to v1: $PROBE"
OUT=$(publish "$WORK/armature_proposals")
PROPS=$(echo "$OUT" | json "j.objectChanges.find(c=>c.type==='published').packageId")
info "armature_proposals linked to v1: $PROPS"

new_ou() { # new_ou <name> -> OU id (created through v1)
  S ptb --move-call "$FW1::governance::init_board" "vector[@$ADDR]" --assign init \
    --move-call "$FW1::ou::create" init "\"$1\"" '"u"' --gas-budget 500000000 --json 2>/dev/null \
    | json "j.objectChanges.find(c=>c.type==='created'&&c.objectType.endsWith('::ou::OU')).objectId"
}
OU_A=$(new_ou A)
OU_B=$(new_ou B)
info "OU A $OU_A, OU B $OU_B"

floor() { # the object's min_version, wherever the CLI's JSON puts its fields
  S object "$1" --json 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
    const find=o=>{if(o&&typeof o==='object'){if('min_version' in o)return o.min_version;for(const v of Object.values(o)){const r=find(v);if(r!==undefined)return r}}};
    console.log(String(find(JSON.parse(d))))})"
}

call() { # call <label> <expect ok|retired> <package> <module> <function> <ou>
  local label=$1 expect=$2 out status
  out=$(S ptb --move-call "$3::$4::$5" "@$6" --gas-budget 200000000 --json 2>&1 || true)
  if echo "$out" | grep -q '"status": "success"'; then
    status=ok
  elif echo "$out" | grep -q "::version::assert_supported' at instruction" && echo "$out" | grep -q "with code 0"; then
    status=retired
  else
    echo "$out" >"$WORK/unexpected-$(echo "$label" | tr -c 'a-zA-Z0-9' '_').log"
    status="other: $(echo "$out" | grep -m1 -iE 'abort|error' | cut -c1-220 || true)"
  fi
  if [[ "$status" == "$expect" ]]; then pass "$label → $status"; else fail "$label → $status (expected $expect)"; fi
}

expect_floor() { # expect_floor <label> <ou> <floor>
  local f; f=$(floor "$2")
  if [[ "$f" == "$3" ]]; then pass "$1 floor = $f"; else fail "$1 floor = $f (expected $3)"; fi
}

echo; info "== v1"
call "v1 rotate on A" ok "$FW1" encrypted_entry rotate_encryption_epoch "$OU_A"
call "v1-linked probe on A" ok "$PROBE" probe rotate "$OU_A"
expect_floor "A" "$OU_A" 1

# --- routine upgrade ------------------------------------------------------------

echo; info "== routine upgrade: VERSION 2, MIN_SUPPORTED 1"
set_version 2 1
OUT=$(S test-upgrade "$WORK/armature_framework" --upgrade-capability "$CAP" --build-env localnet \
  --pubfile-path "$PUB" --gas-budget 2000000000 --json 2>/dev/null)
FW2=$(echo "$OUT" | json "j.objectChanges.find(c=>c.type==='published').packageId")
info "framework v2 $FW2"
call "v1 rotate on A" ok "$FW1" encrypted_entry rotate_encryption_epoch "$OU_A"
call "v2 rotate on A" ok "$FW2" encrypted_entry rotate_encryption_epoch "$OU_A"
call "v1-linked probe on A" ok "$PROBE" probe rotate "$OU_A"
call "v1-linked probe on B" ok "$PROBE" probe rotate "$OU_B"
expect_floor "A after v2 &mut use" "$OU_A" 1

# --- security upgrade -------------------------------------------------------------

echo; info "== security upgrade: VERSION 3, MIN_SUPPORTED 3, sweep A only"
set_version 3 3
OUT=$(S test-upgrade "$WORK/armature_framework" --upgrade-capability "$CAP" --build-env localnet \
  --pubfile-path "$PUB" --gas-budget 2000000000 --json 2>/dev/null)
FW3=$(echo "$OUT" | json "j.objectChanges.find(c=>c.type==='published').packageId")
info "framework v3 $FW3"
OUT=$(S ptb --move-call "$FW3::ou::enforce_version" "@$OU_A" --gas-budget 200000000 --json 2>/dev/null)
if echo "$OUT" | grep -q 'VersionFloorRaised'; then pass "sweep: enforce_version on A emits VersionFloorRaised"; else fail "sweep: no VersionFloorRaised event"; fi
expect_floor "A after sweep" "$OU_A" 3
expect_floor "B (unswept)" "$OU_B" 1

call "v1 rotate on swept A" retired "$FW1" encrypted_entry rotate_encryption_epoch "$OU_A"
call "v2 rotate on swept A" retired "$FW2" encrypted_entry rotate_encryption_epoch "$OU_A"
call "v1-linked probe on swept A" retired "$PROBE" probe rotate "$OU_A"
call "v1 rotate on unswept B" ok "$FW1" encrypted_entry rotate_encryption_epoch "$OU_B"
call "v1-linked probe on unswept B" ok "$PROBE" probe rotate "$OU_B"
call "v3 rotate on swept A" ok "$FW3" encrypted_entry rotate_encryption_epoch "$OU_A"
call "v3 rotate on unswept B" ok "$FW3" encrypted_entry rotate_encryption_epoch "$OU_B"
expect_floor "B after v3 &mut use" "$OU_B" 3
call "v1 rotate on B after v3 use" retired "$FW1" encrypted_entry rotate_encryption_epoch "$OU_B"

echo
if [[ $FAILED -eq 0 ]]; then
  pass "version gating rehearsal passed"
else
  fail "version gating rehearsal FAILED"
fi
exit $FAILED
