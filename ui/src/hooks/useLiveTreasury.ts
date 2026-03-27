/**
 * useLiveTreasury — merges useTreasuryBalances (RPC snapshot) with the relay treasury feed.
 *
 * The relay invalidates the treasury cache on every CoinDeposited / CoinWithdrawn /
 * CoinClaimed event, so balances stay current via normal refetch. The additional
 * `feed` array provides a live stream of individual treasury events (newest first)
 * that can drive a real-time activity panel without requiring a separate poll.
 */

import { useMemo } from 'react'
import { useTreasuryBalances, useCoinMetadataMap } from './useDao'
import { useDaoRelayFramework } from '@/context/DaoRelayContext'
import type { TreasuryRelayEvent } from './useFrameworkRelay'

export function useLiveTreasury(treasuryId: string | undefined) {
  const query = useTreasuryBalances(treasuryId)
  const { treasuryFeed } = useDaoRelayFramework()

  const coinTypes = useMemo(
    () => query.data?.map((b) => b.coinType) ?? [],
    [query.data],
  )
  const { data: metaMap } = useCoinMetadataMap(coinTypes)

  const data = useMemo(
    () =>
      query.data?.map((b) => ({
        ...b,
        decimals: metaMap?.[b.coinType]?.decimals ?? 9,
      })),
    [query.data, metaMap],
  )

  // Filter feed to this specific vault (the context may serve multiple vaults
  // if a DAO holds coins in several treasury objects — rare but possible).
  const feed: TreasuryRelayEvent[] = useMemo(
    () =>
      treasuryId
        ? treasuryFeed.filter((e) => e.vaultId === treasuryId)
        : [],
    [treasuryFeed, treasuryId],
  )

  return useMemo(
    () => ({ ...query, data, feed }),
    // Spread query but only depend on the fields consumers actually read.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [query.isLoading, query.isError, query.dataUpdatedAt, data, feed],
  )
}
