import { useParams } from "@tanstack/react-router";
import { useCurrentAccount } from "@mysten/dapp-kit";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
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
  Tooltip,
  TooltipTrigger,
  TooltipContent,
  TooltipProvider,
} from "@/components/ui/tooltip";
import { useDaoSummary, useGovernanceDetail } from "@/hooks/useDao";

function truncAddr(address: string): string {
  if (address.length <= 12) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function BoardPage() {
  const { daoId } = useParams({ strict: false });
  const account = useCurrentAccount();
  const { isError: daoError } = useDaoSummary(daoId ?? "");
  const { data: governance, isLoading } = useGovernanceDetail(daoId ?? "");

  const connectedAddress = account?.address;

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

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div className="space-y-1">
              <CardTitle>Board</CardTitle>
              <CardDescription>
                {governance && (
                  <>
                    <Badge variant="outline" className="mr-2">
                      {governance.type} Governance
                    </Badge>
                    {governance.members.length} member
                    {governance.members.length !== 1 ? "s" : ""}
                    {governance.totalShares != null &&
                      ` · ${governance.totalShares.toLocaleString()} total shares`}
                  </>
                )}
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          ) : governance && governance.members.length > 0 ? (
            <TooltipProvider>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Address</TableHead>
                    {governance.type !== "Board" && (
                      <TableHead className="text-right">Weight</TableHead>
                    )}
                    <TableHead className="w-20" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {governance.members.map((member) => (
                    <TableRow key={member.address}>
                      <TableCell>
                        <Tooltip>
                          <TooltipTrigger className="font-mono">
                            {truncAddr(member.address)}
                          </TooltipTrigger>
                          <TooltipContent>
                            <p className="font-mono text-xs">
                              {member.address}
                            </p>
                          </TooltipContent>
                        </Tooltip>
                      </TableCell>
                      {governance.type !== "Board" && (
                        <TableCell className="text-right font-mono">
                          {member.weight?.toLocaleString() ?? "—"}
                        </TableCell>
                      )}
                      <TableCell className="text-right">
                        {member.address === connectedAddress && (
                          <Badge variant="outline">You</Badge>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TooltipProvider>
          ) : (
            <p className="text-muted-foreground text-sm">No members found.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
