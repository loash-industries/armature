import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { useWalletSigner } from "@/hooks/useWalletSigner";

export interface WalletCoin {
  coinObjectId: string;
  coinType: string;
  balance: bigint;
}

/** Fetch all coin objects owned by the connected wallet. */
export function useWalletCoins() {
  const client = useSuiClient();
  const { address } = useWalletSigner();

  return useQuery({
    queryKey: ["walletCoins", address],
    queryFn: async (): Promise<WalletCoin[]> => {
      if (!address) return [];

      const coins: WalletCoin[] = [];
      let cursor: string | null = null;
      let hasNext = true;

      while (hasNext) {
        const page = await client.getAllCoins({
          owner: address,
          cursor: cursor ?? undefined,
          limit: 50,
        });
        for (const c of page.data) {
          coins.push({
            coinObjectId: c.coinObjectId,
            coinType: c.coinType,
            balance: BigInt(c.balance),
          });
        }
        cursor = page.nextCursor ?? null;
        hasNext = page.hasNextPage;
      }

      return coins;
    },
    enabled: !!address,
  });
}
