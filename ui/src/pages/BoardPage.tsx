import { useParams } from "@tanstack/react-router";
import { useCurrentAccount } from "@mysten/dapp-kit";
import { AddressName } from "@/components/AddressName";
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
import { useDaoSummary, useGovernanceDetail } from "@/hooks/useDao";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { AnimatedValue } from "@/components/ui/AnimatedValue";



export function BoardPage() {
  const { daoId } = useParams({ strict: false });
  const account = useCurrentAccount();
  const { isError: daoError } = useDaoSummary(daoId ?? "");
  const { data: governance, isLoading } = useGovernanceDetail(daoId ?? "");
  const memberAddresses = governance?.members.map((m) => m.address) ?? [];
  const { data: nameMap } = useCharacterNames(memberAddresses);

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
                    {governance.totalShares != null && (
                      <>{" · "}<AnimatedValue value={governance.totalShares} /> total shares</>)}
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
                        <AddressName address={member.address} charName={nameMap?.get(member.address)} />
                      </TableCell>
                      {governance.type !== "Board" && (
                        <TableCell className="text-right font-mono">
                          {member.weight != null ? <AnimatedValue value={member.weight} /> : "—"}
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
          ) : (
            <p className="text-muted-foreground text-sm">No members found.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
