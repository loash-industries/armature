import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import type { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { getDynamicFields, multiGetObjects, unwrapMoveStruct } from "@/lib/sui-rpc";
import type { DaoEntry } from "@/hooks/useWalletDaos";
import type { DaoFields } from "@/types/dao";

function moveFields<T>(obj: { data?: { content?: unknown } | null }): T {
  const content = obj.data?.content as
    | { fields: unknown; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") {
    throw new Error("Object has no Move content");
  }
  return unwrapMoveStruct(content.fields) as T;
}

function extractMembers(dao: DaoFields): string[] {
  const gov = dao.governance;
  if (gov.variant === "Board") return gov.fields.members.contents;
  if (gov.variant === "Direct") return gov.fields.voters.contents.map((e) => e.key);
  if (gov.variant === "Weighted") return gov.fields.delegates.contents.map((e) => e.key);
  return [];
}

/**
 * Recursively collect all board member addresses reachable from a capability vault.
 * Follows SubDAOControl dynamic fields → subdao_id → DAO governance members.
 * Caps at maxDepth to avoid unbounded traversal.
 */
async function collectSubDAOMembers(
  client: SuiJsonRpcClient,
  vaultId: string,
  visited: Set<string>,
  depth: number,
  maxDepth: number,
): Promise<string[]> {
  if (depth >= maxDepth || visited.has(vaultId)) return [];
  visited.add(vaultId);

  const fields = await getDynamicFields(client, vaultId);
  const subDaoControlFields = fields.filter((f) => f.objectType.includes("SubDAOControl"));
  if (subDaoControlFields.length === 0) return [];

  const controlObjects = await multiGetObjects(
    client,
    subDaoControlFields.map((f) => f.objectId),
  );
  const childDaoIds: string[] = [];
  for (const obj of controlObjects) {
    try {
      const cf = moveFields<{ id: { id: string }; subdao_id: string }>(obj);
      childDaoIds.push(cf.subdao_id);
    } catch {
      // skip malformed entries
    }
  }

  if (childDaoIds.length === 0) return [];

  const childDaoObjects = await multiGetObjects(client, childDaoIds);
  const addresses: string[] = [];

  for (const childObj of childDaoObjects) {
    try {
      const dao = moveFields<DaoFields>(childObj);
      addresses.push(...extractMembers(dao));
      const nested = await collectSubDAOMembers(
        client,
        dao.capability_vault_id,
        visited,
        depth + 1,
        maxDepth,
      );
      addresses.push(...nested);
    } catch {
      // skip unreadable children
    }
  }

  return addresses;
}

/**
 * Pre-populates the name cache by collecting every board member address across:
 * 1. All DAOs the wallet is a direct member of (already in `daos[].memberAddresses`)
 * 2. All SubDAOs reachable via each DAO's capability vault SubDAOControl entries (depth ≤ 3)
 *
 * The resulting address list is passed to `useCharacterNames` in the caller to seed the cache.
 */
export function usePrefetchBoardMembers(daos: DaoEntry[]) {
  const client = useSuiClient();
  const stableKey = daos
    .map((d) => d.daoId)
    .sort()
    .join(",");

  return useQuery({
    queryKey: ["prefetchBoardMembers", stableKey],
    queryFn: async (): Promise<string[]> => {
      // Seed with all known member addresses already in the fetched DAOs
      const allAddresses = new Set<string>(daos.flatMap((d) => d.memberAddresses));

      // Follow SubDAO OwnerCap chain from each DAO's capability vault
      const visited = new Set<string>();
      const vaultIds = [...new Set(daos.map((d) => d.capabilityVaultId))];

      const results = await Promise.allSettled(
        vaultIds.map((vaultId) =>
          collectSubDAOMembers(client, vaultId, visited, 0, 3),
        ),
      );

      for (const r of results) {
        if (r.status === "fulfilled") {
          for (const addr of r.value) allAddresses.add(addr);
        }
      }

      return [...allAddresses];
    },
    enabled: daos.length > 0,
    staleTime: 60_000,
  });
}
