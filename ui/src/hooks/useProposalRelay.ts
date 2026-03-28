/**
 * useProposalRelay — Live state machine for armature_proposals on-chain events.
 *
 * Subscribes to execution-outcome events emitted by the armature_proposals package:
 *   • board_ops      — BoardUpdated
 *   • admin_ops      — ProposalTypeEnabled, ProposalTypeDisabled, ProposalConfigUpdated, MetadataUpdated
 *   • treasury_ops   — CoinSent, CoinSentToDAO, SmallPaymentSent
 *   • security_ops   — FreezeAdminTransferred, FreezeConfigUpdated
 *   • subdao_ops     — SubDAOCreated, SubDAOExecutionPaused/Unpaused, SuccessorDAOSpawned,
 *                      SubDAOSpunOut, CapTransferredToSubDAO, CapReclaimedFromSubDAO,
 *                      AssetsTransferInitiated
 *   • upgrade_ops    — UpgradeAuthorized
 *
 * Maintains a typed ProposalRelayState reducer. On execution events the hook
 * also fires React Query invalidations so downstream hooks (useGovernanceDetail,
 * useDaoSummary, etc.) refetch the authoritative on-chain snapshot.
 */

import { useEffect, useLayoutEffect, useReducer, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { RelayClient } from '@loash-industries/relay-sdk'
import type { Subscription } from '@loash-industries/relay-sdk'
import { PROPOSALS_PACKAGE_ID, PROPOSAL_MODULES } from '@/config/constants'
import { cacheKeys } from '@/lib/cache-keys'
import { RELAY_NETWORK, RELAY_TOKEN } from '@/lib/relay'
import type {
  BoardUpdatedFields,
  ProposalTypeEnabledFields,
  ProposalTypeDisabledFields,
  ProposalConfigUpdatedFields,
  MetadataUpdatedFields,
  CoinSentFields,
  CoinSentToDAOFields,
  SmallPaymentSentFields,
  FreezeAdminTransferredFields,
  FreezeConfigUpdatedFields,
  SubDAOCreatedFields,
  SubDAOExecutionPausedFields,
  SubDAOExecutionUnpausedFields,
  SuccessorDAOSpawnedFields,
  SubDAOSpunOutFields,
  CapTransferredToSubDAOFields,
  CapReclaimedFromSubDAOFields,
  AssetsTransferInitiatedFields,
  UpgradeAuthorizedFields,
} from '@/types/relay-events'

// ─── Domain types ────────────────────────────────────────────────────────────

export interface PaymentRelayEvent {
  kind: 'sent' | 'sent_to_dao' | 'small_payment'
  coinType: string
  amount: bigint
  recipient: string
  /** relay-sdk gateway timestamp (epoch ms) */
  timestamp: number
}

export interface SubDAORelayEvent {
  kind:
    | 'created'
    | 'execution_paused'
    | 'execution_unpaused'
    | 'successor_spawned'
    | 'spun_out'
    | 'cap_transferred'
    | 'cap_reclaimed'
    | 'assets_transfer_initiated'
  subdaoId?: string
  timestamp: number
}

export interface ExecutionRecord {
  /** The proposal type key (e.g. "SetBoard", "TreasuryWithdraw"). */
  typeKey: string
  /** relay-sdk gateway timestamp (epoch ms) */
  timestamp: number
}

// ─── State ───────────────────────────────────────────────────────────────────

export interface ProposalRelayState {
  /**
   * Latest board membership from a BoardUpdated event.
   * Null until the first BoardUpdated arrives.
   * Takes precedence over the RPC-fetched board when non-null.
   */
  boardOverride: string[] | null

  /**
   * Proposal type keys whose enabled/config state changed since last fetch.
   * Components can check this to show a "config updated" badge before the
   * React Query refetch completes.
   */
  changedTypeKeys: Set<string>

  /**
   * Recent payment events from executed treasury proposals (newest first, max 50).
   */
  paymentFeed: PaymentRelayEvent[]

  /**
   * Recent SubDAO lifecycle events (newest first, max 20).
   */
  subDAOFeed: SubDAORelayEvent[]

  /**
   * Chronological log of proposal execution outcomes (newest first, max 100).
   * Used to drive activity feeds or "recent actions" panels.
   */
  executionLog: ExecutionRecord[]
}

// ─── Actions ─────────────────────────────────────────────────────────────────

type ProposalAction =
  | { type: 'BOARD_UPDATED'; members: string[] }
  | { type: 'TYPE_ENABLED'; typeKey: string }
  | { type: 'TYPE_DISABLED'; typeKey: string }
  | { type: 'TYPE_CONFIG_UPDATED'; typeKey: string }
  | { type: 'METADATA_UPDATED' }
  | { type: 'PAYMENT'; event: PaymentRelayEvent }
  | { type: 'SUBDAO_EVENT'; event: SubDAORelayEvent }
  | { type: 'EXECUTION_LOGGED'; typeKey: string; timestamp: number }

const MAX_PAYMENT_FEED = 50
const MAX_SUBDAO_FEED = 20
const MAX_EXECUTION_LOG = 100

const initialState: ProposalRelayState = {
  boardOverride: null,
  changedTypeKeys: new Set(),
  paymentFeed: [],
  subDAOFeed: [],
  executionLog: [],
}

function proposalReducer(
  state: ProposalRelayState,
  action: ProposalAction,
): ProposalRelayState {
  switch (action.type) {
    case 'BOARD_UPDATED':
      return { ...state, boardOverride: action.members }

    case 'TYPE_ENABLED':
    case 'TYPE_DISABLED':
    case 'TYPE_CONFIG_UPDATED': {
      const next = new Set(state.changedTypeKeys)
      next.add(action.typeKey)
      return { ...state, changedTypeKeys: next }
    }

    case 'METADATA_UPDATED':
      return state

    case 'PAYMENT': {
      const feed = [action.event, ...state.paymentFeed]
      return {
        ...state,
        paymentFeed: feed.length > MAX_PAYMENT_FEED ? feed.slice(0, MAX_PAYMENT_FEED) : feed,
      }
    }

    case 'SUBDAO_EVENT': {
      const feed = [action.event, ...state.subDAOFeed]
      return {
        ...state,
        subDAOFeed: feed.length > MAX_SUBDAO_FEED ? feed.slice(0, MAX_SUBDAO_FEED) : feed,
      }
    }

    case 'EXECUTION_LOGGED': {
      const log = [
        { typeKey: action.typeKey, timestamp: action.timestamp },
        ...state.executionLog,
      ]
      return {
        ...state,
        executionLog:
          log.length > MAX_EXECUTION_LOG ? log.slice(0, MAX_EXECUTION_LOG) : log,
      }
    }

    default:
      return state
  }
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Connects to the relay service and maintains a live ProposalRelayState for the
 * given DAO. Pass `enabled: false` to suspend (e.g. on localnet).
 */
export function useProposalRelay(
  daoId: string,
  { enabled = true }: { enabled?: boolean } = {},
): ProposalRelayState {
  const queryClient = useQueryClient()
  const [state, dispatch] = useReducer(proposalReducer, initialState)
  const dispatchRef = useRef(dispatch)
  useLayoutEffect(() => { dispatchRef.current = dispatch })

  useEffect(() => {
    if (!enabled || !daoId || !RELAY_TOKEN) return

    const client = new RelayClient(RELAY_NETWORK, { token: RELAY_TOKEN })
    let cancelled = false
    const subscriptions: Subscription[] = []

    /** Helper: log execution + dispatch. */
    const logExecution = (typeKey: string, timestamp: number) => {
      dispatchRef.current({ type: 'EXECUTION_LOGGED', typeKey, timestamp })
    }

    async function start() {
      await client.connect()
      if (cancelled) return

      // ── BoardUpdated ──────────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<BoardUpdatedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.board_ops,
          eventName: 'BoardUpdated',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as BoardUpdatedFields | null
            if (!f) return
            dispatchRef.current({ type: 'BOARD_UPDATED', members: f.new_members })
            logExecution('SetBoard', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.board(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── ProposalTypeEnabled ───────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalTypeEnabledFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.admin_ops,
          eventName: 'ProposalTypeEnabled',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalTypeEnabledFields | null
            if (!f) return
            dispatchRef.current({ type: 'TYPE_ENABLED', typeKey: f.type_key })
            logExecution('EnableProposalType', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── ProposalTypeDisabled ──────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalTypeDisabledFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.admin_ops,
          eventName: 'ProposalTypeDisabled',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalTypeDisabledFields | null
            if (!f) return
            dispatchRef.current({ type: 'TYPE_DISABLED', typeKey: f.type_key })
            logExecution('DisableProposalType', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── ProposalConfigUpdated ─────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<ProposalConfigUpdatedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.admin_ops,
          eventName: 'ProposalConfigUpdated',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as ProposalConfigUpdatedFields | null
            if (!f) return
            dispatchRef.current({ type: 'TYPE_CONFIG_UPDATED', typeKey: f.target_type_key })
            logExecution('UpdateProposalConfig', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── MetadataUpdated ───────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<MetadataUpdatedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.admin_ops,
          eventName: 'MetadataUpdated',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            dispatchRef.current({ type: 'METADATA_UPDATED' })
            logExecution('UpdateMetadata', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.charter(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── CoinSent ──────────────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<CoinSentFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.treasury_ops,
          eventName: 'CoinSent',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinSentFields | null
            if (!f) return
            dispatchRef.current({
              type: 'PAYMENT',
              event: {
                kind: 'sent',
                coinType: f.coin_type,
                amount: BigInt(f.amount),
                recipient: f.recipient,
                timestamp: ev.timestamp,
              },
            })
            logExecution('TreasuryWithdraw', ev.timestamp)
            // Treasury balance changed — invalidate via dao to get treasuryId
            queryClient.invalidateQueries({ queryKey: ['treasury', daoId] })
            queryClient.invalidateQueries({ queryKey: cacheKeys.events('treasury', daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── CoinSentToDAO ─────────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<CoinSentToDAOFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.treasury_ops,
          eventName: 'CoinSentToDAO',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinSentToDAOFields | null
            if (!f) return
            dispatchRef.current({
              type: 'PAYMENT',
              event: {
                kind: 'sent_to_dao',
                coinType: f.coin_type,
                amount: BigInt(f.amount),
                recipient: f.target_treasury,
                timestamp: ev.timestamp,
              },
            })
            logExecution('SendCoinToDAO', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: ['treasury', daoId] })
            queryClient.invalidateQueries({ queryKey: cacheKeys.events('treasury', daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── SmallPaymentSent ──────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<SmallPaymentSentFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.treasury_ops,
          eventName: 'SmallPaymentSent',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as SmallPaymentSentFields | null
            if (!f) return
            dispatchRef.current({
              type: 'PAYMENT',
              event: {
                kind: 'small_payment',
                coinType: f.coin_type,
                amount: BigInt(f.amount),
                recipient: f.recipient,
                timestamp: ev.timestamp,
              },
            })
            logExecution('SendSmallPayment', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: ['treasury', daoId] })
            queryClient.invalidateQueries({ queryKey: cacheKeys.events('treasury', daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── FreezeAdminTransferred ────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<FreezeAdminTransferredFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.security_ops,
          eventName: 'FreezeAdminTransferred',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            logExecution('TransferFreezeAdmin', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── FreezeConfigUpdated ───────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<FreezeConfigUpdatedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.security_ops,
          eventName: 'FreezeConfigUpdated',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            logExecution('UpdateFreezeConfig', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.governance(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── SubDAOCreated ─────────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<SubDAOCreatedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'SubDAOCreated',
          match: { controller_dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as SubDAOCreatedFields | null
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'created', subdaoId: f?.subdao_id, timestamp: ev.timestamp },
            })
            logExecution('CreateSubDAO', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.subdaos(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.capVault(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── SubDAOExecutionPaused ─────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<SubDAOExecutionPausedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'SubDAOExecutionPaused',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'execution_paused', timestamp: ev.timestamp },
            })
            logExecution('PauseSubDAOExecution', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.subdaos(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── SubDAOExecutionUnpaused ───────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<SubDAOExecutionUnpausedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'SubDAOExecutionUnpaused',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'execution_unpaused', timestamp: ev.timestamp },
            })
            logExecution('UnpauseSubDAOExecution', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.subdaos(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── SuccessorDAOSpawned ───────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<SuccessorDAOSpawnedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'SuccessorDAOSpawned',
          match: { origin_dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as SuccessorDAOSpawnedFields | null
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: {
                kind: 'successor_spawned',
                subdaoId: f?.successor_dao_id,
                timestamp: ev.timestamp,
              },
            })
            logExecution('SpawnDAO', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.dao(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── SubDAOSpunOut ─────────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<SubDAOSpunOutFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'SubDAOSpunOut',
          match: { controller_dao_id: daoId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as SubDAOSpunOutFields | null
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'spun_out', subdaoId: f?.subdao_id, timestamp: ev.timestamp },
            })
            logExecution('SpinOutSubDAO', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.subdaos(daoId) })
            queryClient.invalidateQueries({ queryKey: cacheKeys.capVault(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── CapTransferredToSubDAO ────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<CapTransferredToSubDAOFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'CapTransferredToSubDAO',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'cap_transferred', timestamp: ev.timestamp },
            })
            logExecution('TransferCapToSubDAO', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.capVault(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── CapReclaimedFromSubDAO ────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<CapReclaimedFromSubDAOFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'CapReclaimedFromSubDAO',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'cap_reclaimed', timestamp: ev.timestamp },
            })
            logExecution('ReclaimCapFromSubDAO', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.capVault(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── AssetsTransferInitiated ───────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<AssetsTransferInitiatedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.subdao_ops,
          eventName: 'AssetsTransferInitiated',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            dispatchRef.current({
              type: 'SUBDAO_EVENT',
              event: { kind: 'assets_transfer_initiated', timestamp: ev.timestamp },
            })
            logExecution('TransferAssets', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: ['treasury', daoId] })
            queryClient.invalidateQueries({ queryKey: cacheKeys.capVault(daoId) })
          },
        }),
      )

      if (cancelled) return

      // ── UpgradeAuthorized ─────────────────────────────────────────────────
      subscriptions.push(
        await client.subscribe<UpgradeAuthorizedFields>({
          packageId: PROPOSALS_PACKAGE_ID,
          module: PROPOSAL_MODULES.upgrade_ops,
          eventName: 'UpgradeAuthorized',
          match: { dao_id: daoId },
          onEvent: (ev) => {
            logExecution('ProposeUpgrade', ev.timestamp)
            queryClient.invalidateQueries({ queryKey: cacheKeys.capVault(daoId) })
          },
        }),
      )
    }

    start().catch(() => {
      // Connection errors handled internally by RelayClient (auto-reconnect).
    })

    return () => {
      cancelled = true
      client.disconnect()
    }
  }, [daoId, enabled, queryClient])

  return state
}
