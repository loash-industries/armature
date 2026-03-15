/** Field definitions for the generic (Tier 1) proposal form renderer. */

export type FieldDef =
  | { type: "text"; name: string; label: string; placeholder?: string }
  | { type: "address"; name: string; label: string }
  | {
      type: "select";
      name: string;
      label: string;
      optionsKey: string;
    }
  | {
      type: "number";
      name: string;
      label: string;
      min?: number;
      placeholder?: string;
    }
  | {
      type: "duration";
      name: string;
      label: string;
      placeholder?: string;
    };

/** Field definitions for each Tier 1 proposal type. */
export const TIER1_FIELD_DEFS: Record<string, FieldDef[]> = {
  DisableProposalType: [
    {
      type: "select",
      name: "typeKey",
      label: "Proposal Type to Disable",
      optionsKey: "enabledTypes",
    },
  ],
  TransferFreezeAdmin: [
    { type: "address", name: "recipient", label: "New Freeze Admin Address" },
  ],
  UnfreezeProposalType: [
    {
      type: "select",
      name: "typeKey",
      label: "Proposal Type to Unfreeze",
      optionsKey: "frozenTypes",
    },
  ],
  SpinOutSubDAO: [
    { type: "text", name: "subDaoId", label: "SubDAO Object ID", placeholder: "0x..." },
  ],
  SpawnDAO: [
    { type: "text", name: "name", label: "New DAO Name", placeholder: "My DAO" },
    { type: "text", name: "description", label: "Description", placeholder: "DAO description" },
  ],
  UpdateFreezeConfig: [
    { type: "text", name: "newMaxFreezeDurationMs", label: "Max Freeze Duration (ms)", placeholder: "604800000" },
  ],
  UpdateFreezeExemptTypes: [
    { type: "text", name: "typesToAdd", label: "Types to Add (comma-separated)", placeholder: "TypeA, TypeB" },
    { type: "text", name: "typesToRemove", label: "Types to Remove (comma-separated)", placeholder: "TypeC" },
  ],
  TransferCapToSubDAO: [
    { type: "text", name: "capId", label: "Capability Object ID", placeholder: "0x..." },
    { type: "text", name: "targetSubdao", label: "Target SubDAO Object ID", placeholder: "0x..." },
  ],
  ReclaimCapFromSubDAO: [
    { type: "text", name: "subdaoId", label: "SubDAO Object ID", placeholder: "0x..." },
    { type: "text", name: "capId", label: "Capability Object ID", placeholder: "0x..." },
    { type: "text", name: "controlId", label: "SubDAOControl Object ID", placeholder: "0x..." },
  ],
  ProposeUpgrade: [
    { type: "text", name: "capId", label: "UpgradeCap Object ID", placeholder: "0x..." },
    { type: "text", name: "packageId", label: "Package ID", placeholder: "0x..." },
    { type: "text", name: "digest", label: "Build Digest (hex)", placeholder: "0x..." },
    { type: "number", name: "policy", label: "Upgrade Policy", min: 0, placeholder: "0" },
  ],
  PauseSubDAOExecution: [
    { type: "text", name: "controlId", label: "SubDAOControl Object ID", placeholder: "0x..." },
  ],
  UnpauseSubDAOExecution: [
    { type: "text", name: "controlId", label: "SubDAOControl Object ID", placeholder: "0x..." },
  ],
  TransferAssets: [
    { type: "text", name: "targetDaoId", label: "Target DAO Object ID", placeholder: "0x..." },
    { type: "text", name: "targetTreasuryId", label: "Target Treasury Object ID", placeholder: "0x..." },
    { type: "text", name: "targetVaultId", label: "Target Capability Vault Object ID", placeholder: "0x..." },
    { type: "text", name: "coinTypes", label: "Coin Types (comma-separated)", placeholder: "0x2::sui::SUI" },
    { type: "text", name: "capIds", label: "Capability IDs (comma-separated)", placeholder: "0x..." },
  ],
};
