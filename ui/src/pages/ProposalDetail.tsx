import { useState, useEffect } from "react";
import { useParams } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Badge,
  Button,
  Skeleton,
  Progress,
  Separator,
} from "@awar.dev/ui";
import { useSuiClient } from "@mysten/dapp-kit";
import { useProposal } from "@/hooks/useProposals";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { buildVote, buildTryExpire } from "@/lib/transactions";
import { cacheKeys } from "@/lib/cache-keys";
import { PROPOSAL_TYPE_MAP } from "@/config/proposal-types";

function truncAddr(addr: string): string {
  if (addr.length <= 12) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function formatBps(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`;
}

function formatDate(ms: number): string {
  return new Date(ms).toLocaleString();
}

function Countdown({ targetMs }: { targetMs: number }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 60_000);
    return () => clearInterval(id);
  }, []);

  const diff = targetMs - now;
  if (diff <= 0) return <span className="text-muted-foreground">Ended</span>;

  const hours = Math.floor(diff / 3600000);
  const mins = Math.floor((diff % 3600000) / 60000);
  if (hours > 24) {
    const days = Math.floor(hours / 24);
    return (
      <span className="font-mono">
        {days}d {hours % 24}h remaining
      </span>
    );
  }
  return (
    <span className="font-mono">
      {hours}h {mins}m remaining
    </span>
  );
}

function statusVariant(
  status: string,
): "default" | "secondary" | "destructive" | "outline" {
  const map: Record<
    string,
    "default" | "secondary" | "destructive" | "outline"
  > = {
    active: "default",
    passed: "outline",
    executed: "secondary",
    expired: "destructive",
  };
  return map[status] ?? "outline";
}

export function ProposalDetail() {
  const { proposalId, daoId } = useParams({ strict: false });
  const { data: proposal, isLoading } = useProposal(proposalId ?? "");
  const client = useSuiClient();
  const { signAndExecuteTransaction } = useWalletSigner();
  const queryClient = useQueryClient();
  const [actionPending, setActionPending] = useState<string | null>(null);

  async function handleVote(approve: boolean) {
    if (!proposal?.payloadType) {
      toast.error("Cannot determine proposal type for voting");
      return;
    }
    setActionPending(approve ? "yes" : "no");
    try {
      const transaction = buildVote({
        proposalId: proposal.id,
        approve,
        proposalType: proposal.payloadType,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success(approve ? "Voted Yes" : "Voted No");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal.id),
      });
      if (daoId) {
        await queryClient.invalidateQueries({
          queryKey: cacheKeys.proposals(daoId),
        });
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Vote failed");
    } finally {
      setActionPending(null);
    }
  }

  async function handleExpire() {
    if (!proposal?.payloadType) {
      toast.error("Cannot determine proposal type");
      return;
    }
    setActionPending("expire");
    try {
      const transaction = buildTryExpire({
        proposalId: proposal.id,
        proposalType: proposal.payloadType,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success("Proposal marked as expired");
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.proposal(proposal.id),
      });
      if (daoId) {
        await queryClient.invalidateQueries({
          queryKey: cacheKeys.proposals(daoId),
        });
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Expire failed");
    } finally {
      setActionPending(null);
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-48 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  if (!proposal) {
    return (
      <Card>
        <CardContent className="py-8 text-center">
          <p className="text-muted-foreground">Proposal not found.</p>
        </CardContent>
      </Card>
    );
  }

  const typeDef = PROPOSAL_TYPE_MAP[proposal.typeKey];
  const totalVotes = proposal.yesWeight + proposal.noWeight;
  const yesPercent = totalVotes > 0 ? (proposal.yesWeight / totalVotes) * 100 : 0;
  const noPercent = totalVotes > 0 ? (proposal.noWeight / totalVotes) * 100 : 0;
  const quorumPercent =
    proposal.quorum > 0
      ? Math.min((totalVotes / proposal.quorum) * 100, 100)
      : 100;
  const expiryTimestamp = proposal.createdMs + proposal.expiryMs;
  const executableAt = expiryTimestamp + proposal.executionDelayMs;

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      {/* Left: content */}
      <div className="space-y-4 lg:col-span-2">
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle>
                  {typeDef?.label ?? proposal.typeKey}
                </CardTitle>
                <CardDescription>
                  Proposed by {truncAddr(proposal.proposer)}
                </CardDescription>
              </div>
              <Badge variant={statusVariant(proposal.status)}>
                {proposal.status}
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-muted-foreground">Created:</span>{" "}
                {formatDate(proposal.createdMs)}
              </div>
              <div>
                <span className="text-muted-foreground">Expires:</span>{" "}
                {formatDate(expiryTimestamp)}
              </div>
              <div>
                <span className="text-muted-foreground">Quorum:</span>{" "}
                {formatBps(proposal.quorum)}
              </div>
              <div>
                <span className="text-muted-foreground">Threshold:</span>{" "}
                {formatBps(proposal.approvalThreshold)}
              </div>
            </div>
            {proposal.status === "active" && (
              <div>
                <span className="text-muted-foreground text-sm">
                  Voting ends:{" "}
                </span>
                <Countdown targetMs={expiryTimestamp} />
              </div>
            )}
            {proposal.status === "passed" && proposal.executionDelayMs > 0 && (
              <div>
                <span className="text-muted-foreground text-sm">
                  Executable in:{" "}
                </span>
                <Countdown targetMs={executableAt} />
              </div>
            )}
            {proposal.metadataIpfs && (
              <div className="text-sm">
                <span className="text-muted-foreground">Metadata:</span>{" "}
                <span className="font-mono text-xs">
                  {proposal.metadataIpfs}
                </span>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Right: voting panel */}
      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Votes</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <div className="mb-1 flex justify-between text-sm">
                <span>Yes</span>
                <span className="font-mono">
                  {proposal.yesWeight} ({yesPercent.toFixed(1)}%)
                </span>
              </div>
              <Progress value={yesPercent} className="h-2" />
            </div>
            <div>
              <div className="mb-1 flex justify-between text-sm">
                <span>No</span>
                <span className="font-mono">
                  {proposal.noWeight} ({noPercent.toFixed(1)}%)
                </span>
              </div>
              <Progress value={noPercent} className="h-2" />
            </div>

            <Separator />

            <div>
              <div className="mb-1 flex justify-between text-sm">
                <span>Quorum</span>
                <span className="font-mono">
                  {totalVotes} / {proposal.quorum} (
                  {quorumPercent.toFixed(0)}%)
                </span>
              </div>
              <Progress value={quorumPercent} className="h-2" />
            </div>

            <Separator />

            {proposal.status === "active" && (
              <div className="flex gap-2">
                <Button
                  className="flex-1"
                  disabled={actionPending !== null}
                  onClick={() => handleVote(true)}
                >
                  {actionPending === "yes" ? "Voting..." : "Vote Yes"}
                </Button>
                <Button
                  variant="destructive"
                  className="flex-1"
                  disabled={actionPending !== null}
                  onClick={() => handleVote(false)}
                >
                  {actionPending === "no" ? "Voting..." : "Vote No"}
                </Button>
              </div>
            )}

            {proposal.status === "passed" && (
              <Button
                className="w-full"
                disabled={actionPending !== null}
                onClick={() =>
                  toast.info("Execute is not yet implemented — requires DAO object IDs")
                }
              >
                Execute Proposal
              </Button>
            )}

            {proposal.status === "active" && (
              <Button
                variant="outline"
                className="w-full"
                disabled={actionPending !== null}
                onClick={() => handleExpire()}
              >
                {actionPending === "expire" ? "Processing..." : "Mark Expired"}
              </Button>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
