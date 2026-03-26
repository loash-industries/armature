/** TypeScript representations of on-chain Move structs. */

export interface DaoFields {
  id: { id: string };
  status: { variant: "Active" } | { variant: "Migrating" };
  governance: GovernanceConfigFields;
  proposal_configs: {
    contents: Array<{ key: string; value: ProposalConfigFields }>;
  };
  enabled_proposal_types: { contents: string[] };
  last_executed_at: { contents: Array<{ key: string; value: string }> };
  treasury_id: string;
  capability_vault_id: string;
  charter_id: string;
  emergency_freeze_id: string;
  execution_paused: boolean;
  controller_cap_id: { vec: string[] };
  controller_paused: boolean;
}

export type GovernanceConfigFields =
  | { variant: "Board"; fields: { members: { contents: string[] } } }
  | {
      variant: "Direct";
      fields: {
        voters: { contents: Array<{ key: string; value: string }> };
        total_shares: string;
      };
    }
  | {
      variant: "Weighted";
      fields: {
        delegates: { contents: Array<{ key: string; value: string }> };
        total_delegated: string;
      };
    };

export interface ProposalConfigFields {
  quorum: number;           // u16 — arrives as number from Sui JSON-RPC
  approval_threshold: number; // u16 — arrives as number from Sui JSON-RPC
  propose_threshold: string;  // u64 — arrives as string
  expiry_ms: string;          // u64
  execution_delay_ms: string; // u64
  cooldown_ms: string;        // u64
}

/** Parsed proposal type config for the Governance page. */
export interface ProposalTypeConfig {
  typeKey: string;
  enabled: boolean;
  frozen: boolean;
  protected: boolean;
  config: {
    quorum: number;
    approvalThreshold: number;
    proposeThreshold: number;
    expiryMs: number;
    executionDelayMs: number;
    cooldownMs: number;
  } | null;
}

export interface TreasuryVaultFields {
  id: { id: string };
  dao_id: string;
  coin_types: { contents: string[] };
}

export interface CharterFields {
  id: { id: string };
  dao_id: string;
  name: string;
  description: string;
  image_url: string;
}

export interface EmergencyFreezeFields {
  id: { id: string };
  dao_id: string;
  frozen_types: { contents: Array<{ key: string; value: string }> };
  max_freeze_duration_ms: string;
}

/** Parsed governance detail for the Board page. */
export interface GovernanceDetail {
  type: "Board" | "Direct" | "Weighted";
  members: GovernanceMember[];
  totalShares?: number;
}

export interface GovernanceMember {
  address: string;
  weight?: number;
}

/** Parsed charter for the Charter page. */
export interface CharterDetail {
  id: string;
  name: string;
  description: string;
  imageUrl: string;
}

/** Parsed emergency freeze for the Emergency page. */
export interface EmergencyFreezeDetail {
  id: string;
  frozenTypes: Array<{ typeKey: string; expiryMs: number }>;
  maxFreezeDurationMs: number;
}

/** Parsed DAO summary used by the dashboard. */
export interface DaoSummary {
  id: string;
  status: "Active" | "Migrating";
  boardMemberCount: number;
  treasuryId: string;
  charterId: string;
  charterName: string;
  emergencyFreezeId: string;
  capabilityVaultId: string;
  enabledProposalTypes: string[];
  frozenTypes: Array<{ typeKey: string; expiryMs: number }>;
}

export interface SubDAONode {
  daoId: string;
  name: string;
  status: "Active" | "Migrating";
  controllerPaused: boolean;
  executionPaused: boolean;
  childCount: number;
}

export interface DAOHierarchy {
  root: SubDAONode;
  children: SubDAONode[];
  parentId: string | null;
}

/** On-chain CapabilityVault fields. */
export interface CapabilityVaultFields {
  id: { id: string };
  dao_id: string;
  cap_types: { contents: string[] };
  cap_ids: { contents: string[] };
  ids_by_type: { contents: Array<{ key: string; value: string[] }> };
}

/** Parsed capability entry for the vault page. */
export interface CapabilityEntry {
  id: string;
  typeName: string;
  shortType: string;
  objectType: string | null;
  isSubDAOControl: boolean;
  subdaoId: string | null;
}

/** A coin balance entry from the treasury. */
export interface TreasuryCoinBalance {
  coinType: string;
  balance: bigint;
  decimals: number;
}

/** Parsed event for the activity feed. */
export interface ActivityEvent {
  txDigest: string;
  eventType: string;
  label: string;
  description: string;
  timestampMs: number;
  /** Address of the actor (voter, depositor, executor, proposer, etc.) */
  actor?: string;
  /** Fully-qualified coin type for treasury events */
  coinType?: string;
  /** Raw coin amount (smallest unit, as string) for treasury events */
  coinAmount?: string;
  /** Recipient address for send/withdraw events */
  recipient?: string;
  /** Whether the vote was an approval (VoteCast only) */
  approve?: boolean;
  /** Proposal type key or affected type key */
  typeKey?: string;
  /** Proposal object ID (for vote/proposal events) */
  proposalId?: string;
}
