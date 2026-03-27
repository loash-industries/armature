import { useQueryClient } from "@tanstack/react-query";
import { getAddressNameRaw } from "@/lib/address-namer";

/**
 * Reads every cached `characterNames` React Query result and flattens it into
 * a single `Map<address, displayName>` covering ALL seen addresses.
 *
 * - Addresses with a resolved EVE character name use that name.
 * - Addresses without one fall back to their deterministically generated name.
 *
 * This powers the RecipientCombobox autocomplete, which should be searchable
 * by whatever name the user sees in the UI.
 */
export function useCharacterNameCache(): Map<string, string> {
  const qc = useQueryClient();

  const result = new Map<string, string>();
  const allData = qc.getQueriesData<Map<string, string | null>>({
    queryKey: ["characterNames"],
  });

  for (const [, data] of allData) {
    if (!data) continue;
    for (const [addr, charName] of data) {
      result.set(addr, charName ?? getAddressNameRaw(addr));
    }
  }

  return result;
}
