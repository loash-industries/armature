import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import { getObject, getDynamicFields, queryEvents, unwrapMoveStruct } from "@/lib/sui-rpc";
import { PACKAGE_ID, PROPOSALS_PACKAGE_ID, MODULES, PROPOSAL_MODULES } from "@/config/constants";
import { ALL_PROPOSAL_TYPE_KEYS } from "@/config/proposal-types";
import type {
  DaoFields,
  DaoSummary,
  CharterFields,
  CharterDetail,
  TreasuryVaultFields,
  TreasuryCoinBalance,
  EmergencyFreezeFields,
  EmergencyFreezeDetail,
  GovernanceDetail,
  GovernanceMember,
  ActivityEvent,
  ProposalTypeConfig,
} from "@/types/dao";

/** Extract typed fields from a SuiObjectResponse's MoveStruct content. */
function moveFields<T>(obj: { data?: { content?: unknown } | null }): T {
  const content = obj.data?.content as
    | { fields: unknown; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") {
    throw new Error("Object has no Move content");
  }
  return unwrapMoveStruct(content.fields) as T;
}

/** Fetch and parse the DAO object into a DaoSummary. */
export function useDaoSummary(daoId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.dao(daoId),
    queryFn: async (): Promise<DaoSummary> => {
      const daoObj = await getObject(client, daoId);
      const dao = moveFields<DaoFields>(daoObj);

      const charterObj = await getObject(client, dao.charter_id);
      const charter = moveFields<CharterFields>(charterObj);

      const freezeObj = await getObject(client, dao.emergency_freeze_id);
      const freeze = moveFields<EmergencyFreezeFields>(freezeObj);

      const statusVariant =
        "variant" in dao.status ? dao.status.variant : "Active";

      let boardMemberCount = 0;
      if (dao.governance.variant === "Board") {
        boardMemberCount = dao.governance.fields.members.contents.length;
      } else if (dao.governance.variant === "Direct") {
        boardMemberCount = dao.governance.fields.voters.contents.length;
      } else if (dao.governance.variant === "Weighted") {
        boardMemberCount = dao.governance.fields.delegates.contents.length;
      }

      return {
        id: daoId,
        status: statusVariant as "Active" | "Migrating",
        isSubdao: (dao.controller_cap_id?.vec?.length ?? 0) > 0,
        boardMemberCount,
        treasuryId: dao.treasury_id,
        charterId: dao.charter_id,
        charterName: charter.name,
        emergencyFreezeId: dao.emergency_freeze_id,
        capabilityVaultId: dao.capability_vault_id,
        enabledProposalTypes: dao.enabled_proposal_types.contents,
        frozenTypes: freeze.frozen_types.contents.map((e) => ({
          typeKey: e.key,
          expiryMs: Number(e.value),
        })),
      };
    },
    enabled: !!daoId,
  });
}

/** Fetch treasury coin balances by reading the TreasuryVault dynamic fields. */
export function useTreasuryBalances(treasuryId: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.treasury(treasuryId ?? ""),
    queryFn: async (): Promise<TreasuryCoinBalance[]> => {
      if (!treasuryId) return [];

      const vaultObj = await getObject(client, treasuryId);
      const vault = moveFields<TreasuryVaultFields>(vaultObj);
      const coinTypes = vault.coin_types.contents;

      if (coinTypes.length === 0) return [];

      const fields = await getDynamicFields(client, treasuryId);

      const results = await Promise.all(
        fields.map(async (field) => {
          const fieldObj = await client.getDynamicFieldObject({
            parentId: treasuryId,
            name: field.name,
          });
          const content = fieldObj.data?.content as
            | { fields: { value: string }; dataType: "moveObject" }
            | undefined;
          if (content?.dataType !== "moveObject") return null;
          const rawCoinType =
            typeof field.name.value === "string"
              ? field.name.value
              : String(field.name.value);
          const coinType = rawCoinType.startsWith("0x") ? rawCoinType : `0x${rawCoinType}`;
          return { coinType, balance: BigInt(content.fields.value), decimals: 6 };
        }),
      );

      return results.filter((b): b is TreasuryCoinBalance => b !== null);
    },
    enabled: !!treasuryId,
  });
}

export interface CoinMeta {
  symbol: string;
  name: string;
  decimals: number;
  iconUrl: string | null;
}

/** Fetch on-chain CoinMetadata for an array of coin types. */
export function useCoinMetadataMap(coinTypes: string[]) {
  const client = useSuiClient();
  const key = coinTypes.slice().sort().join(",");

  return useQuery({
    queryKey: [...cacheKeys.coinMetadata(key)],
    queryFn: async (): Promise<Record<string, CoinMeta>> => {
      const entries = await Promise.all(
        coinTypes.map(async (ct) => {
          try {
            const normalizedCt = ct.startsWith("0x") ? ct : `0x${ct}`;
            const meta = await client.getCoinMetadata({ coinType: normalizedCt });
            if (!meta) return [ct, null] as const;
            return [
              ct,
              {
                symbol: meta.symbol,
                name: meta.name,
                decimals: meta.decimals,
                // Normalize empty string to null; provide SUI's well-known icon
                // since the on-chain metadata has iconUrl: "" on all networks.
                iconUrl: (meta.iconUrl || SUI_ICON_FALLBACKS[normalizedCt] || null) as string | null,
              } satisfies CoinMeta,
            ] as const;
          } catch {
            return [ct, null] as const;
          }
        }),
      );
      return Object.fromEntries(
        entries.filter((e): e is [string, CoinMeta] => e[1] !== null),
      );
    },
    enabled: coinTypes.length > 0,
    staleTime: 5 * 60 * 1000,
  });
}

/** Well-known icon URLs for coins whose on-chain metadata has no iconUrl. */
const SUI_ICON_FALLBACKS: Record<string, string> = {
  "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI":
    "https://s2.coinmarketcap.com/static/img/coins/64x64/20947.png",
  "0x2::sui::SUI":
    "https://s2.coinmarketcap.com/static/img/coins/64x64/20947.png",
};

/** Extract a Sui object ID string from parsedJson field (handles bare string or {id: "0x..."} wrapper). */
function extractId(val: unknown): string | undefined {
  if (typeof val === "string") return val;
  if (val && typeof val === "object" && "id" in val) return String((val as { id: unknown }).id);
  return undefined;
}

/** Fetch recent DAO events for the activity feed. */
export function useDaoActivity(daoId: string, treasuryId?: string, limit = 20) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.events("dao-activity", daoId),
    queryFn: async (): Promise<ActivityEvent[]> => {
      const sources = [
        { pkg: PACKAGE_ID, mod: MODULES.dao },
        { pkg: PACKAGE_ID, mod: MODULES.proposal },
        // ProposalCreated is emitted via board_voting::submit_proposal, so Sui
        // indexes it under board_voting rather than the proposal module.
        { pkg: PACKAGE_ID, mod: MODULES.board_voting },
        { pkg: PACKAGE_ID, mod: MODULES.treasury_vault },
        { pkg: PACKAGE_ID, mod: MODULES.emergency },
        { pkg: PROPOSALS_PACKAGE_ID, mod: PROPOSAL_MODULES.treasury_ops },
        { pkg: PROPOSALS_PACKAGE_ID, mod: PROPOSAL_MODULES.security_ops },
        { pkg: PROPOSALS_PACKAGE_ID, mod: PROPOSAL_MODULES.board_ops },
      ];

      const matchIds = new Set([daoId]);
      if (treasuryId) matchIds.add(treasuryId);

      const allEvents: ActivityEvent[] = [];

      for (const { pkg, mod } of sources) {
        try {
          const result = await queryEvents(
            client,
            { MoveModule: { package: pkg, module: mod } },
            undefined,
            limit,
          );

          for (const ev of result.data) {
            const parsed = ev.parsedJson as Record<string, unknown>;
            const evDaoId = extractId(parsed.dao_id);
            const evVaultId = extractId(parsed.vault_id);

            // Match if either dao_id or vault_id matches our DAO or treasury
            const matches =
              (evDaoId && matchIds.has(evDaoId)) ||
              (evVaultId && matchIds.has(evVaultId));
            if (!matches) continue;

            const typeParts = ev.type.split("::");
            const eventName = typeParts[typeParts.length - 1] ?? ev.type;

            allEvents.push({
              txDigest: ev.id.txDigest,
              eventType: eventName,
              label: eventLabel(eventName),
              description: eventDescription(eventName, parsed),
              timestampMs: Number(ev.timestampMs ?? 0),
              ...extractEventFields(eventName, parsed),
            });
          }
        } catch {
          // Module may not exist on-chain yet; skip silently
        }
      }

      // Deduplicate: when a treasury proposal executes, both treasury_vault
      // (CoinWithdrawn) and treasury_ops (CoinSent / CoinSentToDAO / SmallPaymentSent)
      // emit events in the same tx. Keep only the higher-level ops event.
      const HIGH_LEVEL_TREASURY = new Set(["CoinSent", "CoinSentToDAO", "SmallPaymentSent"]);
      const txHasHighLevel = new Set(
        allEvents
          .filter((e) => HIGH_LEVEL_TREASURY.has(e.eventType))
          .map((e) => e.txDigest),
      );
      const deduped = allEvents.filter(
        (e) => e.eventType !== "CoinWithdrawn" || !txHasHighLevel.has(e.txDigest),
      );

      deduped.sort((a, b) => b.timestampMs - a.timestampMs);
      return deduped.slice(0, limit);
    },
    enabled: !!daoId,
  });
}

/** Fetch governance members for the Board page. */
export function useGovernanceDetail(daoId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.board(daoId),
    queryFn: async (): Promise<GovernanceDetail> => {
      const daoObj = await getObject(client, daoId);
      const dao = moveFields<DaoFields>(daoObj);
      const gov = dao.governance;

      if (gov.variant === "Board") {
        return {
          type: "Board",
          members: gov.fields.members.contents.map((addr) => ({
            address: addr,
          })),
        };
      } else if (gov.variant === "Direct") {
        return {
          type: "Direct",
          members: gov.fields.voters.contents.map(
            (e): GovernanceMember => ({
              address: e.key,
              weight: Number(e.value),
            }),
          ),
          totalShares: Number(gov.fields.total_shares),
        };
      } else {
        return {
          type: "Weighted",
          members: gov.fields.delegates.contents.map(
            (e): GovernanceMember => ({
              address: e.key,
              weight: Number(e.value),
            }),
          ),
          totalShares: Number(gov.fields.total_delegated),
        };
      }
    },
    enabled: !!daoId,
  });
}

/** Fetch charter details for the Charter page. */
export function useCharterDetail(charterId: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.charter(charterId ?? ""),
    queryFn: async (): Promise<CharterDetail> => {
      const obj = await getObject(client, charterId!);
      const charter = moveFields<CharterFields>(obj);
      return {
        id: charterId!,
        name: charter.name,
        description: charter.description,
        imageUrl: charter.image_url,
      };
    },
    enabled: !!charterId,
  });
}

/** Fetch emergency freeze details for the Emergency page. */
export function useEmergencyFreezeDetail(freezeId: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.emergency(freezeId ?? ""),
    queryFn: async (): Promise<EmergencyFreezeDetail> => {
      const obj = await getObject(client, freezeId!);
      const freeze = moveFields<EmergencyFreezeFields>(obj);
      return {
        id: freezeId!,
        frozenTypes: freeze.frozen_types.contents.map((e) => ({
          typeKey: e.key,
          expiryMs: Number(e.value),
        })),
        maxFreezeDurationMs: Number(freeze.max_freeze_duration_ms),
      };
    },
    enabled: !!freezeId,
  });
}

/** Fetch treasury-specific events for a DAO.
 *
 * Because the Sui RPC `queryEvents` filter only supports module-level granularity
 * (no field-value matching), we paginate through pages of up to `PAGE_SIZE` events
 * and filter client-side until we have collected `limit` matching events or we run
 * out of pages (capped at `MAX_PAGES` to prevent unbounded fetching).
 *
 * Accepts an optional `treasuryId` (vault object ID) so we can match against
 * `vault_id` in event data as well — guarding against any DAO-ID format mismatch.
 * Both IDs are normalised to lowercase before comparison.
 */
export function useTreasuryEvents(daoId: string, treasuryId?: string, limit = 20) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.events("treasury", daoId),
    queryFn: async (): Promise<ActivityEvent[]> => {
      const PAGE_SIZE = 50;
      const MAX_PAGES = 10;

      // Query both the low-level vault module and the higher-level proposal
      // treasury_ops module so that CoinSent / CoinSentToDAO / SmallPaymentSent
      // appear alongside CoinDeposited / CoinWithdrawn / CoinClaimed.
      const sources = [
        { package: PACKAGE_ID, module: MODULES.treasury_vault },
        { package: PROPOSALS_PACKAGE_ID, module: PROPOSAL_MODULES.treasury_ops },
      ];

      // Normalise to lowercase so hex-case differences don't break matching.
      const normDaoId = daoId.toLowerCase();
      const normVaultId = treasuryId?.toLowerCase();

      const allMatched: ActivityEvent[] = [];

      for (const src of sources) {
        const filter = { MoveModule: src };
        let cursor: string | undefined;
        let pages = 0;
        let collected = 0;

        try {
          while (collected < limit && pages < MAX_PAGES) {
            const result = await queryEvents(client, filter, cursor, PAGE_SIZE);
            pages++;

            for (const ev of result.data) {
              const parsed = ev.parsedJson as Record<string, unknown>;
              const evDaoId = extractId(parsed.dao_id)?.toLowerCase();
              const evVaultId = extractId(parsed.vault_id)?.toLowerCase();

              const matchesDaoId = evDaoId === normDaoId;
              const matchesVaultId = normVaultId !== undefined && evVaultId === normVaultId;
              if (!matchesDaoId && !matchesVaultId) continue;

              const typeParts = ev.type.split("::");
              const eventName = typeParts[typeParts.length - 1] ?? ev.type;
              allMatched.push({
                txDigest: ev.id.txDigest,
                eventType: eventName,
                label: eventLabel(eventName),
                description: eventDescription(eventName, parsed),
                timestampMs: Number(ev.timestampMs ?? 0),
                ...extractEventFields(eventName, parsed),
              });

              collected++;
              if (collected >= limit) break;
            }

            if (!result.hasNextPage || !result.nextCursor) break;
            cursor = result.nextCursor ?? undefined;
          }
        } catch (err) {
          console.error("[useTreasuryEvents] RPC error for module %s:", src.module, err);
        }
      }

      // Deduplicate: when both CoinWithdrawn (vault) and CoinSent (ops) exist
      // for the same txDigest, keep only the higher-level ops event.
      const HIGH_LEVEL_TREASURY = new Set(["CoinSent", "CoinSentToDAO", "SmallPaymentSent"]);
      const txHasHighLevel = new Set(
        allMatched
          .filter((e) => HIGH_LEVEL_TREASURY.has(e.eventType))
          .map((e) => e.txDigest),
      );
      const deduped = allMatched.filter(
        (e) => e.eventType !== "CoinWithdrawn" || !txHasHighLevel.has(e.txDigest),
      );

      deduped.sort((a, b) => b.timestampMs - a.timestampMs);
      return deduped.slice(0, limit);
    },
    enabled: !!daoId,
  });
}

const PROTECTED_TYPES = new Set(["TransferFreezeAdmin", "UnfreezeProposalType"]);

/** Fetch governance config: all proposal types with their enabled/frozen/protected status and config. */
export function useGovernanceConfig(daoId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.governance(daoId),
    queryFn: async (): Promise<ProposalTypeConfig[]> => {
      const daoObj = await getObject(client, daoId);
      const dao = moveFields<DaoFields>(daoObj);

      const freezeObj = await getObject(client, dao.emergency_freeze_id);
      const freeze = moveFields<EmergencyFreezeFields>(freezeObj);

      const enabledSet = new Set(dao.enabled_proposal_types.contents);
      const frozenSet = new Set(
        freeze.frozen_types.contents
          .filter((e) => Number(e.value) > Date.now())
          .map((e) => e.key),
      );

      const configMap = new Map(
        dao.proposal_configs.contents.map((e) => [e.key, e.value]),
      );

      return ALL_PROPOSAL_TYPE_KEYS.map((typeKey) => {
        const raw = configMap.get(typeKey);
        return {
          typeKey,
          enabled: enabledSet.has(typeKey),
          frozen: frozenSet.has(typeKey),
          protected: PROTECTED_TYPES.has(typeKey),
          config: raw
            ? {
                quorum: Number(raw.quorum),
                approvalThreshold: Number(raw.approval_threshold),
                proposeThreshold: Number(raw.propose_threshold),
                expiryMs: Number(raw.expiry_ms),
                executionDelayMs: Number(raw.execution_delay_ms),
                cooldownMs: Number(raw.cooldown_ms),
              }
            : null,
        };
      });
    },
    enabled: !!daoId,
  });
}

function eventLabel(eventName: string): string {
  const labels: Record<string, string> = {
    DAOCreated: "Charter",
    DAODestroyed: "Charter",
    ProposalCreated: "Proposals",
    VoteCast: "Proposals",
    ProposalPassed: "Proposals",
    ProposalExecuted: "Proposals",
    ProposalExpired: "Proposals",
    TypeFrozen: "Emergency",
    TypeUnfrozen: "Emergency",
    FreezeAdminTransferred: "Emergency",
    FreezeConfigUpdated: "Emergency",
    FreezeExemptTypeAdded: "Emergency",
    FreezeExemptTypeRemoved: "Emergency",
    CoinDeposited: "Deposit",
    CoinWithdrawn: "Withdrawal",
    CoinClaimed: "Claim",
    CoinSent: "Withdrawal",
    CoinSentToDAO: "Withdrawal",
    SmallPaymentSent: "Withdrawal",
    BoardUpdated: "Board",
    MetadataUpdated: "Charter",
    ProposalTypeEnabled: "Proposals",
    ProposalTypeDisabled: "Proposals",
    ProposalConfigUpdated: "Proposals",
  };
  return labels[eventName] ?? "Proposals";
}

function eventDescription(
  eventName: string,
  parsed: Record<string, unknown>,
): string {
  switch (eventName) {
    case "ProposalCreated":
      return `Created ${parsed.type_key ?? "unknown"} proposal ${truncId(parsed.proposal_id)}`;
    case "VoteCast":
      return `Voted ${parsed.approve ? "Yes" : "No"} (weight: ${parsed.weight})`;
    case "ProposalPassed":
      return `Proposal ${truncId(parsed.proposal_id)} passed (${parsed.yes_weight} yes / ${parsed.no_weight} no)`;
    case "ProposalExecuted":
      return `Executed proposal ${truncId(parsed.proposal_id)}`;
    case "ProposalExpired":
      return `Proposal ${truncId(parsed.proposal_id)} expired`;
    case "TypeFrozen":
      return `Froze ${parsed.type_key}`;
    case "TypeUnfrozen":
      return `Unfroze ${parsed.type_key}`;
    case "FreezeAdminTransferred":
      return `Freeze admin transferred to ${truncId(parsed.new_admin)}`;
    case "FreezeConfigUpdated":
      return `Freeze config updated`;
    case "CoinDeposited":
      return `Deposited coins`;
    case "CoinWithdrawn":
      return `Withdrew coins`;
    case "CoinClaimed":
      return `Claimed coins`;
    case "CoinSent":
      return `Sent coins to ${truncId(parsed.recipient)}`;
    case "CoinSentToDAO":
      return `Sent coins to Organization or OU treasury ${truncId(parsed.target_treasury)}`;
    case "SmallPaymentSent":
      return `Small payment sent to ${truncId(parsed.recipient)}`;
    case "BoardUpdated":
      return `Board membership updated`;
    case "DAOCreated":
      return `DAO created`;
    case "DAODestroyed":
      return `DAO destroyed`;
    case "MetadataUpdated":
      return `Metadata updated`;
    case "ProposalTypeEnabled":
      return `Enabled proposal type ${parsed.type_key}`;
    case "ProposalTypeDisabled":
      return `Disabled proposal type ${parsed.type_key}`;
    case "ProposalConfigUpdated":
      return `Updated config for ${parsed.target_type_key}`;
    default:
      return eventName;
  }
}

/** Extract structured fields from event data for rich rendering. */
function extractEventFields(
  eventName: string,
  parsed: Record<string, unknown>,
): Partial<ActivityEvent> {
  switch (eventName) {
    case "VoteCast":
      return {
        actor: parsed.voter as string,
        approve: parsed.approve as boolean,
        proposalId: parsed.proposal_id as string,
      };
    case "ProposalCreated":
      return {
        actor: parsed.proposer as string,
        typeKey: parsed.type_key as string,
        proposalId: parsed.proposal_id as string,
      };
    case "ProposalExecuted":
      return {
        actor: parsed.executor as string,
        proposalId: parsed.proposal_id as string,
      };
    case "ProposalPassed":
      return { proposalId: parsed.proposal_id as string };
    case "ProposalExpired":
      return { proposalId: parsed.proposal_id as string };
    case "TypeFrozen":
    case "TypeUnfrozen":
      return { typeKey: parsed.type_key as string };
    case "CoinDeposited":
      return {
        actor: parsed.depositor as string,
        coinType: parsed.coin_type as string,
        coinAmount: String(parsed.amount ?? "0"),
      };
    case "CoinWithdrawn":
      return {
        recipient: parsed.recipient as string,
        coinType: parsed.coin_type as string,
        coinAmount: String(parsed.amount ?? "0"),
      };
    case "CoinClaimed":
      return {
        actor: parsed.claimer as string,
        coinType: parsed.coin_type as string,
        coinAmount: String(parsed.amount ?? "0"),
      };
    case "CoinSent":
      return {
        recipient: parsed.recipient as string,
        coinType: parsed.coin_type as string,
        coinAmount: String(parsed.amount ?? "0"),
      };
    case "CoinSentToDAO":
      return {
        recipient: parsed.target_treasury as string,
        coinType: parsed.coin_type as string,
        coinAmount: String(parsed.amount ?? "0"),
      };
    case "SmallPaymentSent":
      return {
        recipient: parsed.recipient as string,
        coinType: parsed.coin_type as string,
        coinAmount: String(parsed.amount ?? "0"),
      };
    case "DAOCreated":
      return { actor: parsed.creator as string };
    case "BoardUpdated":
      return {};
    case "FreezeAdminTransferred":
      return { recipient: parsed.new_admin as string };
    default:
      return {};
  }
}

function truncId(val: unknown): string {
  const s = String(val ?? "");
  if (s.length <= 10) return s;
  return `${s.slice(0, 6)}...${s.slice(-4)}`;
}
