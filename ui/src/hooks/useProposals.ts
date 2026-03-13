import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import { queryEvents, multiGetObjects } from "@/lib/sui-rpc";
import { PACKAGE_ID, MODULES } from "@/config/constants";
import type { ProposalSummary } from "@/types/proposal";

interface ProposalFields {
  id: { id: string };
  type_key: string;
  proposer: string;
  yes_weight: string;
  no_weight: string;
  quorum: string;
  approval_threshold: string;
  created_at_ms: string;
  expiry_ms: string;
  execution_delay_ms: string;
  executed: boolean;
  metadata_ipfs: string;
}

function deriveStatus(
  fields: ProposalFields,
): ProposalSummary["status"] {
  if (fields.executed) return "executed";

  const now = Date.now();
  const expiry = Number(fields.created_at_ms) + Number(fields.expiry_ms);

  if (now > expiry) {
    const yes = Number(fields.yes_weight);
    const no = Number(fields.no_weight);
    const total = yes + no;
    const quorumMet = total >= Number(fields.quorum);
    const thresholdMet =
      total > 0 &&
      (yes * 10000) / total >= Number(fields.approval_threshold);
    return quorumMet && thresholdMet ? "passed" : "expired";
  }

  return "active";
}

function parseProposal(obj: {
  data?: { content?: unknown } | null;
}): ProposalSummary | null {
  const content = obj.data?.content as
    | { fields: ProposalFields; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") return null;

  const f = content.fields;
  return {
    id: f.id.id,
    typeKey: f.type_key,
    proposer: f.proposer,
    status: deriveStatus(f),
    yesWeight: Number(f.yes_weight),
    noWeight: Number(f.no_weight),
    quorum: Number(f.quorum),
    approvalThreshold: Number(f.approval_threshold),
    createdMs: Number(f.created_at_ms),
    expiryMs: Number(f.expiry_ms),
    executionDelayMs: Number(f.execution_delay_ms),
    metadataIpfs: f.metadata_ipfs,
  };
}

/** Fetch all proposals for a DAO via ProposalCreated events. */
export function useProposals(daoId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.proposals(daoId),
    queryFn: async (): Promise<ProposalSummary[]> => {
      const result = await queryEvents(
        client,
        { MoveModule: { package: PACKAGE_ID, module: MODULES.proposal } },
        undefined,
        100,
      );

      const proposalIds: string[] = [];
      for (const ev of result.data) {
        const parsed = ev.parsedJson as Record<string, unknown>;
        if ((parsed.dao_id as string) === daoId && parsed.proposal_id) {
          proposalIds.push(parsed.proposal_id as string);
        }
      }

      if (proposalIds.length === 0) return [];

      const objects = await multiGetObjects(client, proposalIds);
      const proposals: ProposalSummary[] = [];
      for (const obj of objects) {
        const p = parseProposal(obj);
        if (p) proposals.push(p);
      }

      proposals.sort((a, b) => b.createdMs - a.createdMs);
      return proposals;
    },
    enabled: !!daoId,
  });
}

/** Fetch a single proposal by ID. */
export function useProposal(proposalId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.proposal(proposalId),
    queryFn: async (): Promise<ProposalSummary | null> => {
      const objects = await multiGetObjects(client, [proposalId]);
      return objects[0] ? parseProposal(objects[0]) : null;
    },
    enabled: !!proposalId,
  });
}
