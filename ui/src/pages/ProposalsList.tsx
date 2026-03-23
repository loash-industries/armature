import { useState } from "react";
import { useParams, Link } from "@tanstack/react-router";
import { Badge } from "@/components/ui/badge";
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
import {
  Tabs,
  TabsList,
  TabsTrigger,
  TabsContent,
} from "@/components/ui/tabs";
import { useProposals } from "@/hooks/useProposals";
import { PROPOSAL_TYPE_MAP } from "@/config/proposal-types";
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

function truncAddr(addr: string): string {
  if (addr.length <= 12) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function formatDate(ms: number): string {
  return new Date(ms).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function ProposalTable({ proposals }: { proposals: ProposalSummary[] }) {
  const { daoId } = useParams({ strict: false });

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
          <TableHead className="text-right">Yes</TableHead>
          <TableHead className="text-right">No</TableHead>
          <TableHead className="text-right">Created</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {proposals.map((p) => (
          <TableRow key={p.id} className="cursor-pointer">
            <TableCell>
              <Link
                to={`/dao/$daoId/proposals/$proposalId`}
                params={{ daoId: daoId ?? "", proposalId: p.id }}
                className="font-mono text-sm hover:underline"
              >
                <Badge variant="outline">
                  {PROPOSAL_TYPE_MAP[p.typeKey]?.label ?? p.typeKey}
                </Badge>
              </Link>
            </TableCell>
            <TableCell className="font-mono text-xs">
              {truncAddr(p.proposer)}
            </TableCell>
            <TableCell>{statusBadge(p.status)}</TableCell>
            <TableCell className="text-right font-mono text-sm">
              {p.yesWeight}
            </TableCell>
            <TableCell className="text-right font-mono text-sm">
              {p.noWeight}
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
  const [filter, setFilter] = useState<StatusFilter>("all");

  const filtered =
    filter === "all"
      ? (proposals ?? [])
      : (proposals ?? []).filter((p) => p.status === filter);

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Proposals</CardTitle>
          <CardDescription>
            {proposals
              ? `${proposals.length} proposal(s) found`
              : "Loading..."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          ) : (
            <Tabs
              value={filter}
              onValueChange={(v) => setFilter(v as StatusFilter)}
            >
              <TabsList>
                <TabsTrigger value="all">All</TabsTrigger>
                <TabsTrigger value="active">Active</TabsTrigger>
                <TabsTrigger value="passed">Passed</TabsTrigger>
                <TabsTrigger value="executed">Executed</TabsTrigger>
                <TabsTrigger value="expired">Expired</TabsTrigger>
              </TabsList>
              <TabsContent value={filter}>
                <ProposalTable proposals={filtered} />
              </TabsContent>
            </Tabs>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
