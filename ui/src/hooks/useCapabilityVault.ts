import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import { getObject, getDynamicFields, unwrapMoveStruct } from "@/lib/sui-rpc";
import type { CapabilityVaultFields, CapabilityEntry } from "@/types/dao";

function moveFields<T>(obj: { data?: { content?: unknown } | null }): T {
  const content = obj.data?.content as
    | { fields: unknown; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") {
    throw new Error("Object has no Move content");
  }
  return unwrapMoveStruct(content.fields) as T;
}

function shortTypeName(fullType: string): string {
  const parts = fullType.split("::");
  return parts[parts.length - 1] ?? fullType;
}

export function useCapabilityVaultEntries(vaultId: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.capVaultEntries(vaultId ?? ""),
    queryFn: async (): Promise<CapabilityEntry[]> => {
      if (!vaultId) return [];

      const vaultObj = await getObject(client, vaultId);
      const vault = moveFields<CapabilityVaultFields>(vaultObj);

      const capIds = vault.cap_ids.contents;
      if (capIds.length === 0) return [];

      // Build a reverse map: capId → typeName from ids_by_type
      const idToType = new Map<string, string>();
      for (const entry of vault.ids_by_type.contents) {
        const typeName = entry.key;
        for (const id of entry.value) {
          idToType.set(id, typeName);
        }
      }

      // Read dynamic fields to get object types and SubDAOControl details
      const fields = await getDynamicFields(client, vaultId);
      const fieldMap = new Map(
        fields.map((f) => {
          const nameValue =
            typeof f.name.value === "string"
              ? f.name.value
              : String(f.name.value);
          return [nameValue, f];
        }),
      );

      const entries: CapabilityEntry[] = [];

      for (const capId of capIds) {
        const typeName = idToType.get(capId) ?? "Unknown";
        const field = fieldMap.get(capId);
        const isSubDAOControl = typeName.includes("SubDAOControl");

        let subdaoId: string | null = null;
        if (isSubDAOControl && field) {
          try {
            const fieldObj = await client.getDynamicFieldObject({
              parentId: vaultId,
              name: field.name,
            });
            const controlFields = moveFields<{
              id: { id: string };
              subdao_id: string;
            }>(fieldObj);
            subdaoId = controlFields.subdao_id;
          } catch {
            // Can't read SubDAOControl details
          }
        }

        entries.push({
          id: capId,
          typeName,
          shortType: shortTypeName(typeName),
          objectType: field?.objectType ?? null,
          isSubDAOControl,
          subdaoId,
        });
      }

      return entries;
    },
    enabled: !!vaultId,
  });
}
