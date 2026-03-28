import { useState } from "react";
import { useNavigate, useParams } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useDaoSummary } from "@/hooks/useDao";
import { useDAOHierarchy } from "@/hooks/useSubDAOs";
import { SubDAOCard } from "@/components/SubDAOCard";
import { SubDAOGraph } from "@/components/SubDAOGraph";
// import { ControllerActionsMenu } from "@/components/ControllerActionsMenu";

export function SubDAOListPage() {
  const { daoId } = useParams({ strict: false });
  const navigate = useNavigate();
  const id = daoId ?? "";
  const { data: dao, isLoading: daoLoading } = useDaoSummary(id);
  const {
    data: hierarchy,
    isLoading: hierarchyLoading,
    isError,
  } = useDAOHierarchy(id, dao?.capabilityVaultId);

  const [view, setView] = useState<"list" | "graph">("list");

  const isLoading = daoLoading || hierarchyLoading;
  const children = hierarchy?.children ?? [];

  // const newLocal = <ControllerActionsMenu daoId={id} />;
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold">Organizational Units</h1>
          {!isLoading && (
            <Badge variant="outline">{children.length}</Badge>
          )}
        </div>
        <div className="flex items-center gap-2">
          <div className="flex gap-1">
            <Button
              variant={view === "list" ? "default" : "outline"}
              size="sm"
              onClick={() => setView("list")}
            >
              List
            </Button>
            <Button
              variant={view === "graph" ? "default" : "outline"}
              size="sm"
              onClick={() => setView("graph")}
            >
              Graph
            </Button>
          </div>
          {/* {newLocal} */}
          <Button
            size="sm"
            onClick={() =>
              navigate({
                to: "/dao/$daoId/proposals/new",
                params: { daoId: id },
                search: { type: "CreateSubDAO" },
              })
            }
          >
            <Plus className="mr-1.5 h-4 w-4" />
            Create organizational unit
          </Button>
        </div>
      </div>

      {/* Error state */}
      {isError && (
        <Alert variant="destructive">
          <AlertTitle>Error</AlertTitle>
          <AlertDescription>
            Failed to load sub-DAO hierarchy. Check that the network is reachable.
          </AlertDescription>
        </Alert>
      )}

      {/* Loading skeleton */}
      {isLoading && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-32 w-full" />
          ))}
        </div>
      )}

      {/* Content */}
      {!isLoading && !isError && (
        <>
          {view === "list" ? (
            children.length > 0 ? (
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {children.map((child) => (
                  <SubDAOCard
                    key={child.daoId}
                    node={child}
                  />
                ))}
              </div>
            ) : (
              <div className="text-muted-foreground py-12 text-center text-sm">
                No organizational units found in organization.
              </div>
            )
          ) : hierarchy ? (
            <SubDAOGraph hierarchy={hierarchy} />
          ) : null}
        </>
      )}
    </div>
  );
}
