import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import { queryEvents, multiGetObjects, unwrapMoveStruct } from "@/lib/sui-rpc";
import { PACKAGE_ID, MODULES } from "@/config/constants";
import type { ProposalSummary } from "@/types/proposal";

interface ProposalConfigFields {
  quorum: number;
  approval_threshold: number;
  propose_threshold: string;
  expiry_ms: string;
  execution_delay_ms: string;
  cooldown_ms: string;
}

interface ProposalFields {
  id: { id: string };
  type_key: string;
  proposer: string;
  yes_weight: string;
  no_weight: string;
  config: ProposalConfigFields;
  created_at_ms: string;
  status: { variant: string };
  metadata_ipfs: string;
  votes_cast: { contents: Array<{ key: string; value: boolean }> };
}

function deriveStatus(
  fields: ProposalFields,
): ProposalSummary["status"] {
  const variant = fields.status.variant;
  if (variant === "Executed") return "executed";
  if (variant === "Expired") return "expired";
  if (variant === "Passed") return "passed";

  // Active — check if expired by time
  const cfg = fields.config;
  const now = Date.now();
  const expiry = Number(fields.created_at_ms) + Number(cfg.expiry_ms);

  if (now > expiry) {
    const yes = Number(fields.yes_weight);
    const no = Number(fields.no_weight);
    const total = yes + no;
    const quorumMet = total >= cfg.quorum;
    const thresholdMet =
      total > 0 &&
      (yes * 10000) / total >= cfg.approval_threshold;
    return quorumMet && thresholdMet ? "passed" : "expired";
  }

  return "active";
}

/** Extract the payload type parameter from a Proposal<T> on-chain type string. */
function extractPayloadType(objectType: string): string {
  const start = objectType.indexOf("<");
  const end = objectType.lastIndexOf(">");
  if (start === -1 || end === -1) return "";
  return objectType.slice(start + 1, end);
}

function parseProposal(obj: {
  data?: { content?: unknown; type?: string | null } | null;
}): ProposalSummary | null {
  const content = obj.data?.content as
    | { fields: unknown; dataType: "moveObject"; type?: string | null }
    | undefined;
  if (!content || content.dataType !== "moveObject") return null;

  const f = unwrapMoveStruct(content.fields) as ProposalFields;
  const cfg = f.config;
  const objectType = content.type ?? obj.data?.type ?? "";
  return {
    id: f.id.id,
    typeKey: f.type_key,
    proposer: f.proposer,
    status: deriveStatus(f),
    yesWeight: Number(f.yes_weight),
    noWeight: Number(f.no_weight),
    quorum: cfg.quorum,
    approvalThreshold: cfg.approval_threshold,
    createdMs: Number(f.created_at_ms),
    expiryMs: Number(cfg.expiry_ms),
    executionDelayMs: Number(cfg.execution_delay_ms),
    metadataIpfs: f.metadata_ipfs,
    payloadType: extractPayloadType(objectType),
    votesCast: Object.fromEntries(
      (f.votes_cast?.contents ?? []).map((e) => [e.key, e.value]),
    ),
  };
}

/** Fetch all proposals for a DAO via ProposalCreated events. */
export function useProposals(daoId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.proposals(daoId),
    queryFn: async (): Promise<ProposalSummary[]> => {
      // ProposalCreated is defined in the proposal module but emitted via
      // board_voting::submit_proposal, so Sui indexes it under board_voting.
      const result = await queryEvents(
        client,
        { MoveModule: { package: PACKAGE_ID, module: MODULES.board_voting } },
        undefined,
        100,
      );

      const proposalIdSet = new Set<string>();
      for (const ev of result.data) {
        const parsed = ev.parsedJson as Record<string, unknown>;
        if ((parsed.dao_id as string) === daoId && parsed.proposal_id) {
          proposalIdSet.add(parsed.proposal_id as string);
        }
      }

      const proposalIds = [...proposalIdSet];
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
