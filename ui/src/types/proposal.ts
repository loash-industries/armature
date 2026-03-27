/** Payload interfaces for each proposal type. */

export interface ProposalConfigInput {
  quorum: number;
  approvalThreshold: number;
  proposeThreshold: number;
  expiryMs: number;
  executionDelayMs: number;
  cooldownMs: number;
}

// --- Tier 1 payloads ---

export interface DisableProposalTypePayload {
  typeKey: string;
  metadataIpfs: string;
}

export interface TransferFreezeAdminPayload {
  recipient: string;
  metadataIpfs: string;
}

export interface UnfreezeProposalTypePayload {
  typeKey: string;
  metadataIpfs: string;
}

export interface SpinOutSubDAOPayload {
  subDaoId: string;
  controlCapId: string;
  freezeAdminCapId: string;
  metadataIpfs: string;
}

export interface SpawnDAOPayload {
  name: string;
  description: string;
  metadataIpfs: string;
}

export interface SendCoinToDAOPayload {
  recipientTreasuryId: string;
  amount: string;
  coinType: string;
  metadataIpfs: string;
}

export interface SendSmallPaymentPayload {
  recipient: string;
  amount: string;
  coinType: string;
  metadataIpfs: string;
}

export interface UpdateFreezeConfigPayload {
  newMaxFreezeDurationMs: string;
  metadataIpfs: string;
}

export interface UpdateFreezeExemptTypesPayload {
  typesToAdd: string;
  typesToRemove: string;
  metadataIpfs: string;
}

export interface TransferCapToSubDAOPayload {
  capId: string;
  targetSubdao: string;
  metadataIpfs: string;
}

export interface ReclaimCapFromSubDAOPayload {
  subdaoId: string;
  capId: string;
  controlId: string;
  metadataIpfs: string;
}

export interface ProposeUpgradePayload {
  capId: string;
  packageId: string;
  digest: string;
  policy: number;
  metadataIpfs: string;
}

export interface PauseSubDAOExecutionPayload {
  controlId: string;
  metadataIpfs: string;
}

export interface UnpauseSubDAOExecutionPayload {
  controlId: string;
  metadataIpfs: string;
}

export interface TransferAssetsPayload {
  targetDaoId: string;
  targetTreasuryId: string;
  targetVaultId: string;
  coinTypes: string;
  capIds: string;
  metadataIpfs: string;
}

// --- Tier 2 payloads ---

export interface TreasuryWithdrawPayload {
  coinType: string;
  amount: string;
  recipient: string;
  metadataIpfs: string;
}

export interface SetBoardPayload {
  members: string[];
  metadataIpfs: string;
}

export interface EnableProposalTypePayload {
  typeKey: string;
  config: ProposalConfigInput;
  metadataIpfs: string;
}

export interface UpdateProposalConfigPayload {
  typeKey: string;
  config: ProposalConfigInput;
  metadataIpfs: string;
}

export interface CharterUpdatePayload {
  name: string;
  description: string;
  imageUrl: string;
  metadataIpfs: string;
}

// --- Wizard payload ---

export interface CreateSubDAOPayload {
  name: string;
  metadataIpfs: string;
  board: string[];
  charterName: string;
  charterDescription: string;
  charterImageUrl: string;
  proposalTypes: Array<{
    typeKey: string;
    config: ProposalConfigInput;
  }>;
  fundingAmount: string;
}

/** Union of all payloads, discriminated by typeKey. */
export type ProposalPayload =
  | { typeKey: "DisableProposalType"; data: DisableProposalTypePayload }
  | { typeKey: "TransferFreezeAdmin"; data: TransferFreezeAdminPayload }
  | { typeKey: "UnfreezeProposalType"; data: UnfreezeProposalTypePayload }
  | { typeKey: "SpinOutSubDAO"; data: SpinOutSubDAOPayload }
  | { typeKey: "SpawnDAO"; data: SpawnDAOPayload }
  | { typeKey: "SendCoinToDAO"; data: SendCoinToDAOPayload }
  | { typeKey: "SendSmallPayment"; data: SendSmallPaymentPayload }
  | { typeKey: "UpdateFreezeConfig"; data: UpdateFreezeConfigPayload }
  | { typeKey: "UpdateFreezeExemptTypes"; data: UpdateFreezeExemptTypesPayload }
  | { typeKey: "TransferCapToSubDAO"; data: TransferCapToSubDAOPayload }
  | { typeKey: "ReclaimCapFromSubDAO"; data: ReclaimCapFromSubDAOPayload }
  | { typeKey: "ProposeUpgrade"; data: ProposeUpgradePayload }
  | { typeKey: "TreasuryWithdraw"; data: TreasuryWithdrawPayload }
  | { typeKey: "SetBoard"; data: SetBoardPayload }
  | { typeKey: "EnableProposalType"; data: EnableProposalTypePayload }
  | { typeKey: "UpdateProposalConfig"; data: UpdateProposalConfigPayload }
  | { typeKey: "CharterUpdate"; data: CharterUpdatePayload }
  | { typeKey: "CreateSubDAO"; data: CreateSubDAOPayload }
  | { typeKey: "PauseSubDAOExecution"; data: PauseSubDAOExecutionPayload }
  | { typeKey: "UnpauseSubDAOExecution"; data: UnpauseSubDAOExecutionPayload }
  | { typeKey: "TransferAssets"; data: TransferAssetsPayload };

/** Summary of an on-chain proposal for list views. */
export interface ProposalSummary {
  id: string;
  typeKey: string;
  proposer: string;
  status: "active" | "passed" | "executed" | "expired";
  yesWeight: number;
  noWeight: number;
  /** Snapshot of total governance weight at proposal creation — used for quorum/threshold checks. */
  totalSnapshotWeight: number;
  quorum: number;
  approvalThreshold: number;
  createdMs: number;
  expiryMs: number;
  executionDelayMs: number;
  metadataIpfs: string;
  /** Full Move type of the proposal payload, e.g. `0x...::set_board::SetBoard` */
  payloadType: string;
  /** Map of voter address → approved (true=yes, false=no) */
  votesCast: Record<string, boolean>;
  /** On-chain payload fields (e.g. new_members, recipient, amount). */
  payload: Record<string, unknown>;
  /** Transaction digest of the execution transaction (only present when status === "executed"). */
  executionTxHash?: string;
}
