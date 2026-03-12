import { createNetworkConfig } from "@mysten/dapp-kit";
import { getJsonRpcFullnodeUrl } from "@mysten/sui/jsonRpc";

const { networkConfig, useNetworkVariable } = createNetworkConfig({
  localnet: {
    url: getJsonRpcFullnodeUrl("localnet"),
    network: "localnet",
  },
  devnet: {
    url: getJsonRpcFullnodeUrl("devnet"),
    network: "devnet",
  },
  testnet: {
    url: getJsonRpcFullnodeUrl("testnet"),
    network: "testnet",
  },
  mainnet: {
    url: getJsonRpcFullnodeUrl("mainnet"),
    network: "mainnet",
  },
});

export { networkConfig, useNetworkVariable };
