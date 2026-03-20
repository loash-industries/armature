/**
 * Proposal execution transaction builders.
 *
 * Each execution PTB follows the pattern: authorize_execution → handler → (finalize).
 */

import { Transaction, fw, prop, SUI_CLOCK, MODULES, PROPOSAL_MODULES, PROPOSALS_PACKAGE_ID } from "./helpers";

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

/** Execute an UpdateFreezeConfig proposal. */
export function buildExecuteUpdateFreezeConfig(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_freeze_config}::UpdateFreezeConfig`;

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
    target: prop(PROPOSAL_MODULES.security_ops, "execute_update_freeze_config"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.proposalId),
      req,
    ],
  });

  return tx;
}

/** Execute an UpdateFreezeExemptTypes proposal. */
export function buildExecuteUpdateFreezeExemptTypes(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.update_freeze_exempt_types}::UpdateFreezeExemptTypes`;

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
    target: prop(PROPOSAL_MODULES.security_ops, "execute_update_freeze_exempt_types"),
    arguments: [
      tx.object(args.emergencyFreezeId),
      tx.object(args.proposalId),
      req,
    ],
  });

  return tx;
}

/** Execute a SendCoinToDAO proposal. */
export function buildExecuteSendCoinToDAO(args: {
  daoId: string;
  proposalId: string;
  sourceTreasuryId: string;
  targetTreasuryId: string;
  emergencyFreezeId: string;
  coinType: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.send_coin_to_dao}::SendCoinToDAO<${args.coinType}>`;

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
    target: prop(PROPOSAL_MODULES.treasury_ops, "execute_send_coin_to_dao"),
    arguments: [
      tx.object(args.sourceTreasuryId),
      tx.object(args.targetTreasuryId),
      tx.object(args.proposalId),
      req,
    ],
    typeArguments: [args.coinType],
  });

  return tx;
}

/** Execute a SendSmallPayment proposal. */
export function buildExecuteSendSmallPayment(args: {
  daoId: string;
  proposalId: string;
  treasuryId: string;
  emergencyFreezeId: string;
  coinType: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.send_small_payment}::SendSmallPayment<${args.coinType}>`;

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
    target: prop(PROPOSAL_MODULES.treasury_ops, "execute_send_small_payment"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.treasuryId),
      tx.object(args.proposalId),
      req,
      tx.object(SUI_CLOCK),
    ],
    typeArguments: [args.coinType],
  });

  return tx;
}

/** Execute a SpawnDAO proposal. */
export function buildExecuteSpawnDAO(args: {
  daoId: string;
  proposalId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.spawn_dao}::SpawnDAO`;

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
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_spawn_dao"),
    arguments: [
      tx.object(args.daoId),
      tx.object(args.proposalId),
      req,
    ],
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

/** Execute a SpinOutSubDAO proposal. */
export function buildExecuteSpinOutSubDAO(args: {
  daoId: string;
  proposalId: string;
  capabilityVaultId: string;
  subdaoVaultId: string;
  subdaoId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.spin_out_subdao}::SpinOutSubDAO`;

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
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_spin_out_subdao"),
    arguments: [
      tx.object(args.capabilityVaultId),
      tx.object(args.subdaoVaultId),
      tx.object(args.subdaoId),
      tx.object(args.proposalId),
      req,
      tx.object(SUI_CLOCK),
    ],
  });

  return tx;
}

/** Execute a PauseSubDAOExecution proposal. */
export function buildExecutePauseSubDAOExecution(args: {
  daoId: string;
  proposalId: string;
  controllerVaultId: string;
  subdaoId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.pause_execution}::PauseSubDAOExecution`;

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
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_pause_subdao_execution"),
    arguments: [
      tx.object(args.controllerVaultId),
      tx.object(args.subdaoId),
      tx.object(args.proposalId),
      req,
      tx.object(SUI_CLOCK),
    ],
  });

  return tx;
}

/** Execute an UnpauseSubDAOExecution proposal. */
export function buildExecuteUnpauseSubDAOExecution(args: {
  daoId: string;
  proposalId: string;
  controllerVaultId: string;
  subdaoId: string;
  emergencyFreezeId: string;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.pause_execution}::UnpauseSubDAOExecution`;

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
    target: prop(PROPOSAL_MODULES.subdao_ops, "execute_unpause_subdao_execution"),
    arguments: [
      tx.object(args.controllerVaultId),
      tx.object(args.subdaoId),
      tx.object(args.proposalId),
      req,
      tx.object(SUI_CLOCK),
    ],
  });

  return tx;
}

/**
 * Commit a package upgrade after executing a ProposeUpgrade proposal.
 *
 * Flow:
 *   1. Execute ProposeUpgrade proposal → receive UpgradeTicket (off-chain: build upgrade bytes)
 *   2. Call sui::package::authorize_upgrade → receive UpgradeTicket
 *   3. Publish upgraded package bytes → receive UpgradeReceipt
 *   4. Call buildCommitUpgrade → returns UpgradeCap to the capability vault
 *
 * Steps 2-3 require CLI tooling (sui client upgrade). This builder handles step 4 only,
 * and must be called in the same PTB as the upgrade publish via PTB composition.
 */
export function buildCommitUpgrade(
  tx: Transaction,
  args: {
    capabilityVaultId: string;
    /** UpgradeCap object ID (held in the capability vault) */
    upgradeCapId: string;
    /** UpgradeReceipt result from the preceding package publish command in the same PTB */
    upgradeReceipt: ReturnType<Transaction["moveCall"]>;
    /** CapLoan result from a preceding vault borrow call in the same PTB */
    capLoan: ReturnType<Transaction["moveCall"]>;
  },
): void {
  tx.moveCall({
    target: prop(PROPOSAL_MODULES.upgrade_ops, "commit_upgrade"),
    arguments: [
      tx.object(args.capabilityVaultId),
      tx.object(args.upgradeCapId),
      args.upgradeReceipt,
      args.capLoan,
    ],
  });
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

/**
 * Execute a TransferAssets proposal.
 *
 * PTB flow (mirrors Move's validate → withdraw/deposit × N → finalize):
 *   1. authorize_execution → ExecutionRequest (hot potato)
 *   2. validate_transfer_assets — borrows req, emits AssetsTransferInitiated
 *   3. For each coinTransfer: source_treasury.withdraw<T> → target_treasury.deposit<T>
 *   4. finalize_transfer_assets — consumes req
 *
 * Cap transfers are not yet supported (pass capIds=[] in the proposal).
 */
export function buildExecuteTransferAssets(args: {
  daoId: string;
  proposalId: string;
  sourceTreasuryId: string;
  sourceVaultId: string;
  targetTreasuryId: string;
  targetVaultId: string;
  emergencyFreezeId: string;
  /** Each entry withdraws `amount` of `coinType` from source and deposits to target. */
  coinTransfers: Array<{ coinType: string; amount: string }>;
}): Transaction {
  const tx = new Transaction();
  const payloadType = `${PROPOSALS_PACKAGE_ID}::${PROPOSAL_MODULES.transfer_assets}::TransferAssets`;

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

  // Validate the proposal payload and emit AssetsTransferInitiated (borrows req).
  tx.moveCall({
    target: prop(PROPOSAL_MODULES.subdao_ops, "validate_transfer_assets"),
    arguments: [
      tx.object(args.sourceTreasuryId),
      tx.object(args.sourceVaultId),
      tx.object(args.targetTreasuryId),
      tx.object(args.targetVaultId),
      tx.object(args.proposalId),
      req,
    ],
  });

  // For each coin type: withdraw from source treasury and deposit to target.
  for (const { coinType, amount } of args.coinTransfers) {
    const coin = tx.moveCall({
      target: fw(MODULES.treasury_vault, "withdraw"),
      arguments: [
        tx.object(args.sourceTreasuryId),
        tx.pure.u64(amount),
        req,
      ],
      typeArguments: [coinType, payloadType],
    });

    tx.moveCall({
      target: fw(MODULES.treasury_vault, "deposit"),
      arguments: [tx.object(args.targetTreasuryId), coin],
      typeArguments: [coinType],
    });
  }

  // Consume the ExecutionRequest (finalize).
  tx.moveCall({
    target: prop(PROPOSAL_MODULES.subdao_ops, "finalize_transfer_assets"),
    arguments: [req, tx.object(args.proposalId)],
  });

  return tx;
}
