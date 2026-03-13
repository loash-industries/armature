export const cacheKeys = {
  dao: (id: string) => ["dao", id] as const,
  treasury: (daoId: string) => ["treasury", daoId] as const,
  treasuryBalance: (daoId: string, coinType: string) =>
    ["treasury", daoId, "balance", coinType] as const,
  capVault: (daoId: string) => ["capVault", daoId] as const,
  capVaultEntries: (vaultId: string) => ["capVaultEntries", vaultId] as const,
  proposals: (daoId: string) => ["proposals", daoId] as const,
  proposal: (id: string) => ["proposal", id] as const,
  board: (daoId: string) => ["board", daoId] as const,
  charter: (daoId: string) => ["charter", daoId] as const,
  governance: (daoId: string) => ["governance", daoId] as const,
  emergency: (daoId: string) => ["emergency", daoId] as const,
  subdaos: (daoId: string) => ["subdaos", daoId] as const,
  hierarchy: (daoId: string) => ["hierarchy", daoId] as const,
  ownedDaos: (address: string) => ["ownedDaos", address] as const,
  events: (module: string, cursor?: string) =>
    ["events", module, cursor] as const,
};
