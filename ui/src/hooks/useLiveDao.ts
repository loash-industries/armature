/**
 * useLiveDao — merges useDaoSummary (RPC snapshot) with the relay freeze overlay.
 *
 * The relay invalidates the DAO cache when TypeFrozen/TypeUnfrozen events arrive,
 * so a refetch is already in flight. The `freezeOverrides` state fills the gap
 * between the event arriving and the refetch completing.
 */

import { useMemo } from 'react'
import { useDaoSummary } from './useDao'
import { useDaoRelayFramework } from '@/context/DaoRelayContext'

export function useLiveDao(daoId: string) {
  const query = useDaoSummary(daoId)
  const { freezeOverrides } = useDaoRelayFramework()

  const data = useMemo(() => {
    const dao = query.data
    if (!dao || Object.keys(freezeOverrides).length === 0) return dao

    // Remove types that were unfrozen (expiryMs === 0) and apply newly frozen ones
    const kept = dao.frozenTypes.filter(({ typeKey }) => !(typeKey in freezeOverrides))
    const added = Object.entries(freezeOverrides)
      .filter(([, expiryMs]) => expiryMs > 0)
      .map(([typeKey, expiryMs]) => ({ typeKey, expiryMs }))

    return { ...dao, frozenTypes: [...kept, ...added] }
  }, [query.data, freezeOverrides])

  return { ...query, data }
}
