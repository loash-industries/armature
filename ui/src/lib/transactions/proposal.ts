/**
 * Proposal submission, voting, and expiry transaction builders.
 */

import { Transaction, fw, prop, SUI_CLOCK, MODULES, PROPOSAL_MODULES, PROPOSALS_PACKAGE_ID } from "./helpers";

// ---------------------------------------------------------------------------
// Submit builders
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

/** Submit a SendCoinToDAO proposal. */
export function buildSubmitSendCoinToDAO(args: {
  daoId: string;
  recipientTreasuryId: string;
  amount: string;
  coinType: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.send_coin_to_dao, "new"),
    arguments: [
      tx.pure.id(args.recipientTreasuryId),
      tx.pure.u64(args.amount),
    ],
    typeArguments: [args.coinType],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("SendCoinToDAO"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.send_coin_to_dao}::SendCoinToDAO<${args.coinType}>`,
    ],
  });

  return tx;
}

/** Submit a SendSmallPayment proposal. */
export function buildSubmitSendSmallPayment(args: {
  daoId: string;
  recipient: string;
  amount: string;
  coinType: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.send_small_payment, "new"),
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
      tx.pure.string("SendSmallPayment"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.send_small_payment}::SendSmallPayment<${args.coinType}>`,
    ],
  });

  return tx;
}

/** Submit an UpdateFreezeConfig proposal. */
export function buildSubmitUpdateFreezeConfig(args: {
  daoId: string;
  newMaxFreezeDurationMs: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.update_freeze_config, "new"),
    arguments: [tx.pure.u64(args.newMaxFreezeDurationMs)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("UpdateFreezeConfig"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_freeze_config}::UpdateFreezeConfig`,
    ],
  });

  return tx;
}

/** Submit an UpdateFreezeExemptTypes proposal. */
export function buildSubmitUpdateFreezeExemptTypes(args: {
  daoId: string;
  typesToAdd: string[];
  typesToRemove: string[];
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.update_freeze_exempt_types, "new"),
    arguments: [
      tx.pure.vector("string", args.typesToAdd),
      tx.pure.vector("string", args.typesToRemove),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("UpdateFreezeExemptTypes"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_freeze_exempt_types}::UpdateFreezeExemptTypes`,
    ],
  });

  return tx;
}

/** Submit a TransferCapToSubDAO proposal. */
export function buildSubmitTransferCapToSubDAO(args: {
  daoId: string;
  capId: string;
  targetSubdao: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.transfer_cap_to_subdao, "new"),
    arguments: [
      tx.pure.id(args.capId),
      tx.pure.id(args.targetSubdao),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("TransferCapToSubDAO"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.transfer_cap_to_subdao}::TransferCapToSubDAO`,
    ],
  });

  return tx;
}

/** Submit a ReclaimCapFromSubDAO proposal. */
export function buildSubmitReclaimCapFromSubDAO(args: {
  daoId: string;
  subdaoId: string;
  capId: string;
  controlId: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.reclaim_cap_from_subdao, "new"),
    arguments: [
      tx.pure.id(args.subdaoId),
      tx.pure.id(args.capId),
      tx.pure.id(args.controlId),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("ReclaimCapFromSubDAO"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.reclaim_cap_from_subdao}::ReclaimCapFromSubDAO`,
    ],
  });

  return tx;
}

/** Submit a ProposeUpgrade proposal. */
export function buildSubmitProposeUpgrade(args: {
  daoId: string;
  capId: string;
  packageId: string;
  digest: string;
  policy: number;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  // Convert hex digest to bytes
  const digestHex = args.digest.startsWith("0x") ? args.digest.slice(2) : args.digest;
  const digestBytes = new Uint8Array(
    digestHex.match(/.{1,2}/g)?.map((b) => parseInt(b, 16)) ?? [],
  );

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.propose_upgrade, "new"),
    arguments: [
      tx.pure.id(args.capId),
      tx.pure.id(args.packageId),
      tx.pure.vector("u8", Array.from(digestBytes)),
      tx.pure.u8(args.policy),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("ProposeUpgrade"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.propose_upgrade}::ProposeUpgrade`,
    ],
  });

  return tx;
}

/** Submit a SpawnDAO proposal. */
export function buildSubmitSpawnDAO(args: {
  daoId: string;
  name: string;
  description: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const govInit = tx.moveCall({
    target: fw(MODULES.governance, "init_board"),
    arguments: [tx.pure.vector("address", [])],
  });

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.spawn_dao, "new"),
    arguments: [
      govInit,
      tx.pure.string(args.name),
      tx.pure.string(args.description),
      tx.pure.string(args.metadataIpfs),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("SpawnDAO"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.spawn_dao}::SpawnDAO`,
    ],
  });

  return tx;
}

/** Submit a SpinOutSubDAO proposal. */
export function buildSubmitSpinOutSubDAO(args: {
  daoId: string;
  subDaoId: string;
  /** Object ID of the SubDAOControl stored in the parent DAO's capability vault. */
  controlCapId: string;
  /** Object ID of the SubDAO's FreezeAdminCap stored in the parent DAO's capability vault. */
  freezeAdminCapId: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const defaultConfig = (q: number, t: number) =>
    tx.moveCall({
      target: fw(MODULES.proposal, "new_config"),
      arguments: [
        tx.pure.u16(q),
        tx.pure.u16(t),
        tx.pure.u64("0"),
        tx.pure.u64("86400000"), // 24h
        tx.pure.u64("0"),
        tx.pure.u64("0"),
      ],
    });

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.spin_out_subdao, "new"),
    arguments: [
      tx.pure.id(args.subDaoId),
      tx.pure.id(args.controlCapId),
      tx.pure.id(args.freezeAdminCapId),
      defaultConfig(5000, 5000),
      defaultConfig(5000, 5000),
      defaultConfig(5000, 5000),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("SpinOutSubDAO"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.spin_out_subdao}::SpinOutSubDAO`,
    ],
  });

  return tx;
}

/** Submit an UpdateProposalConfig proposal. */
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

/** Submit a PauseSubDAOExecution proposal. */
export function buildSubmitPauseSubDAOExecution(args: {
  daoId: string;
  controlId: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.pause_execution, "new_pause"),
    arguments: [tx.pure.id(args.controlId)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("PauseSubDAOExecution"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.pause_execution}::PauseSubDAOExecution`,
    ],
  });

  return tx;
}

/** Submit an UnpauseSubDAOExecution proposal. */
export function buildSubmitUnpauseSubDAOExecution(args: {
  daoId: string;
  controlId: string;
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.pause_execution, "new_unpause"),
    arguments: [tx.pure.id(args.controlId)],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("UnpauseSubDAOExecution"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.pause_execution}::UnpauseSubDAOExecution`,
    ],
  });

  return tx;
}

/** Submit a TransferAssets proposal. */
export function buildSubmitTransferAssets(args: {
  daoId: string;
  targetDaoId: string;
  targetTreasuryId: string;
  targetVaultId: string;
  coinTypes: string[];
  capIds: string[];
  metadataIpfs: string;
}): Transaction {
  const tx = new Transaction();

  // Build vector<TypeName> from coin type strings
  const typeNames = args.coinTypes.map((ct) =>
    tx.moveCall({
      target: "0x1::type_name::get",
      typeArguments: [ct],
    }),
  );

  const typeNameVec = tx.makeMoveVec({
    type: "0x1::type_name::TypeName",
    elements: typeNames,
  });

  const payload = tx.moveCall({
    target: prop(PROPOSAL_MODULES.transfer_assets, "new"),
    arguments: [
      tx.pure.id(args.targetDaoId),
      tx.pure.id(args.targetTreasuryId),
      tx.pure.id(args.targetVaultId),
      typeNameVec,
      tx.pure.vector("id", args.capIds),
    ],
  });

  tx.moveCall({
    target: fw(MODULES.board_voting, "submit_proposal"),
    arguments: [
      tx.object(args.daoId),
      tx.pure.string("TransferAssets"),
      tx.pure.string(args.metadataIpfs),
      payload,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [
      `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.transfer_assets}::TransferAssets`,
    ],
  });

  return tx;
}

// ---------------------------------------------------------------------------
// Vote / Expire
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
