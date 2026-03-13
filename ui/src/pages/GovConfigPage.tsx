import { useState } from "react";
import { useParams } from "@tanstack/react-router";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  Badge,
  Button,
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

// --- Warning thresholds (#54) ---

/** Types where low quorum/approval is a security risk. */
const SECURITY_SENSITIVE = new Set([
  "EmergencyFreeze",
  "EmergencyUnfreeze",
  "TransferFreezeAdmin",
  "UnfreezeProposalType",
]);

/** Types where supermajority is strongly recommended. */
const GOVERNANCE_TYPES = new Set(["SetBoard", "CharterUpdate"]);

/** Types that should not be disabled (guard for #55). */
const UNDISABLEABLE = new Set([
  "TransferFreezeAdmin",
  "UnfreezeProposalType",
]);

type Severity = "ok" | "warn" | "critical";

function quorumSeverity(typeKey: string, quorum: number): Severity {
  if (SECURITY_SENSITIVE.has(typeKey) && quorum < 5000) return "critical";
  if (quorum < 3000) return "warn";
  return "ok";
}

function approvalSeverity(typeKey: string, threshold: number): Severity {
  if (SECURITY_SENSITIVE.has(typeKey) && threshold < 6600) return "critical";
  if (GOVERNANCE_TYPES.has(typeKey) && threshold < 6600) return "warn";
  return "ok";
}

function severityColor(s: Severity): string {
  if (s === "critical") return "text-red-500";
  if (s === "warn") return "text-yellow-500";
  return "";
}

function configWarnings(item: ProposalTypeConfig): string[] {
  if (!item.config || !item.enabled) return [];
  const warnings: string[] = [];
  const qs = quorumSeverity(item.typeKey, item.config.quorum);
  const as_ = approvalSeverity(item.typeKey, item.config.approvalThreshold);
  if (qs === "critical")
    warnings.push(
      `Quorum is below 50% on security-sensitive type ${item.typeKey}`,
    );
  else if (qs === "warn") warnings.push(`Quorum is below 30%`);
  if (as_ === "critical")
    warnings.push(
      `Approval threshold is below 66% on security-sensitive type ${item.typeKey}`,
    );
  else if (as_ === "warn")
    warnings.push(
      `Approval threshold is below 66% — supermajority recommended for governance types`,
    );
  return warnings;
}

// --- Formatters ---

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

// --- Components ---

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
  className,
}: {
  label: string;
  value: string;
  className?: string;
}) {
  return (
    <div className="flex justify-between py-1.5">
      <span className="text-muted-foreground text-sm">{label}</span>
      <span className={`font-mono text-sm ${className ?? ""}`}>{value}</span>
    </div>
  );
}

function TypeDetailPanel({ item }: { item: ProposalTypeConfig }) {
  const { daoId } = useParams({ strict: false });

  if (!item.config) {
    return (
      <div className="flex items-center justify-between py-2">
        <p className="text-muted-foreground text-sm">
          No configuration — type is disabled.
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            window.location.hash = `/dao/${daoId}/proposals?action=enable&type=${item.typeKey}`;
          }}
        >
          Propose Enable
        </Button>
      </div>
    );
  }

  const { config } = item;
  const qs = quorumSeverity(item.typeKey, config.quorum);
  const as_ = approvalSeverity(item.typeKey, config.approvalThreshold);
  const warnings = configWarnings(item);
  const canDisable = item.enabled && !UNDISABLEABLE.has(item.typeKey);

  return (
    <div className="space-y-3">
      {warnings.length > 0 && (
        <Alert variant="destructive">
          <AlertTitle>Configuration Warning</AlertTitle>
          <AlertDescription>
            <ul className="list-inside list-disc">
              {warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
          </AlertDescription>
        </Alert>
      )}
      <div className="grid grid-cols-2 gap-x-8 sm:grid-cols-3">
        <div className="col-span-1">
          <ConfigDetail
            label="Quorum"
            value={formatBps(config.quorum)}
            className={severityColor(qs)}
          />
        </div>
        <div className="col-span-1">
          <ConfigDetail
            label="Approval Threshold"
            value={formatBps(config.approvalThreshold)}
            className={severityColor(as_)}
          />
        </div>
        <div className="col-span-1">
          <ConfigDetail
            label="Propose Threshold"
            value={
              config.proposeThreshold === 0
                ? "None"
                : String(config.proposeThreshold)
            }
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
      <div className="flex gap-2 pt-1">
        <Button
          variant="outline"
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            window.location.hash = `/dao/${daoId}/proposals?action=update-config&type=${item.typeKey}`;
          }}
        >
          Propose Config Change
        </Button>
        {canDisable && (
          <Button
            variant="destructive"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              window.location.hash = `/dao/${daoId}/proposals?action=disable&type=${item.typeKey}`;
            }}
          >
            Propose Disable
          </Button>
        )}
      </div>
    </div>
  );
}

function TypeRow({ item }: { item: ProposalTypeConfig }) {
  const [open, setOpen] = useState(false);
  const colCount = 6;

  const hasWarning =
    item.config && item.enabled && configWarnings(item).length > 0;

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
              {hasWarning && (
                <span className="ml-2 inline-block text-yellow-500">!</span>
              )}
            </TableCell>
            <TableCell>
              <TypeBadges item={item} />
            </TableCell>
            <TableCell
              className={`text-right font-mono text-sm ${item.config ? severityColor(quorumSeverity(item.typeKey, item.config.quorum)) : ""}`}
            >
              {item.config ? formatBps(item.config.quorum) : "—"}
            </TableCell>
            <TableCell
              className={`text-right font-mono text-sm ${item.config ? severityColor(approvalSeverity(item.typeKey, item.config.approvalThreshold)) : ""}`}
            >
              {item.config
                ? formatBps(item.config.approvalThreshold)
                : "—"}
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
  const warningCount =
    types?.filter((t) => t.enabled && configWarnings(t).length > 0).length ?? 0;

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

      {warningCount > 0 && (
        <Alert>
          <AlertTitle>Configuration Warnings</AlertTitle>
          <AlertDescription>
            {warningCount} proposal type{warningCount !== 1 ? "s have" : " has"}{" "}
            configs below recommended thresholds. Expand rows for details.
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
