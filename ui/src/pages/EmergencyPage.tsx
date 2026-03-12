import { useParams } from "@tanstack/react-router";
import { useEffect, useState } from "react";
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
} from "@awar.dev/ui";
import { useDaoSummary, useEmergencyFreezeDetail } from "@/hooks/useDao";

function formatDuration(ms: number): string {
  const hours = Math.floor(ms / 3_600_000);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return `${days}d ${hours % 24}h`;
}

function CountdownTimer({ expiryMs }: { expiryMs: number }) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const remaining = expiryMs - now;

  if (remaining <= 0) {
    return <Badge variant="outline">Expired</Badge>;
  }

  const hours = Math.floor(remaining / 3_600_000);
  const minutes = Math.floor((remaining % 3_600_000) / 60_000);
  const seconds = Math.floor((remaining % 60_000) / 1_000);

  return (
    <span className="font-mono tabular-nums">
      {hours > 0 && `${hours}h `}
      {minutes}m {seconds}s
    </span>
  );
}

export function EmergencyPage() {
  const { daoId } = useParams({ strict: false });
  const { data: dao, isError: daoError } = useDaoSummary(daoId ?? "");
  const { data: freeze, isLoading } = useEmergencyFreezeDetail(
    dao?.emergencyFreezeId,
  );

  const activeFrozen =
    freeze?.frozenTypes.filter((t) => t.expiryMs > Date.now()) ?? [];

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

      {activeFrozen.length > 0 && (
        <Alert variant="destructive">
          <AlertTitle>Emergency Freeze Active</AlertTitle>
          <AlertDescription>
            {activeFrozen.length} proposal type
            {activeFrozen.length !== 1 ? "s" : ""} currently frozen.
          </AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Freeze Status</CardTitle>
          <CardDescription>
            {isLoading ? (
              "Loading..."
            ) : freeze ? (
              <>
                Max freeze duration:{" "}
                {formatDuration(freeze.maxFreezeDurationMs)}
              </>
            ) : (
              "Unavailable"
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableBody>
              <TableRow>
                <TableCell className="text-muted-foreground">
                  Frozen Types
                </TableCell>
                <TableCell className="text-right">
                  {isLoading ? (
                    <Skeleton className="ml-auto h-5 w-12" />
                  ) : (
                    `${activeFrozen.length} / ${dao?.enabledProposalTypes.length ?? "—"}`
                  )}
                </TableCell>
              </TableRow>
              <TableRow>
                <TableCell className="text-muted-foreground">
                  Max Duration
                </TableCell>
                <TableCell className="text-right">
                  {isLoading ? (
                    <Skeleton className="ml-auto h-5 w-16" />
                  ) : freeze ? (
                    formatDuration(freeze.maxFreezeDurationMs)
                  ) : (
                    "—"
                  )}
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Frozen Types</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          ) : freeze && freeze.frozenTypes.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Type</TableHead>
                  <TableHead className="text-right">Expires In</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {freeze.frozenTypes.map((ft) => (
                  <TableRow key={ft.typeKey}>
                    <TableCell className="font-mono">{ft.typeKey}</TableCell>
                    <TableCell className="text-right">
                      <CountdownTimer expiryMs={ft.expiryMs} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-muted-foreground text-sm">
              No types are currently frozen.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
