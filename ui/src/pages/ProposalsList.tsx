import { useState } from "react";
import { useParams, useNavigate, Link } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableHeader,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
} from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { useProposals } from "@/hooks/useProposals";
import { useGovernanceDetail } from "@/hooks/useDao";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { PROPOSAL_TYPE_MAP } from "@/config/proposal-types";
import { AddressName } from "@/components/AddressName";
import type { ProposalSummary } from "@/types/proposal";

type StatusFilter = "all" | "active" | "passed" | "executed" | "expired";

function statusBadge(status: ProposalSummary["status"]) {
  const variants: Record<
    string,
    "default" | "secondary" | "destructive" | "outline"
  > = {
    active: "default",
    passed: "outline",
    executed: "secondary",
    expired: "destructive",
  };
  return <Badge variant={variants[status] ?? "outline"}>{status}</Badge>;
}

function formatDate(ms: number): string {
  return new Date(ms).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function VoteBar({
  yesWeight,
  noWeight,
  totalSnapshotWeight,
  // quorum: @todo add when weighted votes are implemented
  approvalThreshold,
}: {
  yesWeight: number;
  noWeight: number;
  totalSnapshotWeight: number;
  quorum: number;
  approvalThreshold: number;
}) {
  const total = yesWeight + noWeight;
  const yesAbsolute =
    totalSnapshotWeight > 0 ? (yesWeight / totalSnapshotWeight) * 100 : 0;
  const noAbsolute =
    totalSnapshotWeight > 0 ? (noWeight / totalSnapshotWeight) * 100 : 0;
  const yesPercent = total > 0 ? (yesWeight / total) * 100 : 0;
  const noPercent = total > 0 ? (noWeight / total) * 100 : 0;
  const approvalLinePercent = approvalThreshold / 100; // bps → fixed % of bar

  return (
    <div className="w-32 space-y-1">
      <div className="flex justify-between text-xs">
        <span className="font-medium text-blue-500">
          {yesWeight}{" "}
          <span className="text-muted-foreground">
            ({yesPercent.toFixed(0)}%)
          </span>
        </span>
        <span className="font-medium text-red-500">
          {noWeight}{" "}
          <span className="text-muted-foreground">
            ({noPercent.toFixed(0)}%)
          </span>
        </span>
      </div>
      <div className="relative h-2 w-full">
        <div className="absolute inset-0 overflow-hidden rounded-full bg-muted">
          <div
            className="absolute left-0 top-0 h-full bg-blue-500 transition-all"
            style={{ width: `${yesAbsolute}%` }}
          />
          <div
            className="absolute top-0 h-full bg-red-500 transition-all"
            style={{ left: `${yesAbsolute}%`, width: `${noAbsolute}%` }}
          />
        </div>
        {approvalLinePercent > 0 && (
          <div
            className="absolute z-10 w-0.5 -top-1 -bottom-1 rounded-sm bg-white/80"
            style={{ left: `${Math.min(approvalLinePercent, 99.5)}%` }}
          />
        )}
      </div>
    </div>
  );
}

function ProposalTable({
  proposals,
  nameMap,
}: {
  proposals: ProposalSummary[];
  nameMap?: Map<string, string | null>;
}) {
  const { daoId } = useParams({ strict: false });
  const navigate = useNavigate();

  if (proposals.length === 0) {
    return (
      <p className="text-muted-foreground py-8 text-center text-sm">
        No proposals found.
      </p>
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Type</TableHead>
          <TableHead>Proposer</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Votes</TableHead>
          <TableHead className="text-right">Created</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {proposals.map((p) => (
          <TableRow
            key={p.id}
            className="cursor-pointer hover:bg-muted/50"
            onClick={() =>
              navigate({
                to: "/dao/$daoId/proposals/$proposalId",
                params: { daoId: daoId ?? "", proposalId: p.id },
              })
            }
          >
            <TableCell>
              <Badge variant="outline">
                {PROPOSAL_TYPE_MAP[p.typeKey]?.label ?? p.typeKey}
              </Badge>
            </TableCell>
            <TableCell className="font-mono text-xs">
              <AddressName address={p.proposer} charName={nameMap?.get(p.proposer)} />
            </TableCell>
            <TableCell>{statusBadge(p.status)}</TableCell>
            <TableCell>
              <VoteBar
                yesWeight={p.yesWeight}
                noWeight={p.noWeight}
                totalSnapshotWeight={p.totalSnapshotWeight}
                quorum={p.quorum}
                approvalThreshold={p.approvalThreshold}
              />
            </TableCell>
            <TableCell className="text-right text-sm">
              {formatDate(p.createdMs)}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function ProposalsList() {
  const { daoId } = useParams({ strict: false });
  const { data: proposals, isLoading } = useProposals(daoId ?? "");
  const { data: governance } = useGovernanceDetail(daoId ?? "");
  const { address } = useWalletSigner();
  const [filter, setFilter] = useState<StatusFilter>("all");

  const isMember =
    governance?.members.some((m) => m.address === address) ?? false;

  const proposerAddresses = [...new Set((proposals ?? []).map((p) => p.proposer))];
  const { data: nameMap } = useCharacterNames(proposerAddresses);

  const filtered =
    filter === "all"
      ? (proposals ?? [])
      : (proposals ?? []).filter((p) => p.status === filter);

  return (
    <div className="space-y-6 w-full">
      <Tabs
        value={filter}
        onValueChange={(v) => setFilter(v as StatusFilter)}
        className="w-full"
      >
        <Card className="w-full">
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle>Proposals</CardTitle>
                <CardDescription>
                  {proposals
                    ? `${proposals.length === 0 ? "No proposals" : proposals.length > 1 ? `${proposals.length} proposals` : "1 proposal"} found`
                    : "Loading..."}
                </CardDescription>
              </div>
              <div className="flex items-center gap-2">
                <TabsList>
                  <TabsTrigger value="all">All</TabsTrigger>
                  <TabsTrigger value="active">Active</TabsTrigger>
                  <TabsTrigger value="passed">Passed</TabsTrigger>
                  <TabsTrigger value="executed">Executed</TabsTrigger>
                  <TabsTrigger value="expired">Expired</TabsTrigger>
                </TabsList>
                {isMember && (
                  <Button
                    size="sm"
                    render={
                      <Link
                        to="/dao/$daoId/proposals/new"
                        params={{ daoId: daoId ?? "" }}
                      />
                    }
                  >
                    <Plus className="mr-1 h-4 w-4" />
                    New Proposal
                  </Button>
                )}
              </div>
            </div>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="space-y-3 gap-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Skeleton key={i} className="h-10 w-full" />
                ))}
              </div>
            ) : (
              <TabsContent value={filter}>
                <ProposalTable proposals={filtered} nameMap={nameMap} />
              </TabsContent>
            )}
          </CardContent>
        </Card>
      </Tabs>
    </div>
  );
}
