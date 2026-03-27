import { useParams } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableHeader,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
} from "@/components/ui/table";
import { useSuiClient } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useDaoSummary, useEmergencyFreezeDetail } from "@/hooks/useDao";
import { useFreezeAdminCap } from "@/hooks/useFreezeAdminCap";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { buildFreezeType, buildUnfreezeType } from "@/lib/transactions";
import { cacheKeys } from "@/lib/cache-keys";

function formatDuration(ms: number): string {
  const hours = Math.floor(ms / 3_600_000);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return `${days}d ${hours % 24}h`;
}

function CountdownTimer({ expiryMs }: { expiryMs: number }) {
  const [now, setNow] = useState(Date.now);

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
  const { data: freezeAdminCapId } = useFreezeAdminCap(daoId ?? "");
  const { signAndExecuteTransaction } = useWalletSigner();
  const client = useSuiClient();
  const queryClient = useQueryClient();
  const [freezeTarget, setFreezeTarget] = useState("");
  const [unfreezeTarget, setUnfreezeTarget] = useState("");
  const [actionPending, setActionPending] = useState<string | null>(null);

  const activeFrozen =
    freeze?.frozenTypes.filter((t) => t.expiryMs > Date.now()) ?? [];
  const isAdmin = !!freezeAdminCapId;

  async function handleFreeze() {
    if (!dao || !freezeAdminCapId || !freezeTarget) return;
    setActionPending("freeze");
    try {
      const transaction = buildFreezeType({
        emergencyFreezeId: dao.emergencyFreezeId,
        freezeAdminCapId,
        typeKey: freezeTarget,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success(`Frozen: ${freezeTarget}`);
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.dao(daoId ?? ""),
      });
      setFreezeTarget("");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Freeze failed");
    } finally {
      setActionPending(null);
    }
  }

  async function handleUnfreeze() {
    if (!dao || !freezeAdminCapId || !unfreezeTarget) return;
    setActionPending("unfreeze");
    try {
      const transaction = buildUnfreezeType({
        emergencyFreezeId: dao.emergencyFreezeId,
        freezeAdminCapId,
        typeKey: unfreezeTarget,
      });
      const result = await signAndExecuteTransaction({ transaction });
      toast.success(`Unfrozen: ${unfreezeTarget}`);
      await client.waitForTransaction({ digest: result.digest });
      await queryClient.invalidateQueries({
        queryKey: cacheKeys.dao(daoId ?? ""),
      });
      setUnfreezeTarget("");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Unfreeze failed");
    } finally {
      setActionPending(null);
    }
  }

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

      {isAdmin && (
        <Card>
          <CardHeader>
            <CardTitle>Admin Actions</CardTitle>
            <CardDescription>
              You hold the FreezeAdminCap for this DAO
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <p className="text-sm font-medium">Freeze a Proposal Type</p>
              <div className="flex gap-2">
                <Select
                  value={freezeTarget}
                  onValueChange={(v) => setFreezeTarget(v ?? "")}
                >
                  <SelectTrigger className="flex-1">
                    <SelectValue placeholder="Select type to freeze..." />
                  </SelectTrigger>
                  <SelectContent>
                    {dao?.enabledProposalTypes
                      .filter((t) => !activeFrozen.some((f) => f.typeKey === t))
                      .map((t) => (
                        <SelectItem key={t} value={t}>
                          {t}
                        </SelectItem>
                      ))}
                  </SelectContent>
                </Select>
                <Button
                  variant="destructive"
                  disabled={!freezeTarget || actionPending !== null}
                  onClick={handleFreeze}
                >
                  {actionPending === "freeze" ? "Freezing..." : "Freeze"}
                </Button>
              </div>
            </div>

            <Separator />

            <div className="space-y-2">
              <p className="text-sm font-medium">Unfreeze a Proposal Type</p>
              <div className="flex gap-2">
                <Select
                  value={unfreezeTarget}
                  onValueChange={(v) => setUnfreezeTarget(v ?? "")}
                >
                  <SelectTrigger className="flex-1">
                    <SelectValue placeholder="Select type to unfreeze..." />
                  </SelectTrigger>
                  <SelectContent>
                    {activeFrozen.map((f) => (
                      <SelectItem key={f.typeKey} value={f.typeKey}>
                        {f.typeKey}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Button
                  disabled={!unfreezeTarget || actionPending !== null}
                  onClick={handleUnfreeze}
                >
                  {actionPending === "unfreeze" ? "Unfreezing..." : "Unfreeze"}
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
