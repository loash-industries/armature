import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "path";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: [{ find: "@", replacement: path.resolve(__dirname, "src") }],
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
  },
  test: {
    environment: "node",
    globals: true,
    alias: [{ find: "@", replacement: path.resolve(__dirname, "src") }],
    // Exclude integration tests — those require a running localnet (yarn test:integration)
    exclude: ["src/**/__tests__/integration/**", "node_modules/**"],
  },
});
