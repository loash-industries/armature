/**
 * useFrameworkRelay — Live state machine for armature_framework on-chain events.
 *
 * Subscribes to three armature_framework modules via relay-sdk:
 *   • proposal       — ProposalCreated, VoteCast, ProposalPassed, ProposalExecuted, ProposalExpired
 *   • treasury_vault — CoinDeposited, CoinWithdrawn, CoinClaimed
 *   • emergency      — TypeFrozen, TypeUnfrozen, FreezeExemptTypeAdded, FreezeExemptTypeRemoved
 *
 * State is updated via a reducer as events arrive. Components can use the returned
 * state as a live overlay on top of their React Query (RPC-fetched) snapshots.
 *
 * Side effects: React Query cache entries are invalidated when authoritative
 * on-chain state has definitively changed (proposal executed, board updated, etc.)
 * so that background refetches stay in sync.
 */

import { useEffect, useLayoutEffect, useReducer, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { RelayClient } from '@loash-industries/relay-sdk'
import type { Subscription } from '@loash-industries/relay-sdk'
import { PACKAGE_ID, MODULES } from '@/config/constants'
import { cacheKeys } from '@/lib/cache-keys'
import { RELAY_NETWORK, RELAY_TOKEN } from '@/lib/relay'
import { decodeMoveString } from '@/lib/utils'
import type {
  ProposalCreatedFields,
  VoteCastFields,
  ProposalPassedFields,
  ProposalExecutedFields,
  ProposalExpiredFields,
  CoinDepositedFields,
  CoinWithdrawnFields,
  CoinClaimedFields,
  TypeFrozenFields,
  TypeUnfrozenFields,
  FreezeExemptTypeAddedFields,
  FreezeExemptTypeRemovedFields,
} from '@/types/relay-events'

// ─── Domain types ────────────────────────────────────────────────────────────

export interface TreasuryRelayEvent {
  kind: 'deposited' | 'withdrawn' | 'claimed'
  vaultId: string
  coinType: string
  amount: bigint
  actor: string
  /** relay-sdk gateway timestamp (epoch ms) */
  timestamp: number
}

// ─── State ───────────────────────────────────────────────────────────────────

export interface FrameworkRelayState {
  /**
   * Proposal IDs that arrived via relay since the last full fetch.
   * Use alongside `useProposals()` to surface new proposals without waiting
   * for a stale-time-triggered refetch.
   */
  incomingProposalIds: string[]

  /**
   * Authoritative status overrides keyed by proposalId.
   * Set by ProposalPassed / ProposalExecuted / ProposalExpired events.
   * Takes precedence over the last-fetched status in `useProposals()`.
   */
  proposalStatusOverrides: Record<string, 'passed' | 'executed' | 'expired'>

  /**
   * Live accumulated vote counts since the last RPC snapshot, keyed by proposalId.
   * Add these to the snapshot values to get the current tally.
   */
  liveVoteCounts: Record<string, { yes: bigint; no: bigint }>

  /**
   * Recent treasury events (newest first, capped at MAX_TREASURY_FEED).
   * Used to drive live activity feeds without waiting for a full treasury re-fetch.
   */
  treasuryFeed: TreasuryRelayEvent[]

  /**
   * Type keys whose freeze state changed since last RPC snapshot.
   * Value: expiry epoch-ms (0 means the type was unfrozen by the relay event).
   */
  freezeOverrides: Record<string, number>
}

// ─── Actions ─────────────────────────────────────────────────────────────────

type FrameworkAction =
  | { type: 'PROPOSAL_CREATED'; proposalId: string }
  | { type: 'VOTE_CAST'; proposalId: string; approve: boolean; weight: bigint }
  | { type: 'PROPOSAL_PASSED'; proposalId: string }
  | { type: 'PROPOSAL_EXECUTED'; proposalId: string }
  | { type: 'PROPOSAL_EXPIRED'; proposalId: string }
  | { type: 'COIN_EVENT'; event: TreasuryRelayEvent }
  | { type: 'TYPE_FROZEN'; typeKey: string; expiryMs: number }
  | { type: 'TYPE_UNFROZEN'; typeKey: string }

const MAX_TREASURY_FEED = 50

const initialState: FrameworkRelayState = {
  incomingProposalIds: [],
  proposalStatusOverrides: {},
  liveVoteCounts: {},
  treasuryFeed: [],
  freezeOverrides: {},
}

function frameworkReducer(
  state: FrameworkRelayState,
  action: FrameworkAction,
): FrameworkRelayState {
  switch (action.type) {
    case 'PROPOSAL_CREATED':
      if (state.incomingProposalIds.includes(action.proposalId)) return state
      return {
        ...state,
        incomingProposalIds: [...state.incomingProposalIds, action.proposalId],
      }

    case 'VOTE_CAST': {
      const prev = state.liveVoteCounts[action.proposalId] ?? { yes: 0n, no: 0n }
      return {
        ...state,
        liveVoteCounts: {
          ...state.liveVoteCounts,
          [action.proposalId]: {
            yes: action.approve ? prev.yes + action.weight : prev.yes,
            no: action.approve ? prev.no : prev.no + action.weight,
          },
        },
      }
    }

    case 'PROPOSAL_PASSED':
      return {
        ...state,
        proposalStatusOverrides: {
          ...state.proposalStatusOverrides,
          [action.proposalId]: 'passed',
        },
      }

    case 'PROPOSAL_EXECUTED':
      return {
        ...state,
        proposalStatusOverrides: {
          ...state.proposalStatusOverrides,
          [action.proposalId]: 'executed',
        },
      }

    case 'PROPOSAL_EXPIRED':
      // Only set if not already overridden to passed/executed
      if (
        state.proposalStatusOverrides[action.proposalId] === 'passed' ||
        state.proposalStatusOverrides[action.proposalId] === 'executed'
      ) {
        return state
      }
      return {
        ...state,
        proposalStatusOverrides: {
          ...state.proposalStatusOverrides,
          [action.proposalId]: 'expired',
        },
      }

    case 'COIN_EVENT': {
      const feed = [action.event, ...state.treasuryFeed]
      return {
        ...state,
        treasuryFeed: feed.length > MAX_TREASURY_FEED ? feed.slice(0, MAX_TREASURY_FEED) : feed,
      }
    }

    case 'TYPE_FROZEN':
      return {
        ...state,
        freezeOverrides: { ...state.freezeOverrides, [action.typeKey]: action.expiryMs },
      }

    case 'TYPE_UNFROZEN':
      return {
        ...state,
        freezeOverrides: { ...state.freezeOverrides, [action.typeKey]: 0 },
      }

    default:
      return state
  }
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Connects to the relay service and maintains a live FrameworkRelayState for
 * the given DAO. Pass `enabled: false` to suspend the WebSocket connection
 * (e.g. on localnet where relay is unavailable).
 */
export function useFrameworkRelay(
  daoId: string,
  { enabled = true }: { enabled?: boolean } = {},
): FrameworkRelayState {
  const queryClient = useQueryClient()
  const [state, dispatch] = useReducer(frameworkReducer, initialState)
  // Keep a stable ref to dispatch for use inside async callbacks
  const dispatchRef = useRef(dispatch)
  useLayoutEffect(() => { dispatchRef.current = dispatch })

  useEffect(() => {
    if (!enabled || !daoId || !RELAY_TOKEN) {
      console.log('[useFrameworkRelay] skipped — enabled=%s, daoId=%s, hasToken=%s', enabled, daoId, !!RELAY_TOKEN)
      return
    }

    console.log('[useFrameworkRelay] connecting for daoId=%s', daoId)
    const client = new RelayClient(RELAY_NETWORK, { token: RELAY_TOKEN })
    let cancelled = false
    const subscriptions: Subscription[] = []

    async function start() {
      await client.connect()
      console.log('[useFrameworkRelay] connected, cancelled=%s', cancelled)
      if (cancelled) return

      // ── Proposal: ProposalCreated ──────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalCreatedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.proposal,
          eventName: 'ProposalCreated',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalCreatedFields | null
            if (!f) return
            dispatchRef.current({ type: 'PROPOSAL_CREATED', proposalId: f.proposal_id })
            queryClient.invalidateQueries({ queryKey: cacheKeys.proposals(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Proposal: VoteCast ────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<VoteCastFields>({
          packageId: PACKAGE_ID,
          module: MODULES.proposal,
          eventName: 'VoteCast',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as VoteCastFields | null
            if (!f) return
            dispatchRef.current({
              type: 'VOTE_CAST',
              proposalId: f.proposal_id,
              approve: f.approve,
              weight: BigInt(f.weight),
            })
            queryClient.invalidateQueries({ queryKey: cacheKeys.proposal(f.proposal_id) })
          },
        }),
      )

      if (cancelled) return

      // ── Proposal: ProposalPassed ───────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalPassedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.proposal,
          eventName: 'ProposalPassed',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalPassedFields | null
            if (!f) return
            dispatchRef.current({ type: 'PROPOSAL_PASSED', proposalId: f.proposal_id })
            queryClient.invalidateQueries({ queryKey: cacheKeys.proposal(f.proposal_id) })
          },
        }),
      )

      if (cancelled) return

      // ── Proposal: ProposalExecuted ────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalExecutedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.proposal,
          eventName: 'ProposalExecuted',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalExecutedFields | null
            if (!f) return
            dispatchRef.current({ type: 'PROPOSAL_EXECUTED', proposalId: f.proposal_id })
            queryClient.invalidateQueries({ queryKey: cacheKeys.proposal(f.proposal_id) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.proposals(daoId) })
            // Execution mutates DAO state — invalidate the full snapshot
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Proposal: ProposalExpired ─────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalExpiredFields>({
          packageId: PACKAGE_ID,
          module: MODULES.proposal,
          eventName: 'ProposalExpired',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalExpiredFields | null
            if (!f) return
            dispatchRef.current({ type: 'PROPOSAL_EXPIRED', proposalId: f.proposal_id })
            queryClient.invalidateQueries({ queryKey: cacheKeys.proposal(f.proposal_id) })
          },
        }),
      )

      if (cancelled) return

      // ── Treasury: CoinDeposited ────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<CoinDepositedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.treasury_vault,
          eventName: 'CoinDeposited',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinDepositedFields | null
            if (!f) return
            const coinType = decodeMoveString(f.coin_type)
            console.log('[useFrameworkRelay] CoinDeposited — raw coin_type=%o, decoded=%s, vault=%s, amount=%s, depositor=%s', f.coin_type, coinType, f.vault_id, f.amount, f.depositor)
            dispatchRef.current({
              type: 'COIN_EVENT',
              event: {
                kind: 'deposited',
                vaultId: f.vault_id,
                coinType,
                amount: BigInt(f.amount),
                actor: f.depositor,
                timestamp: ev.timestamp,
              },
            })
            console.log('[useFrameworkRelay] invalidating treasury(%s) and events(treasury, %s)', f.vault_id, daoId)
            queryClient.invalidateQueries({ queryKey: cacheKeys.treasury(f.vault_id) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.events('treasury', daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Treasury: CoinWithdrawn ────────────────────────────────────────────
      // Every withdrawal goes through a proposal, so the higher-level
      // CoinSent / CoinSentToDAO / SmallPaymentSent event (treasury_ops)
      // always accompanies CoinWithdrawn. We subscribe here only for cache
      // invalidation — the feed entry comes from useProposalRelay's
      // paymentFeed and the RPC history, avoiding duplicate rows.
      subscriptions.push(
        await client.subscribe<CoinWithdrawnFields>({
          packageId: PACKAGE_ID,
          module: MODULES.treasury_vault,
          eventName: 'CoinWithdrawn',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinWithdrawnFields | null
            if (!f) return
            // No COIN_EVENT dispatch — higher-level ops event covers the feed.
            queryClient.invalidateQueries({ queryKey: cacheKeys.treasury(f.vault_id) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.events('treasury', daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Treasury: CoinClaimed ──────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<CoinClaimedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.treasury_vault,
          eventName: 'CoinClaimed',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinClaimedFields | null
            if (!f) return
            dispatchRef.current({
              type: 'COIN_EVENT',
              event: {
                kind: 'claimed',
                vaultId: f.vault_id,
                coinType: decodeMoveString(f.coin_type),
                amount: BigInt(f.amount),
                actor: f.claimer,
                timestamp: ev.timestamp,
              },
            })
            queryClient.invalidateQueries({ queryKey: cacheKeys.treasury(f.vault_id) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.events('treasury', daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Emergency: TypeFrozen ──────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<TypeFrozenFields>({
          packageId: PACKAGE_ID,
          module: MODULES.emergency,
          eventName: 'TypeFrozen',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as TypeFrozenFields | null
            if (!f) return
            dispatchRef.current({
              type: 'TYPE_FROZEN',
              typeKey: f.type_key,
              expiryMs: Number(f.expiry_ms),
            })
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Emergency: TypeUnfrozen ────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<TypeUnfrozenFields>({
          packageId: PACKAGE_ID,
          module: MODULES.emergency,
          eventName: 'TypeUnfrozen',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as TypeUnfrozenFields | null
            if (!f) return
            dispatchRef.current({ type: 'TYPE_UNFROZEN', typeKey: f.type_key })
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── Emergency: FreezeExemptTypeAdded / Removed ─────────────────────────
      // These don't change displayed freeze state — just invalidate governance config.
      const onFreezeExemptChange = () => {
        queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
      }

      subscriptions.push(
        await client.subscribe<FreezeExemptTypeAddedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.emergency,
          eventName: 'FreezeExemptTypeAdded',
          match: { dao_id: daoId },
          onEvent: onFreezeExemptChange,
        }),
      )

      if (cancelled) return

      subscriptions.push(
        await client.subscribe<FreezeExemptTypeRemovedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.emergency,
          eventName: 'FreezeExemptTypeRemoved',
          match: { dao_id: daoId },
          onEvent: onFreezeExemptChange,
        }),
      )
    }

    start().catch(() => {
      // Connection errors are handled internally by RelayClient (auto-reconnect).
    })

    return () => {
      cancelled = true
      client.disconnect()
    }
  }, [daoId, enabled, queryClient])

  return state
}
