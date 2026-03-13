#!/usr/bin/env node
/**
 * localnet-setup.mjs — Publish packages, create test DAO, output .env.local
 *
 * Usage:
 *   node scripts/localnet-setup.mjs                  # full setup
 *   node scripts/localnet-setup.mjs --skip-localnet   # skip localnet check
 *
 * Prerequisites:
 *   - sui CLI installed and on PATH
 *   - Localnet running (or pass --skip-localnet)
 */

import { execSync } from "node:child_process";
import { writeFileSync, unlinkSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const ENV_FILE = resolve(ROOT, "ui", ".env.local");
const PROPOSALS_DIR = resolve(ROOT, "packages", "armature_proposals");

const SKIP_LOCALNET = process.argv.includes("--skip-localnet");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const BLUE = "\x1b[1;34m";
const GREEN = "\x1b[1;32m";
const RED = "\x1b[1;31m";
const YELLOW = "\x1b[1;33m";
const RESET = "\x1b[0m";

function info(msg) { console.log(`${BLUE}[INFO]${RESET} ${msg}`); }
function ok(msg) { console.log(`${GREEN}[OK]${RESET}   ${msg}`); }
function err(msg) { console.error(`${RED}[ERR]${RESET}  ${msg}`); }
function step(msg) { console.log(`\n${YELLOW}==> ${msg}${RESET}`); }

function sui(args, { json = false, allowFailure = false } = {}) {
  const cmd = `sui ${args}${json ? " --json" : ""}`;
  try {
    const out = execSync(cmd, {
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 180_000,
    }).trim();
    if (json) return JSON.parse(out);
    return out;
  } catch (e) {
    if (allowFailure) return null;
    const stdout = e.stdout?.toString().trim() ?? "";
    if (json && stdout) {
      try { return JSON.parse(stdout); } catch {}
    }
    err(`Command failed: ${cmd}`);
    const stderr = e.stderr?.toString().trim();
    if (stderr) err(stderr);
    throw e;
  }
}

// ---------------------------------------------------------------------------
// Step 1: Check prerequisites
// ---------------------------------------------------------------------------

step("Checking prerequisites");

try {
  const version = execSync("sui --version", { encoding: "utf8" }).trim();
  ok(`sui CLI: ${version}`);
} catch {
  err("sui CLI not found. Install from https://docs.sui.io/guides/developer/getting-started/sui-install");
  process.exit(1);
}

ok(`node: ${process.version}`);

// ---------------------------------------------------------------------------
// Step 2: Ensure localnet is running
// ---------------------------------------------------------------------------

step("Checking localnet");

if (!SKIP_LOCALNET) {
  const envs = sui("client envs", { json: true, allowFailure: true });
  const envList = Array.isArray(envs?.[0]) ? envs[0] : (envs ?? []);
  const hasLocalnet = envList.some((e) => e.alias === "localnet");

  if (hasLocalnet) {
    info("localnet env already configured");
  } else {
    info("Adding localnet env...");
    sui("client new-env --alias localnet --rpc http://127.0.0.1:9000", { allowFailure: true });
  }

  sui("client switch --env localnet", { allowFailure: true });

  const gas = sui("client gas", { json: true, allowFailure: true });
  if (gas === null) {
    err("Cannot connect to localnet at http://127.0.0.1:9000");
    err("Start it with: sui start --with-faucet --force-regenesis");
    process.exit(1);
  }
  ok("localnet is reachable");
} else {
  info("Skipping localnet check (--skip-localnet)");
}

// ---------------------------------------------------------------------------
// Step 3: Create and fund test wallets
// ---------------------------------------------------------------------------

step("Setting up test wallets");

const activeAddress = sui("client active-address").trim();
ok(`Active address (User 1 / Creator): ${activeAddress}`);

// Export active key
let walletKey1 = "";
try {
  const exportResult = sui(`keytool export --key-identity ${activeAddress}`, { json: true });
  walletKey1 = exportResult?.exportedPrivateKey ?? "";
} catch {
  info("Could not export key for active address");
}

// Create User 2
const user2 = sui("client new-address ed25519", { json: true });
const user2Address = user2.address;
const user2Mnemonic = user2.recoveryPhrase ?? "";
ok(`User 2 (Board member): ${user2Address}`);

// Create User 3
const user3 = sui("client new-address ed25519", { json: true });
const user3Address = user3.address;
const user3Mnemonic = user3.recoveryPhrase ?? "";
ok(`User 3 (Board member): ${user3Address}`);

// Fund via faucet
info("Funding wallets via faucet...");
for (const addr of [activeAddress, user2Address, user3Address]) {
  sui(`client faucet --address ${addr}`, { allowFailure: true });
}

info("Waiting for faucet transactions...");
await new Promise((r) => setTimeout(r, 3000));
ok("Wallets funded");

// ---------------------------------------------------------------------------
// Step 4: Publish all packages
// ---------------------------------------------------------------------------

step("Publishing armature packages");

// Clean ephemeral publication tracking so re-runs work
for (const dir of [
  resolve(ROOT, "packages", "armature_framework"),
  PROPOSALS_DIR,
]) {
  const eph = resolve(dir, ".ephemeral.toml");
  if (existsSync(eph)) unlinkSync(eph);
}

// Publish armature_proposals with --with-unpublished-dependencies bundles
// both armature_framework and armature_proposals into a single package ID.
const ephFile = resolve(PROPOSALS_DIR, ".ephemeral.toml");
const pubResult = sui(
  `client test-publish "${PROPOSALS_DIR}" --gas-budget 500000000 --skip-dependency-verification --with-unpublished-dependencies --build-env localnet --pubfile-path "${ephFile}"`,
  { json: true },
);

const published = pubResult.objectChanges?.find((c) => c.type === "published");
if (!published) {
  err("Failed to publish packages:");
  console.error(JSON.stringify(pubResult, null, 2));
  process.exit(1);
}
const PACKAGE_ID = published.packageId;
const moduleCount = published.modules?.length ?? 0;
ok(`Packages published: ${PACKAGE_ID} (${moduleCount} modules)`);

// ---------------------------------------------------------------------------
// Step 5: Create test DAO
// ---------------------------------------------------------------------------

step("Creating test DAO");

const daoResult = sui(
  `client ptb` +
  ` --make-move-vec "<address>" "[@${activeAddress}, @${user2Address}, @${user3Address}]"` +
  ` --assign members` +
  ` --move-call ${PACKAGE_ID}::governance::init_board members` +
  ` --assign gov_init` +
  ` --move-call ${PACKAGE_ID}::dao::create gov_init '"Test DAO"' '"A test DAO for local e2e testing"' '"https://example.com/dao-logo.png"'` +
  ` --gas-budget 100000000`,
  { json: true },
);

// PTB --json uses event_json (parsed) rather than events[].parsedJson
const eventJson = daoResult.event_json;
if (!Array.isArray(eventJson) || eventJson.length === 0 || !eventJson[0].dao_id) {
  err("DAOCreated event not found in transaction output:");
  console.error(JSON.stringify(daoResult, null, 2));
  process.exit(1);
}

const ids = eventJson[0];
const DAO_ID = ids.dao_id;
const TREASURY_ID = ids.treasury_id;
const CAP_VAULT_ID = ids.capability_vault_id;
const CHARTER_ID = ids.charter_id;
const FREEZE_ID = ids.emergency_freeze_id;

ok(`DAO created: ${DAO_ID}`);
info(`  Treasury:         ${TREASURY_ID}`);
info(`  Capability Vault: ${CAP_VAULT_ID}`);
info(`  Charter:          ${CHARTER_ID}`);
info(`  Emergency Freeze: ${FREEZE_ID}`);

// ---------------------------------------------------------------------------
// Step 6: Write .env.local
// ---------------------------------------------------------------------------

step(`Writing ${ENV_FILE}`);

const envContent = `\
# Generated by scripts/localnet-setup.mjs — ${new Date().toISOString()}
# Do not commit this file.

# Network
VITE_NETWORK=localnet

# Package ID (both armature_framework + armature_proposals in one package)
VITE_PACKAGE_ID=${PACKAGE_ID}
VITE_PROPOSALS_PACKAGE_ID=${PACKAGE_ID}

# Test wallets
VITE_WALLET_KEY_1=${walletKey1}
VITE_WALLET_MNEMONIC_2=${user2Mnemonic}
VITE_WALLET_MNEMONIC_3=${user3Mnemonic}

# Test DAO object IDs
VITE_TEST_DAO_ID=${DAO_ID}
VITE_TEST_TREASURY_ID=${TREASURY_ID}
VITE_TEST_CAP_VAULT_ID=${CAP_VAULT_ID}
VITE_TEST_CHARTER_ID=${CHARTER_ID}
VITE_TEST_FREEZE_ID=${FREEZE_ID}

# Test wallet addresses (for reference)
# User 1 (creator): ${activeAddress}
# User 2 (board):   ${user2Address}
# User 3 (board):   ${user3Address}
`;

writeFileSync(ENV_FILE, envContent, "utf8");
ok(`Wrote ${ENV_FILE}`);

// ---------------------------------------------------------------------------
// Done
// ---------------------------------------------------------------------------

step("Setup complete!");
console.log();
info("To start the UI:");
info("  cd ui && npm run dev");
console.log();
info("Test wallets:");
info(`  User 1 (creator): ${activeAddress}`);
info(`  User 2 (board):   ${user2Address}`);
info(`  User 3 (board):   ${user3Address}`);
console.log();
info(`DAO ID: ${DAO_ID}`);
info(`Navigate to: http://localhost:5173/dao/${DAO_ID}`);
console.log();
