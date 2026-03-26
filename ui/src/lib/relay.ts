import type { RelayNetwork } from '@loash-industries/relay-sdk'

/**
 * Relay network resolved from VITE_RELAY_NETWORK.
 * Defaults to 'testnet'. Set to 'mainnet' for production.
 */
export const RELAY_NETWORK: RelayNetwork =
  (import.meta.env.VITE_RELAY_NETWORK as RelayNetwork | undefined) ?? 'testnet'

/**
 * Relay API token from VITE_RELAY_TOKEN.
 * When empty the relay hooks are disabled (localnet / offline dev).
 */
export const RELAY_TOKEN: string = import.meta.env.VITE_RELAY_TOKEN ?? ''
