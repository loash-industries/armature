import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  resolve: {
    alias: [{ find: "@", replacement: path.resolve(__dirname, "src") }],
  },
  test: {
    environment: "node",
    globals: true,
    // Unit tests only — integration tests have their own config.
    include: ["src/**/__tests__/*.test.ts"],
    exclude: ["src/**/__tests__/integration/**"],
  },
});
