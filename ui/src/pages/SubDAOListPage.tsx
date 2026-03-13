import { useState } from "react";
import { useParams } from "@tanstack/react-router";
import {
  Button,
  Badge,
  Skeleton,
  Alert,
  AlertTitle,
  AlertDescription,
} from "@awar.dev/ui";
import { useDaoSummary } from "@/hooks/useDao";
import { useDAOHierarchy } from "@/hooks/useSubDAOs";
import { SubDAOCard } from "@/components/SubDAOCard";
import { SubDAOGraph } from "@/components/SubDAOGraph";
import { ControllerActionsMenu } from "@/components/ControllerActionsMenu";

export function SubDAOListPage() {
  const { daoId } = useParams({ strict: false });
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

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold">Sub-DAOs</h1>
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
          <ControllerActionsMenu daoId={id} />
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
                No sub-DAOs found. This DAO has no child DAOs.
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
