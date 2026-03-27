/**
 * useLiveProposal — merges useProposal (RPC snapshot) with the relay vote/status overlay.
 *
 * Status override: ProposalPassed / ProposalExecuted / ProposalExpired events set a
 * definitive override that takes effect immediately, before the RPC refetch lands.
 *
 * Vote delta: VoteCast events accumulate a delta on top of the last fetched vote counts.
 * The relay also invalidates the proposal cache on every VoteCast, so the delta covers
 * only the brief window while the refetch is in flight. Once the refetch completes the
 * new totals come from RPC and the delta becomes zero (relay resets liveVoteCounts on
 * cache invalidation — see useFrameworkRelay).
 *
 * NOTE: vote deltas are additive on top of the snapshot. If the snapshot was already
 * fetched after the votes arrived (common case given auto-invalidation), the delta will
 * be zero and the proposal is returned unchanged.
 */

import { useMemo } from 'react'
import { useProposal } from './useProposals'
import { useDaoRelayFramework } from '@/context/DaoRelayContext'

export function useLiveProposal(proposalId: string) {
  const query = useProposal(proposalId)
  const { proposalStatusOverrides, liveVoteCounts } = useDaoRelayFramework()

  const data = useMemo(() => {
    const p = query.data
    if (!p) return p

    const statusOverride = proposalStatusOverrides[proposalId]
    const delta = liveVoteCounts[proposalId]

    if (!statusOverride && !delta) return p

    return {
      ...p,
      ...(statusOverride ? { status: statusOverride } : {}),
      ...(delta
        ? {
            yesWeight: p.yesWeight + Number(delta.yes),
            noWeight: p.noWeight + Number(delta.no),
          }
        : {}),
    }
  }, [query.data, proposalId, proposalStatusOverrides, liveVoteCounts])

  return { ...query, data }
}
