import { useState } from "react";
import { useParams } from "@tanstack/react-router";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Badge,
  Skeleton,
  Alert,
  AlertTitle,
  AlertDescription,
  Table,
  TableHeader,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
  Tooltip,
  TooltipTrigger,
  TooltipContent,
  TooltipProvider,
  Collapsible,
  CollapsibleTrigger,
  CollapsibleContent,
} from "@awar.dev/ui";
import { useDaoSummary, useGovernanceConfig } from "@/hooks/useDao";
import type { ProposalTypeConfig } from "@/types/dao";

function formatDuration(ms: number): string {
  if (ms === 0) return "None";
  const hours = Math.floor(ms / 3_600_000);
  if (hours < 1) return `${Math.floor(ms / 60_000)}m`;
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  const rem = hours % 24;
  return rem > 0 ? `${days}d ${rem}h` : `${days}d`;
}

function formatBps(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`;
}

function TypeBadges({ item }: { item: ProposalTypeConfig }) {
  return (
    <div className="flex items-center gap-1.5">
      {item.enabled ? (
        <Badge variant="default">Enabled</Badge>
      ) : (
        <Badge variant="secondary">Disabled</Badge>
      )}
      {item.frozen && <Badge variant="destructive">Frozen</Badge>}
      {item.protected && (
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger>
              <Badge variant="outline">Protected</Badge>
            </TooltipTrigger>
            <TooltipContent>
              <p className="text-xs">Cannot be frozen or disabled</p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      )}
    </div>
  );
}

function ConfigDetail({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="flex justify-between py-1.5">
      <span className="text-muted-foreground text-sm">{label}</span>
      <span className="font-mono text-sm">{value}</span>
    </div>
  );
}

function TypeDetailPanel({ item }: { item: ProposalTypeConfig }) {
  if (!item.config) {
    return (
      <p className="text-muted-foreground py-2 text-sm">
        No configuration — type is disabled.
      </p>
    );
  }

  const { config } = item;

  return (
    <div className="divide-border grid grid-cols-2 gap-x-8 divide-y sm:grid-cols-3">
      <div className="col-span-1">
        <ConfigDetail label="Quorum" value={formatBps(config.quorum)} />
      </div>
      <div className="col-span-1">
        <ConfigDetail
          label="Approval Threshold"
          value={formatBps(config.approvalThreshold)}
        />
      </div>
      <div className="col-span-1">
        <ConfigDetail
          label="Propose Threshold"
          value={config.proposeThreshold === 0 ? "None" : String(config.proposeThreshold)}
        />
      </div>
      <div className="col-span-1">
        <ConfigDetail
          label="Voting Period"
          value={formatDuration(config.expiryMs)}
        />
      </div>
      <div className="col-span-1">
        <ConfigDetail
          label="Execution Delay"
          value={formatDuration(config.executionDelayMs)}
        />
      </div>
      <div className="col-span-1">
        <ConfigDetail
          label="Cooldown"
          value={formatDuration(config.cooldownMs)}
        />
      </div>
    </div>
  );
}

function TypeRow({ item }: { item: ProposalTypeConfig }) {
  const [open, setOpen] = useState(false);
  const colCount = 6;

  return (
    <Collapsible open={open} onOpenChange={setOpen} asChild>
      <>
        <CollapsibleTrigger asChild>
          <TableRow
            className={`cursor-pointer ${!item.enabled ? "opacity-50" : ""}`}
          >
            <TableCell className="font-mono text-sm">
              <span className="mr-1.5 inline-block w-3 text-center text-xs">
                {open ? "▾" : "▸"}
              </span>
              {item.typeKey}
            </TableCell>
            <TableCell>
              <TypeBadges item={item} />
            </TableCell>
            <TableCell className="text-right font-mono text-sm">
              {item.config ? formatBps(item.config.quorum) : "—"}
            </TableCell>
            <TableCell className="text-right font-mono text-sm">
              {item.config ? formatBps(item.config.approvalThreshold) : "—"}
            </TableCell>
            <TableCell className="text-right font-mono text-sm">
              {item.config ? formatDuration(item.config.expiryMs) : "—"}
            </TableCell>
            <TableCell className="text-right font-mono text-sm">
              {item.config ? formatDuration(item.config.cooldownMs) : "—"}
            </TableCell>
          </TableRow>
        </CollapsibleTrigger>
        <CollapsibleContent asChild>
          <TableRow>
            <TableCell colSpan={colCount} className="bg-muted/30 px-6 py-4">
              <TypeDetailPanel item={item} />
            </TableCell>
          </TableRow>
        </CollapsibleContent>
      </>
    </Collapsible>
  );
}

export function GovConfigPage() {
  const { daoId } = useParams({ strict: false });
  const { isError: daoError } = useDaoSummary(daoId ?? "");
  const { data: types, isLoading } = useGovernanceConfig(daoId ?? "");

  const enabledCount = types?.filter((t) => t.enabled).length ?? 0;
  const frozenCount = types?.filter((t) => t.frozen).length ?? 0;

  return (
    <div className="space-y-6">
      {daoError && (
        <Alert variant="destructive">
          <AlertTitle>Connection Error</AlertTitle>
          <AlertDescription>
            Could not fetch DAO data. Check that the network is reachable.
          </AlertDescription>
        </Alert>
      )}

      {frozenCount > 0 && (
        <Alert variant="destructive">
          <AlertTitle>Emergency Freeze Active</AlertTitle>
          <AlertDescription>
            {frozenCount} proposal type{frozenCount !== 1 ? "s" : ""} currently
            frozen.
          </AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Proposal Types</CardTitle>
          <CardDescription>
            {types
              ? `${enabledCount} of ${types.length} types enabled — click a row for details`
              : "Loading..."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          ) : types && types.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Type</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Quorum</TableHead>
                  <TableHead className="text-right">Approval</TableHead>
                  <TableHead className="text-right">Voting Period</TableHead>
                  <TableHead className="text-right">Cooldown</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {types.map((item) => (
                  <TypeRow key={item.typeKey} item={item} />
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground text-sm">
              No proposal types configured.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
