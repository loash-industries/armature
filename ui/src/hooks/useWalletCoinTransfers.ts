/**
 * useWalletCoinTransfers — live feed of Coin object transfers involving a
 * specific wallet address, using the relay SDK's subscribeTransfer API.
 *
 * A single OR-match subscription watches for:
 *   - `_sender: address` — Coin objects sent FROM this address
 *   - `_to: address`     — Coin objects received BY this address
 *
 * The SDK deduplicates self-transfers automatically (where the address
 * satisfies both branches simultaneously).
 *
 * ─── What this captures ──────────────────────────────────────────────────────
 *
 *   ✓  execute_send_coin → transfer::public_transfer(coin, recipient)
 *        — fires _to: recipient when a DAO proposal pays out to this address
 *   ✓  Any direct transfer::public_transfer(coin, vaultAddress)
 *        — fires _to: vaultAddress (the "unclaimed" path before claim_coin)
 *   ✓  Wallet-to-wallet Coin transfers via PTBs
 *
 *   ✗  deposit() into TreasuryVault — coin.into_balance() destroys the object
 *   ✗  execute_send_coin_to_dao    — deposits into target Balance directly
 *
 * For vault-level treasury accounting (deposits, withdrawals), use
 * useLiveCoinTransfers instead. This hook is for personal wallet activity.
 *
 * ─── Cache invalidation ──────────────────────────────────────────────────────
 *
 * Invalidates the ["walletCoins", address] query on each event so that
 * useWalletCoins stays fresh after a transfer.
 */

import { useEffect, useLayoutEffect, useReducer, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { RelayClient } from '@loash-industries/relay-sdk'
import type { Subscription } from '@loash-industries/relay-sdk'
import { RELAY_NETWORK, RELAY_TOKEN } from '@/lib/relay'

// ─── Transfer batch payload from the relay indexer ───────────────────────────

interface TransferEntry {
  object_id: string
  tx_digest: string
  event_index: number
  /** Transaction sender (the address that signed the tx, not necessarily the previous owner). */
  sender?: string
  /** Previous owner address, absent on object creation. */
  from_owner?: string
  /** New owner address. */
  to_owner?: string
}

interface CoinTransferBatch {
  /** Fully-qualified Move type, e.g. "0x2::coin::Coin". */
  object_type: string
  checkpoint: number
  timestamp_ms: number
  transfers: TransferEntry[]
}

// ─── Domain types ─────────────────────────────────────────────────────────────

export interface WalletTransferEvent {
  /** Sui object ID of the Coin object that moved. */
  objectId: string
  /**
   * Move object type as reported by the indexer (e.g. "0x2::coin::Coin").
   * The concrete type parameter (e.g. "::sui::SUI") is not available in the
   * transfer envelope; query the object directly if you need it.
   */
  objectType: string
  /** Transaction sender. */
  sender: string
  /** Previous owner, or null for object creation. */
  fromOwner: string | null
  /** New owner. */
  toOwner: string
  direction: 'inbound' | 'outbound'
  txDigest: string
  timestamp: number
}

export interface WalletTransferState {
  /** Recent transfers (newest first, capped at MAX_FEED). */
  feed: WalletTransferEvent[]
}

// ─── State ────────────────────────────────────────────────────────────────────

type Action = { type: 'TRANSFERS'; events: WalletTransferEvent[] }

const MAX_FEED = 50

const initialState: WalletTransferState = { feed: [] }

function reducer(state: WalletTransferState, action: Action): WalletTransferState {
  const feed = [...action.events, ...state.feed]
  return { feed: feed.length > MAX_FEED ? feed.slice(0, MAX_FEED) : feed }
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Opens one relay subscribeTransfer subscription (OR-match) for the given
 * wallet address, watching for any Coin object sent from or received by it.
 *
 * Pass `enabled: false` to suspend (e.g. on localnet where the relay is
 * unavailable).
 *
 * @example
 * const { feed } = useWalletCoinTransfers(currentAccount?.address)
 */
export function useWalletCoinTransfers(
  walletAddress: string | undefined,
  { enabled = true }: { enabled?: boolean } = {},
): WalletTransferState {
  const queryClient = useQueryClient()
  const [state, dispatch] = useReducer(reducer, initialState)
  const dispatchRef = useRef(dispatch)
  useLayoutEffect(() => { dispatchRef.current = dispatch })

  useEffect(() => {
    if (!enabled || !walletAddress || !RELAY_TOKEN) return

    // Capture as a non-nullable string so closure types are clean.
    const addr: string = walletAddress

    const client = new RelayClient(RELAY_NETWORK, { token: RELAY_TOKEN })
    let cancelled = false
    const subscriptions: Subscription[] = []

    // 5-second dedup window: prevents double-dispatch on self-transfers where
    // the address is both sender and recipient (satisfies both subjects).
    const seen = new Set<string>()
    let seenTimer: ReturnType<typeof setTimeout> | null = null
    function deduped(txDigest: string): boolean {
      if (seen.has(txDigest)) return true
      seen.add(txDigest)
      if (!seenTimer) {
        seenTimer = setTimeout(() => { seen.clear(); seenTimer = null }, 5_000)
      }
      return false
    }

    function handleBatch(ev: { data: CoinTransferBatch }): void {
      const batch = ev.data
      if (!batch?.transfers?.length) return

      const events: WalletTransferEvent[] = batch.transfers
        .filter((t) => !deduped(t.tx_digest))
        .map((t) => ({
          objectId: t.object_id,
          objectType: batch.object_type,
          sender: t.sender ?? addr,
          fromOwner: t.from_owner ?? null,
          toOwner: t.to_owner ?? addr,
          direction: t.to_owner === addr ? 'inbound' : 'outbound',
          txDigest: t.tx_digest,
          timestamp: batch.timestamp_ms,
        }))

      if (!events.length) return
      dispatchRef.current({ type: 'TRANSFERS', events })
      queryClient.invalidateQueries({ queryKey: ['walletCoins', addr] })
    }

    async function start() {
      await client.connect()
      if (cancelled) return

      // ── 1. Coins sent FROM this address ───────────────────────────────────
      subscriptions.push(
        await client.subscribeTransfer<CoinTransferBatch>({
          packageId: '0x2',
          module: 'coin',
          typeName: 'Coin',
          match: { _sender: addr },
          onEvent: handleBatch,
        }),
      )

      if (cancelled) return

      // ── 2. Coins received BY this address ─────────────────────────────────
      subscriptions.push(
        await client.subscribeTransfer<CoinTransferBatch>({
          packageId: '0x2',
          module: 'coin',
          typeName: 'Coin',
          match: { _to: addr },
          onEvent: handleBatch,
        }),
      )
    }

    start().catch(console.error)

    return () => {
      cancelled = true
      for (const sub of subscriptions) sub.unsubscribe()
      if (seenTimer) clearTimeout(seenTimer)
      client.disconnect()
    }
  }, [walletAddress, enabled, queryClient])

  return state
}
