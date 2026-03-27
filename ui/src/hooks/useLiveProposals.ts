/**
 * useLiveProposals — merges useProposals (RPC snapshot) with the relay proposal overlay.
 *
 * Two relay contributions:
 *
 * 1. proposalStatusOverrides — definitive status transitions (passed / executed / expired)
 *    delivered by relay events before the RPC refetch completes. Applied directly over
 *    the fetched status so the UI reflects reality immediately.
 *
 * 2. pendingIds — IDs from ProposalCreated events not yet present in the RPC snapshot
 *    (refetch is already queued). Callers can render skeleton rows until real data arrives.
 */

import { useMemo } from 'react'
import { useProposals } from './useProposals'
import { useDaoRelayFramework } from '@/context/DaoRelayContext'
import type { ProposalSummary } from '@/types/proposal'

export function useLiveProposals(daoId: string) {
  const query = useProposals(daoId)
  const { proposalStatusOverrides, incomingProposalIds } = useDaoRelayFramework()

  const data: ProposalSummary[] | undefined = useMemo(() => {
    if (!query.data) return query.data

    return query.data.map((p) => {
      const override = proposalStatusOverrides[p.id]
      return override ? { ...p, status: override } : p
    })
  }, [query.data, proposalStatusOverrides])

  // Proposal IDs delivered by relay that haven't appeared in the RPC snapshot yet.
  const pendingIds: string[] = useMemo(() => {
    if (!query.data) return []
    const existing = new Set(query.data.map((p) => p.id))
    return incomingProposalIds.filter((id) => !existing.has(id))
  }, [query.data, incomingProposalIds])

  return { ...query, data, pendingIds }
}
