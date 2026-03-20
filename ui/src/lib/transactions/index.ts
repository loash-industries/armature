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

// DAO lifecycle
export { buildCreateDao, buildSubmitCreateSubDAO } from "./dao";

// Proposal submission, voting, expiry
export {
  buildSubmitSetBoard,
  buildSubmitUpdateMetadata,
  buildSubmitSendCoin,
  buildSubmitDisableProposalType,
  buildSubmitEnableProposalType,
  buildSubmitTransferFreezeAdmin,
  buildSubmitUnfreezeProposalType,
  buildSubmitSendCoinToDAO,
  buildSubmitSendSmallPayment,
  buildSubmitUpdateFreezeConfig,
  buildSubmitUpdateFreezeExemptTypes,
  buildSubmitTransferCapToSubDAO,
  buildSubmitReclaimCapFromSubDAO,
  buildSubmitProposeUpgrade,
  buildSubmitSpawnDAO,
  buildSubmitSpinOutSubDAO,
  buildSubmitUpdateProposalConfig,
  buildSubmitPauseSubDAOExecution,
  buildSubmitUnpauseSubDAOExecution,
  buildSubmitTransferAssets,
  buildVote,
  buildTryExpire,
} from "./proposal";

// Proposal execution handlers
export {
  buildExecuteSetBoard,
  buildExecuteUpdateMetadata,
  buildExecuteDisableProposalType,
  buildExecuteEnableProposalType,
  buildExecuteSendCoin,
  buildExecuteUpdateProposalConfig,
  buildExecuteTransferFreezeAdmin,
  buildExecuteUnfreezeProposalType,
  buildExecuteUpdateFreezeConfig,
  buildExecuteUpdateFreezeExemptTypes,
  buildExecuteSendCoinToDAO,
  buildExecuteSendSmallPayment,
  buildExecuteSpawnDAO,
  buildExecuteCreateSubDAO,
  buildExecuteTransferCapToSubDAO,
  buildExecuteSpinOutSubDAO,
  buildExecutePauseSubDAOExecution,
  buildExecuteUnpauseSubDAOExecution,
  buildExecuteReclaimCap,
  buildExecuteTransferAssets,
  buildCommitUpgrade,
} from "./execution";

// Direct treasury actions
export { buildDeposit, buildClaimCoin } from "./treasury";

// Direct emergency actions
export { buildFreezeType, buildUnfreezeType } from "./emergency";

// Controller (privileged SubDAO operations)
export { buildPrivilegedOp } from "./controller";
