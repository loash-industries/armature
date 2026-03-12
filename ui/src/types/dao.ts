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
  quorum_threshold_bps: string;
  approval_threshold_bps: string;
  voting_duration_ms: string;
  execution_delay_ms: string;
  execution_window_ms: string;
  cooldown_ms: string;
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

/** A coin balance entry from the treasury. */
export interface TreasuryCoinBalance {
  coinType: string;
  balance: bigint;
}

/** Parsed event for the activity feed. */
export interface ActivityEvent {
  txDigest: string;
  eventType: string;
  label: string;
  description: string;
  timestampMs: number;
}
