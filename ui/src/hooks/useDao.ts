import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import { getObject, getDynamicFields, queryEvents } from "@/lib/sui-rpc";
import { PACKAGE_ID, MODULES } from "@/config/constants";
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
    | { fields: T; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") {
    throw new Error("Object has no Move content");
  }
  return content.fields;
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

      const balances: TreasuryCoinBalance[] = [];
      for (const field of fields) {
        const fieldObj = await client.getDynamicFieldObject({
          parentId: treasuryId,
          name: field.name,
        });
        const content = fieldObj.data?.content as
          | { fields: { value: string }; dataType: "moveObject" }
          | undefined;
        if (content?.dataType === "moveObject") {
          const coinType =
            typeof field.name.value === "string"
              ? field.name.value
              : String(field.name.value);
          balances.push({
            coinType,
            balance: BigInt(content.fields.value),
          });
        }
      }

      return balances;
    },
    enabled: !!treasuryId,
  });
}

/** Fetch recent DAO events for the activity feed. */
export function useDaoActivity(daoId: string, limit = 10) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.events("dao-activity", daoId),
    queryFn: async (): Promise<ActivityEvent[]> => {
      const modules = [
        MODULES.dao,
        MODULES.proposal,
        MODULES.treasury_vault,
        MODULES.emergency,
      ];

      const allEvents: ActivityEvent[] = [];

      for (const mod of modules) {
        try {
          const result = await queryEvents(
            client,
            { MoveModule: { package: PACKAGE_ID, module: mod } },
            undefined,
            limit,
          );

          for (const ev of result.data) {
            const parsed = ev.parsedJson as Record<string, unknown>;
            const evDaoId =
              (parsed.dao_id as string) ?? (parsed.vault_id as string);

            if (evDaoId && evDaoId !== daoId) continue;

            const typeParts = ev.type.split("::");
            const eventName = typeParts[typeParts.length - 1] ?? ev.type;

            allEvents.push({
              txDigest: ev.id.txDigest,
              eventType: eventName,
              label: eventLabel(eventName),
              description: eventDescription(eventName, parsed),
              timestampMs: Number(ev.timestampMs ?? 0),
            });
          }
        } catch {
          // Module may not exist on-chain yet; skip silently
        }
      }

      allEvents.sort((a, b) => b.timestampMs - a.timestampMs);
      return allEvents.slice(0, limit);
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

/** Fetch treasury-specific events (CoinClaimed). */
export function useTreasuryEvents(daoId: string, limit = 20) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.events("treasury", daoId),
    queryFn: async (): Promise<ActivityEvent[]> => {
      try {
        const result = await queryEvents(
          client,
          {
            MoveModule: {
              package: PACKAGE_ID,
              module: MODULES.treasury_vault,
            },
          },
          undefined,
          limit,
        );

        return result.data
          .filter((ev) => {
            const parsed = ev.parsedJson as Record<string, unknown>;
            return (
              (parsed.dao_id as string) === daoId ||
              (parsed.vault_id as string) === daoId
            );
          })
          .map((ev) => {
            const parsed = ev.parsedJson as Record<string, unknown>;
            const typeParts = ev.type.split("::");
            const eventName = typeParts[typeParts.length - 1] ?? ev.type;
            return {
              txDigest: ev.id.txDigest,
              eventType: eventName,
              label: eventLabel(eventName),
              description: eventDescription(eventName, parsed),
              timestampMs: Number(ev.timestampMs ?? 0),
            };
          });
      } catch {
        return [];
      }
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
    DAOCreated: "Created",
    ProposalCreated: "Proposal",
    VoteCast: "Vote",
    ProposalPassed: "Passed",
    ProposalExecuted: "Executed",
    ProposalExpired: "Expired",
    TypeFrozen: "Frozen",
    TypeUnfrozen: "Unfrozen",
    CoinClaimed: "Claimed",
  };
  return labels[eventName] ?? eventName;
}

function eventDescription(
  eventName: string,
  parsed: Record<string, unknown>,
): string {
  switch (eventName) {
    case "ProposalCreated":
      return `Proposal ${truncId(parsed.proposal_id)} created (${parsed.type_key ?? "unknown"})`;
    case "VoteCast":
      return `${truncId(parsed.voter)} voted ${parsed.approve ? "Yes" : "No"} (weight: ${parsed.weight})`;
    case "ProposalPassed":
      return `Proposal ${truncId(parsed.proposal_id)} passed (${parsed.yes_weight}/${parsed.no_weight})`;
    case "ProposalExecuted":
      return `Proposal ${truncId(parsed.proposal_id)} executed by ${truncId(parsed.executor)}`;
    case "ProposalExpired":
      return `Proposal ${truncId(parsed.proposal_id)} expired`;
    case "TypeFrozen":
      return `Type "${parsed.type_key}" frozen`;
    case "TypeUnfrozen":
      return `Type "${parsed.type_key}" unfrozen`;
    case "CoinClaimed":
      return `${parsed.amount} claimed by ${truncId(parsed.claimer)}`;
    case "DAOCreated":
      return `DAO created by ${truncId(parsed.creator)}`;
    default:
      return eventName;
  }
}

function truncId(val: unknown): string {
  const s = String(val ?? "");
  if (s.length <= 10) return s;
  return `${s.slice(0, 6)}...${s.slice(-4)}`;
}
