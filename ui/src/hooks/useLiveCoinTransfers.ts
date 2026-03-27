/**
 * useLiveCoinTransfers — live feed of Coin treasury mutations for a given
 * treasury vault address.
 *
 * Two subscriptions are opened per hook instance, matching the on-chain fund
 * flows in `armature::treasury_vault`:
 *
 *   Inbound:
 *   1. `subscribe CoinDeposited` — coins deposited via the permissionless
 *      `deposit()` entry (merged into Balance, no object transfer).
 *      (The complementary `CoinClaimed` path — objects transferred to the
 *      vault then claimed — is handled by useFrameworkRelay.)
 *
 *   Outbound:
 *   2. `subscribe CoinWithdrawn` — coins withdrawn via an approved proposal
 *      execution (`withdraw()` creates a fresh Coin from Balance, so no
 *      `_from` object-transfer fires).
 *
 * The coin type (e.g. "0x2::sui::SUI") is extracted from the `coin_type`
 * field of the emitted event.
 */

import { useEffect, useLayoutEffect, useReducer, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { RelayClient } from '@loash-industries/relay-sdk'
import type { Subscription } from '@loash-industries/relay-sdk'
import { RELAY_NETWORK, RELAY_TOKEN } from '@/lib/relay'
import { PACKAGE_ID, MODULES } from '@/config/constants'
import { cacheKeys } from '@/lib/cache-keys'
import type { CoinDepositedFields, CoinWithdrawnFields } from '@/types/relay-events'

// ─── Domain types ─────────────────────────────────────────────────────────────

export interface CoinTransferEvent {
  /** Sui object ID of the Coin object that moved. */
  objectId: string
  /** Full Move type parameter, e.g. "0x2::sui::SUI". */
  coinType: string
  /** Raw balance string of the Coin object at transfer time (u64 as string). */
  amount: string
  direction: 'inbound' | 'outbound'
  /** Sending address (the tx sender, not necessarily the previous owner). */
  sender: string
  /** Previous owner address, or null for object creation / wrapped objects. */
  fromOwner: string | null
  /** New owner address. */
  toOwner: string
  /** Transaction digest that carried this transfer. */
  txDigest: string
  /** relay-sdk gateway timestamp (epoch ms). */
  timestamp: number
}

// ─── State ────────────────────────────────────────────────────────────────────

export interface CoinTransferState {
  /**
   * Recent Coin transfers (newest first, capped at MAX_FEED).
   * Includes both inbound and outbound transfers.
   */
  feed: CoinTransferEvent[]
  /** Total inbound amount accumulated since mount, in raw u64 string units.
   *  Summed per coin type — use `inboundByType` for per-type granularity. */
  inboundByType: Record<string, bigint>
  /** Total outbound amount accumulated since mount, per coin type. */
  outboundByType: Record<string, bigint>
}

// ─── Actions ──────────────────────────────────────────────────────────────────

type TransferAction = { type: 'TRANSFER'; event: CoinTransferEvent }

const MAX_FEED = 50

const initialState: CoinTransferState = {
  feed: [],
  inboundByType: {},
  outboundByType: {},
}

function transferReducer(state: CoinTransferState, action: TransferAction): CoinTransferState {
  const { event } = action
  const feed = [event, ...state.feed]
  const amount = BigInt(event.amount)

  if (event.direction === 'inbound') {
    const prev = state.inboundByType[event.coinType] ?? 0n
    return {
      feed: feed.length > MAX_FEED ? feed.slice(0, MAX_FEED) : feed,
      inboundByType: { ...state.inboundByType, [event.coinType]: prev + amount },
      outboundByType: state.outboundByType,
    }
  } else {
    const prev = state.outboundByType[event.coinType] ?? 0n
    return {
      feed: feed.length > MAX_FEED ? feed.slice(0, MAX_FEED) : feed,
      inboundByType: state.inboundByType,
      outboundByType: { ...state.outboundByType, [event.coinType]: prev + amount },
    }
  }
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Opens two relay subscriptions for treasury coin mutations:
 *   1. `subscribe CoinDeposited`    — direct deposits via deposit()
 *   2. `subscribe CoinWithdrawn`    — outbound withdrawals via approved proposals
 *
 * The complementary `CoinClaimed` inbound path (objects transferred to the
 * vault address then claimed via `claim_coin`) is handled by
 * `useFrameworkRelay`, which already subscribes to the treasury_vault module.
 *
 * Pass `enabled: false` to suspend (e.g. on localnet where the relay is
 * unavailable).
 *
 * The hook also invalidates `cacheKeys.treasury(treasuryId)` on every mutation
 * so that balance queries stay fresh.
 */
export function useLiveCoinTransfers(
  treasuryId: string | undefined,
  { enabled = true }: { enabled?: boolean } = {},
): CoinTransferState {
  const queryClient = useQueryClient()
  const [state, dispatch] = useReducer(transferReducer, initialState)
  const dispatchRef = useRef(dispatch)
  useLayoutEffect(() => { dispatchRef.current = dispatch })

  useEffect(() => {
    if (!enabled || !treasuryId || !RELAY_TOKEN) return

    const vaultId = treasuryId
    const client = new RelayClient(RELAY_NETWORK, { token: RELAY_TOKEN })
    let cancelled = false
    const subscriptions: Subscription[] = []

    async function start() {
      await client.connect()
      if (cancelled) return

      // ── 1. Inbound: Direct deposits via deposit() ─────────────────────────
      subscriptions.push(
        await client.subscribe<CoinDepositedFields>({
          packageId: PACKAGE_ID,
          module: MODULES.treasury_vault,
          eventName: 'CoinDeposited',
          match: { vault_id: vaultId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinDepositedFields | null
            if (!f) return
            dispatchRef.current({
              type: 'TRANSFER',
              event: {
                objectId: f.vault_id,
                coinType: f.coin_type,
                amount: f.amount,
                direction: 'inbound',
                sender: f.depositor,
                fromOwner: f.depositor,
                toOwner: vaultId,
                txDigest: '',
                timestamp: ev.timestamp,
              },
            })
            queryClient.invalidateQueries({ queryKey: cacheKeys.treasury(vaultId) })
          },
        }),
      )

      if (cancelled) return

      // ── 2. Outbound: Withdrawals via approved proposal execution ──────────
      subscriptions.push(
        await client.subscribe<CoinWithdrawnFields>({
          packageId: PACKAGE_ID,
          module: MODULES.treasury_vault,
          eventName: 'CoinWithdrawn',
          match: { vault_id: vaultId },
          onEvent: (ev) => {
            const f = ev.decoded_fields as unknown as CoinWithdrawnFields | null
            if (!f) return
            dispatchRef.current({
              type: 'TRANSFER',
              event: {
                objectId: f.vault_id,
                coinType: f.coin_type,
                amount: f.amount,
                direction: 'outbound',
                sender: vaultId,
                fromOwner: vaultId,
                toOwner: f.recipient,
                txDigest: '',
                timestamp: ev.timestamp,
              },
            })
            queryClient.invalidateQueries({ queryKey: cacheKeys.treasury(vaultId) })
          },
        }),
      )
    }

    start().catch(console.error)

    return () => {
      cancelled = true
      for (const sub of subscriptions) sub.unsubscribe()
      client.disconnect()
    }
  }, [treasuryId, enabled, queryClient])

  return state
}
