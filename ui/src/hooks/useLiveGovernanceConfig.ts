/**
 * useLiveGovernanceConfig — merges useGovernanceConfig (RPC snapshot) with the relay
 * changedTypeKeys overlay.
 *
 * When a ProposalTypeEnabled / ProposalTypeDisabled / ProposalConfigUpdated event
 * arrives, the relay marks those type keys as changed and queues an invalidation.
 * The `stale` flag on each entry signals that a refetch is in flight, so callers can
 * show a spinner or muted value on the affected rows while waiting for fresh data.
 */

import { useMemo } from 'react'
import { useGovernanceConfig } from './useDao'
import { useDaoRelayProposals } from '@/context/DaoRelayContext'
import type { ProposalTypeConfig } from '@/types/dao'

export type LiveProposalTypeConfig = ProposalTypeConfig & {
  /** True while the relay has received a config-change event and the RPC refetch
   *  is still in flight. Resets to false once the new snapshot arrives. */
  stale: boolean
}

export function useLiveGovernanceConfig(daoId: string) {
  const query = useGovernanceConfig(daoId)
  const { changedTypeKeys } = useDaoRelayProposals()

  const data: LiveProposalTypeConfig[] | undefined = useMemo(() => {
    if (!query.data) return query.data
    if (changedTypeKeys.size === 0) {
      return query.data.map((item) => ({ ...item, stale: false }))
    }
    return query.data.map((item) => ({
      ...item,
      stale: changedTypeKeys.has(item.typeKey),
    }))
  }, [query.data, changedTypeKeys])

  return { ...query, data }
}
