// Canonical relay-sdk + TanStack React Query integration hook.
// Source: @loash-industries/relay-sdk docs/react-query.md
//
// Manages a RelayClient connection and pushes each incoming event into the
// React Query cache under `queryKey`. Components read from the cache via
// useQuery — they stay fully decoupled from the WebSocket itself.

import { useEffect, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { RelayClient } from '@loash-industries/relay-sdk'
import type { FilterValue, RelayEvent, RelayNetwork } from '@loash-industries/relay-sdk'

export interface UseRelayEventsOptions {
  network: RelayNetwork
  token: string
  packageId: string
  module?: string
  eventName?: string
  match?: Record<string, FilterValue>
  /**
   * The React Query key that incoming events are written to.
   * Use the same key in useQuery to read the accumulated list.
   *
   * Cache entry type: RelayEvent<T>[]
   */
  queryKey: unknown[]
  /** Max events to keep in cache (oldest dropped). Defaults to 100. */
  maxEvents?: number
  onError?: (err: Error) => void
  /** When false the hook is a no-op. Defaults true. */
  enabled?: boolean
}

export function useRelayEvents<T = Record<string, unknown>>(
  options: UseRelayEventsOptions,
): void {
  const {
    network,
    token,
    packageId,
    module,
    eventName,
    match,
    queryKey,
    maxEvents = 100,
    onError,
    enabled = true,
  } = options

  const queryClient = useQueryClient()
  const clientRef = useRef<RelayClient | null>(null)

  useEffect(() => {
    if (!enabled) return

    const client = new RelayClient(network, { token })
    clientRef.current = client

    let cancelled = false

    async function start() {
      try {
        await client.connect()
        if (cancelled) return

        await client.subscribe<T>({
          packageId,
          module,
          eventName,
          match,
          onEvent: (event: RelayEvent<T>) => {
            queryClient.setQueryData<RelayEvent<T>[]>(queryKey, (prev = []) => {
              const next = [...prev, event]
              return next.length > maxEvents ? next.slice(-maxEvents) : next
            })
          },
          onError,
        })
      } catch (err) {
        if (!cancelled) {
          onError?.(err instanceof Error ? err : new Error(String(err)))
        }
      }
    }

    start()

    return () => {
      cancelled = true
      client.disconnect()
      clientRef.current = null
    }
    // JSON.stringify(match) prevents spurious reconnects from inline object literals.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, network, token, packageId, module, eventName, JSON.stringify(match)])
}
