/**
 * useLiveGovernance — merges useGovernanceDetail (RPC snapshot) with the relay board overlay.
 *
 * When a BoardUpdated event arrives, boardOverride is set immediately with the new member
 * list. The relay also invalidates the board cache, so a refetch is queued. Until it lands,
 * boardOverride is used as the authoritative membership list.
 *
 * Once the refetch completes the fetched data will match boardOverride, so applying the
 * override is idempotent thereafter.
 */

import { useMemo } from 'react'
import { useGovernanceDetail } from './useDao'
import { useDaoRelayProposals } from '@/context/DaoRelayContext'

export function useLiveGovernance(daoId: string) {
  const query = useGovernanceDetail(daoId)
  const { boardOverride } = useDaoRelayProposals()

  const data = useMemo(() => {
    const gov = query.data
    if (!gov || !boardOverride) return gov
    // Only applies to Board governance — Direct/Weighted carry weights that
    // the relay event doesn't supply, so leave those unchanged.
    if (gov.type !== 'Board') return gov

    return {
      ...gov,
      members: boardOverride.map((address) => ({ address })),
    }
  }, [query.data, boardOverride])

  return { ...query, data }
}
