import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import type { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";
import { getOwnedObjects, multiGetObjects, unwrapMoveStruct } from "@/lib/sui-rpc";
import { WORLD_PACKAGE_ID } from "@/config/constants";
import { cacheKeys } from "@/lib/cache-keys";

const PLAYER_PROFILE_TYPE = `${WORLD_PACKAGE_ID}::character::PlayerProfile`;
const MAX_CONCURRENCY = 5;

interface PlayerProfileFields {
  character_id: string;
}

interface MetadataFields {
  name: string;
}

interface CharacterFields {
  metadata: MetadataFields | null;
}

/**
 * Batch-resolve Sui addresses to EVE Frontier character names.
 *
 * Phase 1: For each address, query owned PlayerProfile objects → extract character_id.
 *          (Parallelised with a concurrency cap.)
 * Phase 2: Fetch all Character objects in one multiGetObjects call → read metadata.name.
 *
 * Returns a `Map<address, string | null>` where null = no character / no name.
 */
export function useCharacterNames(addresses: string[]) {
  const client = useSuiClient();
  const dedupedAddresses = [...new Set(addresses)].filter(Boolean);

  return useQuery({
    queryKey: cacheKeys.characterNames(dedupedAddresses),
    queryFn: () => resolveCharacterNames(client, dedupedAddresses),
    enabled: dedupedAddresses.length > 0,
    staleTime: 60_000,
  });
}

async function resolveCharacterNames(
  client: SuiJsonRpcClient,
  addresses: string[],
): Promise<Map<string, string | null>> {
  const result = new Map<string, string | null>();

  // Phase 1 — resolve address → character_id via owned PlayerProfile
  const addressToCharacterId = new Map<string, string>();

  // Process in batches to cap concurrency
  for (let i = 0; i < addresses.length; i += MAX_CONCURRENCY) {
    const batch = addresses.slice(i, i + MAX_CONCURRENCY);
    const settled = await Promise.allSettled(
      batch.map(async (addr) => {
        const profiles = await getOwnedObjects(client, addr, {
          StructType: PLAYER_PROFILE_TYPE,
        });
        if (profiles.length === 0) return { addr, characterId: null };

        const content = profiles[0].data?.content as
          | { fields: unknown; dataType: "moveObject" }
          | undefined;
        if (!content || content.dataType !== "moveObject") {
          return { addr, characterId: null };
        }
        const fields = unwrapMoveStruct(content.fields) as PlayerProfileFields;
        return { addr, characterId: fields.character_id };
      }),
    );

    for (const entry of settled) {
      if (entry.status === "fulfilled" && entry.value.characterId) {
        addressToCharacterId.set(entry.value.addr, entry.value.characterId);
      }
    }
  }

  // Phase 2 — batch-fetch Character objects → read metadata.name
  const characterIds = [...addressToCharacterId.values()];
  const charIdToName = new Map<string, string | null>();

  if (characterIds.length > 0) {
    // multiGetObjects supports up to 50 IDs per call
    for (let i = 0; i < characterIds.length; i += 50) {
      const batch = characterIds.slice(i, i + 50);
      const objects = await multiGetObjects(client, batch);

      for (const obj of objects) {
        const id = obj.data?.objectId;
        if (!id) continue;

        const content = obj.data?.content as
          | { fields: unknown; dataType: "moveObject" }
          | undefined;
        if (!content || content.dataType !== "moveObject") {
          charIdToName.set(id, null);
          continue;
        }
        const fields = unwrapMoveStruct(content.fields) as CharacterFields;
        charIdToName.set(id, fields.metadata?.name ?? null);
      }
    }
  }

  // Build final address → name map
  for (const addr of addresses) {
    const charId = addressToCharacterId.get(addr);
    result.set(addr, charId ? (charIdToName.get(charId) ?? null) : null);
  }

  return result;
}
