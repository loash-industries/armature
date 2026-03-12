import { useParams } from "@tanstack/react-router";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
  Skeleton,
  Alert,
  AlertTitle,
  AlertDescription,
} from "@awar.dev/ui";
import { useDaoSummary, useCharterDetail } from "@/hooks/useDao";

export function CharterPage() {
  const { daoId } = useParams({ strict: false });
  const { data: dao, isError: daoError } = useDaoSummary(daoId ?? "");
  const { data: charter, isLoading } = useCharterDetail(dao?.charterId);

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
          <CardTitle>
            {isLoading ? (
              <Skeleton className="h-8 w-48" />
            ) : (
              charter?.name ?? "Charter"
            )}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-3/4" />
              <Skeleton className="h-4 w-1/2" />
            </div>
          ) : charter ? (
            <>
              {charter.imageUrl && (
                <div className="overflow-hidden rounded border">
                  <img
                    src={charter.imageUrl}
                    alt={`${charter.name} charter image`}
                    className="h-auto max-h-64 w-full object-cover"
                  />
                </div>
              )}
              <div className="prose prose-invert max-w-none">
                <p className="text-muted-foreground whitespace-pre-wrap">
                  {charter.description || "No description provided."}
                </p>
              </div>
            </>
          ) : (
            <p className="text-muted-foreground text-sm">
              Charter data unavailable.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
