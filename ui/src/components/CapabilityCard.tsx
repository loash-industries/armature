import { Link } from "@tanstack/react-router";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
} from "@/components/ui/card";
import type { CapabilityEntry } from "@/types/dao";
import { CapabilityActions } from "./CapabilityActions";

function truncateId(id: string): string {
  if (id.length <= 14) return id;
  return `${id.slice(0, 8)}...${id.slice(-4)}`;
}

export function CapabilityCard({
  entry,
  daoId,
}: {
  entry: CapabilityEntry;
  daoId: string;
}) {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between gap-2">
          <CardTitle className="truncate text-base">
            {entry.shortType}
          </CardTitle>
          <div className="flex items-center gap-1">
            {entry.isSubDAOControl && (
              <Badge variant="secondary">Controller</Badge>
            )}
            <CapabilityActions entry={entry} daoId={daoId} />
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Object ID</span>
            <span className="font-mono">{truncateId(entry.id)}</span>
          </div>
          {entry.isSubDAOControl && entry.subdaoId && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">Controls</span>
              <Link
                to="/dao/$daoId"
                params={{ daoId: entry.subdaoId }}
                className="text-primary font-mono hover:underline"
              >
                {truncateId(entry.subdaoId)}
              </Link>
            </div>
          )}
          <div className="flex justify-between">
            <span className="text-muted-foreground">Type</span>
            <span
              className="max-w-[200px] truncate text-xs"
              title={entry.typeName}
            >
              {entry.typeName}
            </span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
