/**
 * PTB (Programmable Transaction Block) builders for armature on-chain calls.
 *
 * Each builder returns a Transaction ready for signing. The caller is responsible
 * for executing via useWalletSigner().signAndExecuteTransaction({ transaction }).
 *
 * Two packages are referenced:
 * - PACKAGE_ID  → armature_framework (dao, proposal, board_voting, etc.)
 * - PROPOSALS_PACKAGE_ID → armature_proposals (payload types + execution handlers)
 */

import { Transaction } from "@mysten/sui/transactions";
import {
  PACKAGE_ID,
  PROPOSALS_PACKAGE_ID,
  MODULES,
  PROPOSAL_MODULES,
} from "@/config/constants";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SUI_CLOCK = "0x6";

function target(pkg: string, module: string, fn: string): `${string}::${string}::${string}` {
  return `${pkg}::${module}::${fn}`;
}

function fw(module: string, fn: string) {
  return target(PACKAGE_ID, module, fn);
}

function prop(module: string, fn: string) {
  return target(PROPOSALS_PACKAGE_ID, module, fn);
}

// ---------------------------------------------------------------------------
// #93 — DAO Lifecycle
// ---------------------------------------------------------------------------

/** Create a new root DAO. Returns a Transaction (DAO ID is emitted as event). */
export function buildCreateDao(args: {
  name: string;
  description: string;
  imageUrl: string;
  initialMembers: string[];
}): Transaction {
  const tx = new Transaction();

  // 1. Init board governance
  const govInit = tx.moveCall({
    target: fw(MODULES.governance, "init_board"),
    arguments: [
      tx.pure.vector("address", args.initialMembers),
    ],
  });

  // 2. Create DAO
  tx.moveCall({
    target: fw(MODULES.dao, "create"),
    arguments: [
      govInit,
      tx.pure.string(args.name),
      tx.pure.string(args.description),
      tx.pure.string(args.imageUrl),
    ],
  });

  return tx;
}

/** Create a SubDAO via proposal execution flow. */
export function buildSubmitCreateSubDAO(args: {
  daoId: string;
  name: string;
  description: string;
  initialBoard: string[];
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.create_subdao, "new"),
    arguments: [
      tx.pure.string(args.name),
      tx.pure.string(args.description),
      tx.pure.vector("address", args.initialBoard),
      tx.pure.string(args.metadataIpfs),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("CreateSubDAO"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.create_subdao}::CreateSubDAO`,
    ],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// #94 — Proposal Lifecycle (submit, vote, execute, expire)
// ---------------------------------------------------------------------------

/** Submit a SetBoard proposal. */
export function buildSubmitSetBoard(args: {
  daoId: string;
  newMembers: string[];
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.set_board, "new"),
    arguments: [tx.pure.vector("address", args.newMembers)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("SetBoard"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.set_board}::SetBoard`,
    ],
  });

  return tx;
}

/** Submit an UpdateMetadata (charter) proposal. */
export function buildSubmitUpdateMetadata(args: {
  daoId: string;
  newIpfsCid: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.update_metadata, "new"),
    arguments: [tx.pure.string(args.newIpfsCid)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("CharterUpdate"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_metadata}::UpdateMetadata`,
    ],
  });

  return tx;
}

/** Submit a SendCoin proposal. */
export function buildSubmitSendCoin(args: {
  daoId: string;
  recipient: string;
  amount: string;
  coinType: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.send_coin, "new"),
    arguments: [
      tx.pure.address(args.recipient),
      tx.pure.u64(args.amount),
    ],
    typeArguments: [args.coinType],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("SendCoin"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.send_coin}::SendCoin<${args.coinType}>`,
    ],
  });

  return tx;
}

/** Submit a DisableProposalType proposal. */
export function buildSubmitDisableProposalType(args: {
  daoId: string;
  typeKey: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.disable_proposal_type, "new"),
    arguments: [tx.pure.string(args.typeKey)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("DisableProposalType"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.disable_proposal_type}::DisableProposalType`,
    ],
  });

  return tx;
}

/** Submit an EnableProposalType proposal. */
export function buildSubmitEnableProposalType(args: {
  daoId: string;
  typeKey: string;
  quorum: number;
  approvalThreshold: number;
  proposeThreshold: string;
  expiryMs: string;
  executionDelayMs: string;
  cooldownMs: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const config = tx.moveCall({
    target: fw(MODULES.proposal, "new_config"),
    arguments: [
      tx.pure.u16(args.quorum),
      tx.pure.u16(args.approvalThreshold),
      tx.pure.u64(args.proposeThreshold),
      tx.pure.u64(args.expiryMs),
      tx.pure.u64(args.executionDelayMs),
      tx.pure.u64(args.cooldownMs),
    ],
  });

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.enable_proposal_type, "new"),
    arguments: [tx.pure.string(args.typeKey), config],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("EnableProposalType"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.enable_proposal_type}::EnableProposalType`,
    ],
  });

  return tx;
}

/** Submit a TransferFreezeAdmin proposal. */
export function buildSubmitTransferFreezeAdmin(args: {
  daoId: string;
  newAdmin: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.transfer_freeze_admin, "new"),
    arguments: [tx.pure.address(args.newAdmin)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("TransferFreezeAdmin"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.transfer_freeze_admin}::TransferFreezeAdmin`,
    ],
  });

  return tx;
}

/** Submit an UnfreezeProposalType proposal. */
export function buildSubmitUnfreezeProposalType(args: {
  daoId: string;
  typeKey: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.unfreeze_proposal_type, "new"),
    arguments: [tx.pure.string(args.typeKey)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("UnfreezeProposalType"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.unfreeze_proposal_type}::UnfreezeProposalType`,
    ],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// Vote / Execute / Expire (proposal lifecycle actions)
// ---------------------------------------------------------------------------

/** Cast a vote on a proposal. */
export function buildVote(args: {
  proposalId: string;
  approve: boolean;
  /** The full Move type of the proposal payload, e.g. `0x...::set_board::SetBoard` */
  proposalType: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.proposal, "vote"),
    arguments: [
      tx.object(args.proposalId),
      tx.pure.bool(args.approve),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [args.proposalType],
  });

  return tx;
}

/** Try to expire a proposal that has passed its expiry time. */
export function buildTryExpire(args: {
  proposalId: string;
  proposalType: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.proposal, "try_expire"),
    arguments: [
      tx.object(args.proposalId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [args.proposalType],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// Execution handlers — authorize + handler + finalize in one PTB
// ---------------------------------------------------------------------------

/** Execute a SetBoard proposal. */
export function buildExecuteSetBoard(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.set_board}::SetBoard`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.board_ops, "execute_set_board"),
    arguments: [tx.object(args.daoId), tx.object(args.proposalId), req],
  });

  return tx;
}

/** Execute an UpdateMetadata proposal. */
export function buildExecuteUpdateMetadata(args: {
  daoId: string;
  proposalId: string;
  charterId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_metadata}::UpdateMetadata`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.admin_ops, "execute_update_metadata"),
    arguments: [tx.object(args.charterId), tx.object(args.proposalId), req],
  });

  return tx;
}

/** Execute a DisableProposalType proposal. */
export function buildExecuteDisableProposalType(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.disable_proposal_type}::DisableProposalType`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.admin_ops, "execute_disable_proposal_type"),
    arguments: [tx.object(args.daoId), tx.object(args.proposalId), req],
  });

  return tx;
}

/** Execute an EnableProposalType proposal. */
export function buildExecuteEnableProposalType(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.enable_proposal_type}::EnableProposalType`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.admin_ops, "execute_enable_proposal_type"),
    arguments: [tx.object(args.daoId), tx.object(args.proposalId), req],
  });

  return tx;
}

/** Execute a SendCoin proposal. */
export function buildExecuteSendCoin(args: {
  daoId: string;
  proposalId: string;
  treasuryId: string;
  emergencyFreezeId: string;
  coinType: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.send_coin}::SendCoin<${args.coinType}>`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.treasury_ops, "execute_send_coin"),
    arguments: [
      tx.object(args.treasuryId),
      tx.object(args.proposalId),
      req,
    ],
    typeArguments: [args.coinType],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// #95 — Governance Mutation Transactions
// ---------------------------------------------------------------------------

/** Execute an UpdateProposalConfig proposal. */
export function buildSubmitUpdateProposalConfig(args: {
  daoId: string;
  targetTypeKey: string;
  quorum?: number;
  approvalThreshold?: number;
  proposeThreshold?: string;
  expiryMs?: string;
  executionDelayMs?: string;
  cooldownMs?: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  // Build Option<u16> / Option<u64> for each field
  const optU16 = (val?: number) =>
    val !== undefined
      ? tx.moveCall({
          target: "0x1::option::some",
          arguments: [tx.pure.u16(val)],
          typeArguments: ["u16"],
        })
      : tx.moveCall({
          target: "0x1::option::none",
          typeArguments: ["u16"],
        });

  const optU64 = (val?: string) =>
    val !== undefined
      ? tx.moveCall({
          target: "0x1::option::some",
          arguments: [tx.pure.u64(val)],
          typeArguments: ["u64"],
        })
      : tx.moveCall({
          target: "0x1::option::none",
          typeArguments: ["u64"],
        });

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.update_proposal_config, "new"),
    arguments: [
      tx.pure.string(args.targetTypeKey),
      optU16(args.quorum),
      optU16(args.approvalThreshold),
      optU64(args.proposeThreshold),
      optU64(args.expiryMs),
      optU64(args.executionDelayMs),
      optU64(args.cooldownMs),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("UpdateProposalConfig"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_proposal_config}::UpdateProposalConfig`,
    ],
  });

  return tx;
}

/** Execute an UpdateProposalConfig proposal. */
export function buildExecuteUpdateProposalConfig(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_proposal_config}::UpdateProposalConfig`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.admin_ops, "execute_update_proposal_config"),
    arguments: [tx.object(args.daoId), tx.object(args.proposalId), req],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// #95 — Security / Emergency
// ---------------------------------------------------------------------------

/** Execute a TransferFreezeAdmin proposal. */
export function buildExecuteTransferFreezeAdmin(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
  freezeAdminCapId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.transfer_freeze_admin}::TransferFreezeAdmin`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.security_ops, "execute_transfer_freeze_admin"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.freezeAdminCapId),
      tx.object(args.proposalId),
      req,
    ],
  });

  return tx;
}

/** Execute an UnfreezeProposalType proposal. */
export function buildExecuteUnfreezeProposalType(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.unfreeze_proposal_type}::UnfreezeProposalType`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.security_ops, "execute_unfreeze_proposal_type"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.proposalId),
      req,
    ],
  });

  return tx;
}

/** Freeze a proposal type (direct FreezeAdminCap action, not proposal-gated). */
export function buildFreezeType(args: {
  emergencyFreezeId: string;
  freezeAdminCapId: string;
  typeKey: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.emergency, "freeze_type"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.freezeAdminCapId),
      tx.pure.string(args.typeKey),
      tx.object(SUI_CLOCK),
    ],
  });

  return tx;
}

/** Unfreeze a proposal type (direct FreezeAdminCap action). */
export function buildUnfreezeType(args: {
  emergencyFreezeId: string;
  freezeAdminCapId: string;
  typeKey: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.emergency, "unfreeze_type"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.freezeAdminCapId),
      tx.pure.string(args.typeKey),
    ],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// #96 — Treasury & Capability Vault
// ---------------------------------------------------------------------------

/** Deposit a coin into the DAO treasury. */
export function buildDeposit(args: {
  treasuryId: string;
  coinObjectId: string;
  coinType: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: fw(MODULES.treasury_vault, "deposit"),
    arguments: [
      tx.object(args.treasuryId),
      tx.object(args.coinObjectId),
    ],
    typeArguments: [args.coinType],
  });

  return tx;
}

/** Execute a CreateSubDAO proposal. */
export function buildExecuteCreateSubDAO(args: {
  daoId: string;
  proposalId: string;
  capabilityVaultId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.create_subdao}::CreateSubDAO`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_create_subdao"),
    arguments: [
      tx.object(args.capabilityVaultId),
      tx.object(args.proposalId),
      req,
    ],
  });

  return tx;
}

/** Execute a TransferCapToSubDAO proposal. */
export function buildExecuteTransferCapToSubDAO(args: {
  daoId: string;
  proposalId: string;
  sourceVaultId: string;
  targetVaultId: string;
  emergencyFreezeId: string;
  capType: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.transfer_cap_to_subdao}::TransferCapToSubDAO`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_transfer_cap"),
    arguments: [
      tx.object(args.sourceVaultId),
      tx.object(args.targetVaultId),
      tx.object(args.proposalId),
      req,
    ],
    typeArguments: [args.capType],
  });

  return tx;
}

/** Execute a ReclaimCapFromSubDAO proposal. */
export function buildExecuteReclaimCap(args: {
  daoId: string;
  proposalId: string;
  controllerVaultId: string;
  subdaoVaultId: string;
  emergencyFreezeId: string;
  capType: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.reclaim_cap_from_subdao}::ReclaimCapFromSubDAO`;

  const req = tx.moveCall({
    target: fw(MODULES.board_voting, "authorize_execution"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      tx.object(args.emergencyFreezeId),
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [payloadType],
  });

  tx.moveCall({
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_reclaim_cap"),
    arguments: [
      tx.object(args.controllerVaultId),
      tx.object(args.subdaoVaultId),
      tx.object(args.proposalId),
      req,
    ],
    typeArguments: [args.capType],
  });

  return tx;
}
