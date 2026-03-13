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
              ? `${enabledCount} of ${types.length} types enabled`
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
                  <TableRow
                    key={item.typeKey}
                    className={!item.enabled ? "opacity-50" : undefined}
                  >
                    <TableCell className="font-mono text-sm">
                      {item.typeKey}
                    </TableCell>
                    <TableCell>
                      <TypeBadges item={item} />
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {item.config ? formatBps(item.config.quorum) : "—"}
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {item.config
                        ? formatBps(item.config.approvalThreshold)
                        : "—"}
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {item.config
                        ? formatDuration(item.config.expiryMs)
                        : "—"}
                    </TableCell>
                    <TableCell className="text-right font-mono text-sm">
                      {item.config
                        ? formatDuration(item.config.cooldownMs)
                        : "—"}
                    </TableCell>
                  </TableRow>
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
