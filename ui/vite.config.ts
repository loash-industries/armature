import path from "path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: [
      { find: "@", replacement: "/src" },
      // The `ws` npm package throws in browser builds. The relay-sdk uses it
      // only for its types/constructor — shim it with the native WebSocket.
      { find: "ws", replacement: path.resolve(__dirname, "src/lib/ws-browser-shim.ts") },
    ],
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
  },
});
