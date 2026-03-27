import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import type { DAOHierarchy } from "@/types/dao";

/**
 * SubDAOGraph — placeholder until @xyflow/react is added.
 * Renders a simple list view of the hierarchy instead of the interactive graph.
 */
export function SubDAOGraph({ hierarchy }: { hierarchy: DAOHierarchy }) {
  return (
    <div className="space-y-3">
      <Card className="border-2 p-4">
        <div className="flex items-center gap-2">
          <span className="font-bold">{hierarchy.root.name}</span>
          <Badge variant="outline">{hierarchy.root.status}</Badge>
          {(hierarchy.root.controllerPaused || hierarchy.root.executionPaused) && (
            <Badge variant="destructive">Paused</Badge>
          )}
        </div>
        {hierarchy.root.childCount > 0 && (
          <span className="text-muted-foreground text-sm">
            {hierarchy.root.childCount} organizational unit{hierarchy.root.childCount !== 1 ? "s" : ""}
          </span>
        )}
      </Card>
      {hierarchy.children.length > 0 && (
        <div className="ml-8 space-y-2 border-l-2 pl-4">
          {hierarchy.children.map((child) => {
            const isPaused = child.controllerPaused || child.executionPaused;
            return (
              <Card key={child.daoId} className="p-3">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-bold">{child.name}</span>
                  <Badge variant="outline" className="text-xs">
                    {child.status}
                  </Badge>
                  {isPaused && (
                    <Badge variant="destructive" className="text-xs">
                      Paused
                    </Badge>
                  )}
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
