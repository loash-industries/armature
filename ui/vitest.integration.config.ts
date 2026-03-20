import { defineConfig } from "vitest/config";
import path from "path";

/**
 * Vitest config for integration tests.
 *
 * Requires a running localnet:  make dev
 * Run with:                     yarn test:integration
 *
 * Env vars (auto-loaded from .env.local or environment):
 *   VITE_PACKAGE_ID            — armature_framework package ID
 *   VITE_PROPOSALS_PACKAGE_ID  — armature_proposals package ID
 *   VITE_RPC_URL               — fullnode RPC (default: http://localhost:9000)
 *   VITE_FAUCET_URL            — faucet endpoint (default: http://localhost:9123)
 */
export default defineConfig({
  resolve: {
    alias: [{ find: "@", replacement: path.resolve(__dirname, "src") }],
  },
  test: {
    environment: "node",
    globals: true,
    include: ["src/**/__tests__/integration/**/*.test.ts"],
    // Integration tests hit a real network — generous timeouts.
    testTimeout: 60_000,
    hookTimeout: 30_000,
    // Run integration suites sequentially to avoid nonce/gas conflicts.
    pool: "forks",
    poolOptions: { forks: { singleFork: true } },
    // Load .env.local so VITE_PACKAGE_ID etc. are available.
    env: {},
  },
});
