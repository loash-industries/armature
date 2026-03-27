/**
 * DaoRelayContext — mounts the two relay state machines once at the DAO layout
 * boundary and distributes their state to all descendant hooks.
 *
 * Without this context each composite hook would open its own WebSocket
 * connection. With it, a single connection is shared across the whole page.
 *
 * Mount <DaoRelayProvider daoId={daoId}> in AppShell (or any DAO-scoped layout).
 * Read state with useDaoRelayFramework() and useDaoRelayProposals().
 */

import { createContext, useContext, useMemo, type ReactNode } from 'react'
import { useFrameworkRelay, type FrameworkRelayState } from '@/hooks/useFrameworkRelay'
import { useProposalRelay, type ProposalRelayState } from '@/hooks/useProposalRelay'
import { RELAY_TOKEN } from '@/lib/relay'

interface DaoRelayContextValue {
  framework: FrameworkRelayState
  proposals: ProposalRelayState
}

const EMPTY_FRAMEWORK: FrameworkRelayState = {
  incomingProposalIds: [],
  proposalStatusOverrides: {},
  liveVoteCounts: {},
  treasuryFeed: [],
  freezeOverrides: {},
}

const EMPTY_PROPOSALS: ProposalRelayState = {
  boardOverride: null,
  changedTypeKeys: new Set(),
  paymentFeed: [],
  subDAOFeed: [],
  executionLog: [],
}

const DaoRelayContext = createContext<DaoRelayContextValue>({
  framework: EMPTY_FRAMEWORK,
  proposals: EMPTY_PROPOSALS,
})

interface DaoRelayProviderProps {
  daoId: string
  children: ReactNode
}

/** Mount once at the DAO layout boundary. */
export function DaoRelayProvider({ daoId, children }: DaoRelayProviderProps) {
  // enabled only when a real token is configured (no-op on localnet)
  const enabled = !!RELAY_TOKEN && !!daoId
  const framework = useFrameworkRelay(daoId, { enabled })
  const proposals = useProposalRelay(daoId, { enabled })

  const value = useMemo(
    () => ({ framework, proposals }),
    [framework, proposals],
  )

  return (
    <DaoRelayContext.Provider value={value}>
      {children}
    </DaoRelayContext.Provider>
  )
}

/** Returns the live armature_framework state for the current DAO. */
// eslint-disable-next-line react-refresh/only-export-components
export function useDaoRelayFramework(): FrameworkRelayState {
  return useContext(DaoRelayContext).framework
}

/** Returns the live armature_proposals execution state for the current DAO. */
// eslint-disable-next-line react-refresh/only-export-components
export function useDaoRelayProposals(): ProposalRelayState {
  return useContext(DaoRelayContext).proposals
}
