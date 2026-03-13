import { useState } from "react";
import { useParams } from "@tanstack/react-router";
import {
  Badge,
  Skeleton,
  Alert,
  AlertTitle,
  AlertDescription,
  Button,
} from "@awar.dev/ui";
import { useDaoSummary } from "@/hooks/useDao";
import { useCapabilityVaultEntries } from "@/hooks/useCapabilityVault";
import { CapabilityCard } from "@/components/CapabilityCard";

export function CapVaultPage() {
  const { daoId } = useParams({ strict: false });
  const id = daoId ?? "";
  const { data: dao, isLoading: daoLoading } = useDaoSummary(id);
  const {
    data: entries,
    isLoading: entriesLoading,
    isError,
  } = useCapabilityVaultEntries(dao?.capabilityVaultId);

  const [typeFilter, setTypeFilter] = useState<string | null>(null);

  const isLoading = daoLoading || entriesLoading;
  const allEntries = entries ?? [];

  // Collect unique short types for filtering
  const uniqueTypes = [...new Set(allEntries.map((e) => e.shortType))].sort();

  const filtered = typeFilter
    ? allEntries.filter((e) => e.shortType === typeFilter)
    : allEntries;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold">Capability Vault</h1>
          {!isLoading && (
            <Badge variant="outline">
              {allEntries.length} capabilit{allEntries.length !== 1 ? "ies" : "y"}
            </Badge>
          )}
        </div>
      </div>

      {/* Error state */}
      {isError && (
        <Alert variant="destructive">
          <AlertTitle>Error</AlertTitle>
          <AlertDescription>
            Failed to load capability vault. Check that the network is
            reachable.
          </AlertDescription>
        </Alert>
      )}

      {/* Type filter pills */}
      {!isLoading && uniqueTypes.length > 1 && (
        <div className="flex flex-wrap gap-2">
          <Button
            variant={typeFilter === null ? "default" : "outline"}
            size="sm"
            onClick={() => setTypeFilter(null)}
          >
            All
          </Button>
          {uniqueTypes.map((t) => (
            <Button
              key={t}
              variant={typeFilter === t ? "default" : "outline"}
              size="sm"
              onClick={() => setTypeFilter(t)}
            >
              {t}
            </Button>
          ))}
        </div>
      )}

      {/* Loading skeleton */}
      {isLoading && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-40 w-full" />
          ))}
        </div>
      )}

      {/* Content */}
      {!isLoading && !isError && (
        <>
          {filtered.length > 0 ? (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {filtered.map((entry) => (
                <CapabilityCard key={entry.id} entry={entry} daoId={id} />
              ))}
            </div>
          ) : (
            <div className="text-muted-foreground py-12 text-center text-sm">
              {typeFilter
                ? `No capabilities matching "${typeFilter}".`
                : "No capabilities stored in this vault."}
            </div>
          )}
        </>
      )}
    </div>
  );
}
