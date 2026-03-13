import { Link } from "@tanstack/react-router";
import { Card, CardHeader, CardTitle, CardContent, Badge } from "@awar.dev/ui";
import type { SubDAONode } from "@/types/dao";

export function SubDAOCard({
  node,
}: {
  node: SubDAONode;
}) {
  const isPaused = node.controllerPaused || node.executionPaused;

  return (
    <Link
      to="/dao/$daoId"
      params={{ daoId: node.daoId }}
      className="block no-underline"
    >
      <Card className="hover:border-primary/50 transition-colors">
        <CardHeader>
          <div className="flex items-center justify-between gap-2">
            <CardTitle className="truncate text-base">{node.name}</CardTitle>
            <div className="flex gap-1">
              {isPaused && (
                <Badge variant="destructive">Paused</Badge>
              )}
              <Badge variant="outline">{node.status}</Badge>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="text-muted-foreground flex items-center gap-4 text-sm">
            {node.childCount > 0 && (
              <span>{node.childCount} sub-DAO{node.childCount !== 1 ? "s" : ""}</span>
            )}
            {node.controllerPaused && (
              <span className="text-destructive">Controller paused</span>
            )}
            {node.executionPaused && (
              <span className="text-destructive">Execution paused</span>
            )}
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}
