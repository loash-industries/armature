import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AWARProvider } from "@awar.dev/ui";
import App from "./App";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <AWARProvider>
      <App />
    </AWARProvider>
  </StrictMode>,
);
