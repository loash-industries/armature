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
  metadataIpfs: string;
}

export interface EmergencyFreezePayload {
  typeKey: string;
  durationMs: number;
  metadataIpfs: string;
}

export interface EmergencyUnfreezePayload {
  typeKey: string;
  metadataIpfs: string;
}

export interface CapabilityExtractPayload {
  capObjectId: string;
  recipient: string;
  metadataIpfs: string;
}

export interface SpawnDAOPayload {
  successorDaoId: string;
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
  | { typeKey: "EmergencyFreeze"; data: EmergencyFreezePayload }
  | { typeKey: "EmergencyUnfreeze"; data: EmergencyUnfreezePayload }
  | { typeKey: "CapabilityExtract"; data: CapabilityExtractPayload }
  | { typeKey: "SpawnDAO"; data: SpawnDAOPayload }
  | { typeKey: "TreasuryWithdraw"; data: TreasuryWithdrawPayload }
  | { typeKey: "SetBoard"; data: SetBoardPayload }
  | { typeKey: "EnableProposalType"; data: EnableProposalTypePayload }
  | { typeKey: "UpdateProposalConfig"; data: UpdateProposalConfigPayload }
  | { typeKey: "CharterUpdate"; data: CharterUpdatePayload }
  | { typeKey: "CreateSubDAO"; data: CreateSubDAOPayload };

/** Summary of an on-chain proposal for list views. */
export interface ProposalSummary {
  id: string;
  typeKey: string;
  proposer: string;
  status: "active" | "passed" | "executed" | "expired";
  yesWeight: number;
  noWeight: number;
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
}
