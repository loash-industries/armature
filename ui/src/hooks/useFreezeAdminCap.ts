import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { useWalletSigner } from "@/hooks/useWalletSigner";
import { getOwnedObjects } from "@/lib/sui-rpc";
import { PACKAGE_ID } from "@/config/constants";
import { cacheKeys } from "@/lib/cache-keys";

/** Check if the connected wallet owns a FreezeAdminCap for the given DAO. */
export function useFreezeAdminCap(daoId: string) {
  const client = useSuiClient();
  const { address } = useWalletSigner();

  return useQuery({
    queryKey: [...cacheKeys.dao(daoId), "freezeAdminCap", address],
    queryFn: async (): Promise<string | null> => {
      if (!address) return null;

      const objects = await getOwnedObjects(client, address, {
        StructType: `${PACKAGE_ID}::emergency::FreezeAdminCap`,
      });

      for (const obj of objects) {
        const content = obj.data?.content as
          | { fields: { dao_id: string }; dataType: "moveObject" }
          | undefined;
        if (content?.dataType === "moveObject") {
          if (content.fields.dao_id === daoId) {
            return obj.data!.objectId!;
          }
        }
      }

      return null;
    },
    enabled: !!daoId && !!address,
  });
}
