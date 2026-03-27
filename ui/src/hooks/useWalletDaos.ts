import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import { multiGetObjects, queryEvents, unwrapMoveStruct } from "@/lib/sui-rpc";
import { PACKAGE_ID, PROPOSALS_PACKAGE_ID, MODULES, PROPOSAL_MODULES } from "@/config/constants";
import type { DaoFields, CharterFields } from "@/types/dao";

export interface DaoEntry {
  daoId: string;
  name: string;
  treasury: string;
  memberCount: number;
  activeProposals: number;
  isSubDAO?: boolean;
  memberAddresses: string[];
  capabilityVaultId: string;
}

function moveFields<T>(obj: { data?: { content?: unknown } | null }): T {
  const content = obj.data?.content as
    | { fields: unknown; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") {
    throw new Error("Object has no Move content");
  }
  return unwrapMoveStruct(content.fields) as T;
}

function truncId(id: string): string {
  if (id.length <= 10) return id;
  return `${id.slice(0, 6)}...${id.slice(-4)}`;
}

function isMemberOf(dao: DaoFields, address: string): boolean {
  const gov = dao.governance;
  if (gov.variant === "Board") {
    return gov.fields.members.contents.includes(address);
  } else if (gov.variant === "Direct") {
    return gov.fields.voters.contents.some((e) => e.key === address);
  } else if (gov.variant === "Weighted") {
    return gov.fields.delegates.contents.some((e) => e.key === address);
  }
  return false;
}

function memberCount(dao: DaoFields): number {
  const gov = dao.governance;
  if (gov.variant === "Board") return gov.fields.members.contents.length;
  if (gov.variant === "Direct") return gov.fields.voters.contents.length;
  if (gov.variant === "Weighted") return gov.fields.delegates.contents.length;
  return 0;
}

/** Fetch all DAOs that the given wallet address is a governance member of. */
export function useWalletDaos(address: string | null | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.ownedDaos(address ?? ""),
    queryFn: async (): Promise<DaoEntry[]> => {
      if (!address) return [];

      // 1. Collect all DAO IDs from DAOCreated events (paginate up to 5 pages)
      const daoIds: string[] = [];
      let cursor: string | undefined;
      let hasNext = true;
      let pages = 0;

      while (hasNext && pages < 5) {
        const result = await queryEvents(
          client,
          { MoveModule: { package: PACKAGE_ID, module: MODULES.dao } },
          cursor,
          50,
        );
        console.log(result)
        for (const ev of result.data) {
          if (!ev.type.endsWith("::DAOCreated")) continue;
          const parsed = ev.parsedJson as { dao_id?: string };
          if (parsed.dao_id) daoIds.push(parsed.dao_id);
        }

        cursor = result.nextCursor ?? undefined;
        hasNext = result.hasNextPage;
        pages++;
      }

      // 2. Also collect sub-DAO IDs from SubDAOCreated events
      const subDaoIds: string[] = [];
      let subCursor: string | undefined;
      let subHasNext = true;
      let subPages = 0;

      while (subHasNext && subPages < 5) {
        const subResult = await queryEvents(
          client,
          { MoveModule: { package: PROPOSALS_PACKAGE_ID, module: PROPOSAL_MODULES.subdao_ops } },
          subCursor,
          50,
        );
        for (const ev of subResult.data) {
          if (!ev.type.endsWith("::SubDAOCreated")) continue;
          const parsed = ev.parsedJson as { subdao_id?: string };
          if (parsed.subdao_id) subDaoIds.push(parsed.subdao_id);
        }
        subCursor = subResult.nextCursor ?? undefined;
        subHasNext = subResult.hasNextPage;
        subPages++;
      }

      const allIds = [...new Set([...daoIds, ...subDaoIds])];
      if (allIds.length === 0) return [];

      // 3. Batch fetch all DAO objects in chunks of 50
      const allDaoObjs = [];
      for (let i = 0; i < allIds.length; i += 50) {
        const chunk = allIds.slice(i, i + 50);
        const objs = await multiGetObjects(client, chunk);
        allDaoObjs.push(...objs);
      }

      // 4. Filter to DAOs where the wallet is a member, then enrich with charter name
      const memberDaos: DaoEntry[] = [];

      for (const daoObj of allDaoObjs) {
        try {
          const dao = moveFields<DaoFields>(daoObj);
          const gov = dao.governance;
          const members =
            gov.variant === "Board"
              ? gov.fields.members.contents
              : gov.variant === "Direct"
                ? gov.fields.voters.contents.map((e) => e.key)
                : gov.variant === "Weighted"
                  ? gov.fields.delegates.contents.map((e) => e.key)
                  : [];
          console.log("[useWalletDaos] members:", members, "wallet:", address, "match:", members.includes(address));
          if (!isMemberOf(dao, address)) continue;

          const objectId = daoObj.data!.objectId;
          const isSubDAO = subDaoIds.includes(objectId) && !daoIds.includes(objectId);

          // Fetch charter for the DAO name
          let name = truncId(dao.charter_id);
          try {
            const charterObj = await client.getObject({
              id: dao.charter_id,
              options: { showContent: true },
            });
            const charter = moveFields<CharterFields>(charterObj);
            name = charter.name;
          } catch {
            // fall back to truncated charter ID
          }

          memberDaos.push({
            daoId: objectId,
            name,
            treasury: truncId(dao.treasury_id),
            memberCount: memberCount(dao),
            activeProposals: 0,
            isSubDAO,
            memberAddresses: members,
            capabilityVaultId: dao.capability_vault_id,
          });
        } catch (err) {
          console.error("[useWalletDaos] failed to process DAO object:", err, daoObj);
        }
      }

      return memberDaos;
    },
    enabled: !!address,
  });
}
