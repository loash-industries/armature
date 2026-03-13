import { z } from "zod";

const suiAddress = z
  .string()
  .regex(/^0x[a-fA-F0-9]{64}$/, "Must be a valid Sui address (0x + 64 hex)");

const suiObjectId = suiAddress;

const metadataIpfs = z.string().min(1, "Proposal description is required");

/** Shared proposal config schema (quorum, threshold, etc.). */
export const proposalConfigSchema = z.object({
  quorum: z
    .number()
    .int()
    .min(1, "Quorum must be at least 0.01%")
    .max(10000, "Quorum cannot exceed 100%"),
  approvalThreshold: z
    .number()
    .int()
    .min(1, "Threshold must be at least 0.01%")
    .max(10000, "Threshold cannot exceed 100%"),
  proposeThreshold: z.number().int().min(0),
  expiryMs: z.number().int().min(3600000, "Minimum voting period is 1 hour"),
  executionDelayMs: z.number().int().min(0),
  cooldownMs: z.number().int().min(0),
});

// --- Tier 1 schemas ---

export const disableProposalTypeSchema = z.object({
  typeKey: z.string().min(1, "Select a type to disable"),
  metadataIpfs,
});

export const transferFreezeAdminSchema = z.object({
  recipient: suiAddress,
  metadataIpfs,
});

export const unfreezeProposalTypeSchema = z.object({
  typeKey: z.string().min(1, "Select a type to unfreeze"),
  metadataIpfs,
});

export const spinOutSubDAOSchema = z.object({
  subDaoId: suiObjectId,
  metadataIpfs,
});

export const emergencyFreezeSchema = z.object({
  typeKey: z.string().min(1, "Select a type to freeze"),
  durationMs: z.number().int().min(3600000, "Minimum freeze is 1 hour"),
  metadataIpfs,
});

export const emergencyUnfreezeSchema = z.object({
  typeKey: z.string().min(1, "Select a type to unfreeze"),
  metadataIpfs,
});

export const capabilityExtractSchema = z.object({
  capObjectId: suiObjectId,
  recipient: suiAddress,
  metadataIpfs,
});

export const spawnDAOSchema = z.object({
  successorDaoId: suiObjectId,
  metadataIpfs,
});

// --- Tier 2 schemas ---

export const treasuryWithdrawSchema = z.object({
  coinType: z.string().min(1, "Select a coin type"),
  amount: z.string().min(1, "Amount is required"),
  recipient: suiAddress,
  metadataIpfs,
});

export const setBoardSchema = z.object({
  members: z
    .array(suiAddress)
    .min(1, "At least one board member is required"),
  metadataIpfs,
});

export const enableProposalTypeSchema = z.object({
  typeKey: z.string().min(1, "Select a proposal type"),
  config: proposalConfigSchema,
  metadataIpfs,
});

export const updateProposalConfigSchema = z.object({
  typeKey: z.string().min(1, "Select a proposal type"),
  config: proposalConfigSchema,
  metadataIpfs,
});

export const charterUpdateSchema = z.object({
  name: z.string().min(1, "Charter name is required"),
  description: z.string().min(1, "Charter description is required"),
  imageUrl: z.string(),
  metadataIpfs,
});

// --- Wizard schema ---

export const createSubDAOSchema = z.object({
  name: z.string().min(1, "SubDAO name is required"),
  metadataIpfs,
  board: z
    .array(suiAddress)
    .min(1, "At least one board member is required"),
  charterName: z.string().min(1, "Charter name is required"),
  charterDescription: z.string().min(1, "Charter description is required"),
  charterImageUrl: z.string(),
  proposalTypes: z
    .array(
      z.object({
        typeKey: z.string().min(1),
        config: proposalConfigSchema,
      }),
    )
    .min(1, "At least one proposal type must be enabled"),
  fundingAmount: z.string(),
});

/** Map of type key → zod schema. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const PROPOSAL_SCHEMAS: Record<string, z.ZodObject<any>> = {
  DisableProposalType: disableProposalTypeSchema,
  TransferFreezeAdmin: transferFreezeAdminSchema,
  UnfreezeProposalType: unfreezeProposalTypeSchema,
  SpinOutSubDAO: spinOutSubDAOSchema,
  EmergencyFreeze: emergencyFreezeSchema,
  EmergencyUnfreeze: emergencyUnfreezeSchema,
  CapabilityExtract: capabilityExtractSchema,
  SpawnDAO: spawnDAOSchema,
  TreasuryWithdraw: treasuryWithdrawSchema,
  SetBoard: setBoardSchema,
  EnableProposalType: enableProposalTypeSchema,
  UpdateProposalConfig: updateProposalConfigSchema,
  CharterUpdate: charterUpdateSchema,
  CreateSubDAO: createSubDAOSchema,
};
