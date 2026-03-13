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
  EmergencyFreeze: [
    {
      type: "select",
      name: "typeKey",
      label: "Proposal Type to Freeze",
      optionsKey: "enabledTypes",
    },
    {
      type: "number",
      name: "durationMs",
      label: "Freeze Duration (hours)",
      min: 1,
      placeholder: "24",
    },
  ],
  EmergencyUnfreeze: [
    {
      type: "select",
      name: "typeKey",
      label: "Proposal Type to Unfreeze",
      optionsKey: "frozenTypes",
    },
  ],
  CapabilityExtract: [
    { type: "text", name: "capObjectId", label: "Capability Object ID", placeholder: "0x..." },
    { type: "address", name: "recipient", label: "Recipient Address" },
  ],
  SpawnDAO: [
    { type: "text", name: "successorDaoId", label: "Successor DAO Object ID", placeholder: "0x..." },
  ],
};
