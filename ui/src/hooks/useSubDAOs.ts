import { useQuery } from "@tanstack/react-query";
import { useSuiClient } from "@mysten/dapp-kit";
import { cacheKeys } from "@/lib/cache-keys";
import {
  getObject,
  getDynamicFields,
  multiGetObjects,
  unwrapMoveStruct,
} from "@/lib/sui-rpc";
import type {
  DaoFields,
  CharterFields,
  SubDAONode,
  DAOHierarchy,
} from "@/types/dao";

function moveFields<T>(obj: { data?: { content?: unknown } | null }): T {
  const content = obj.data?.content as
    | { fields: unknown; dataType: "moveObject" }
    | undefined;
  if (!content || content.dataType !== "moveObject") {
    throw new Error("Object has no Move content");
  }
  return unwrapMoveStruct(content.fields) as T;
}

export function useSubDAOs(vaultId: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.subdaos(vaultId ?? ""),
    queryFn: async (): Promise<SubDAONode[]> => {
      if (!vaultId) return [];

      const fields = await getDynamicFields(client, vaultId);
      const subDaoControlFields = fields.filter((f) =>
        f.objectType.includes("SubDAOControl"),
      );

      if (subDaoControlFields.length === 0) return [];

      const controlObjectIds = subDaoControlFields.map((f) => f.objectId);
      const controlObjects = await multiGetObjects(client, controlObjectIds);

      const childDaoIds: string[] = [];
      for (const obj of controlObjects) {
        const controlFields = moveFields<{ id: { id: string }; subdao_id: string }>(obj);
        childDaoIds.push(controlFields.subdao_id);
      }

      if (childDaoIds.length === 0) return [];

      const childDaoObjects = await multiGetObjects(client, childDaoIds);
      const nodes: SubDAONode[] = [];

      for (const childObj of childDaoObjects) {
        try {
          const dao = moveFields<DaoFields>(childObj);
          const daoId = dao.id.id;

          const charterObj = await getObject(client, dao.charter_id);
          const charter = moveFields<CharterFields>(charterObj);

          const childVaultFields = await getDynamicFields(client, dao.capability_vault_id);
          const childSubDaoCount = childVaultFields.filter((f) =>
            f.objectType.includes("SubDAOControl"),
          ).length;

          const statusVariant =
            "variant" in dao.status ? dao.status.variant : "Active";

          nodes.push({
            daoId,
            name: charter.name,
            status: statusVariant as "Active" | "Migrating",
            controllerPaused: dao.controller_paused,
            executionPaused: dao.execution_paused,
            childCount: childSubDaoCount,
          });
        } catch {
          // Skip children that can't be read
        }
      }

      return nodes;
    },
    enabled: !!vaultId,
  });
}

export function useParentDAO(daoId: string) {
  const client = useSuiClient();

  return useQuery({
    queryKey: ["parentDao", daoId],
    queryFn: async (): Promise<{ parentId: string; parentName: string } | null> => {
      const daoObj = await getObject(client, daoId);
      const dao = moveFields<DaoFields>(daoObj);

      const controllerVec = dao.controller_cap_id?.vec;
      if (!controllerVec || controllerVec.length === 0) {
        return null;
      }

      const capId = controllerVec[0];
      const capObj = await getObject(client, capId, {
        showContent: true,
        showOwner: true,
        showType: true,
      });

      const owner = capObj.data?.owner;
      if (!owner || typeof owner !== "object") return null;

      let vaultId: string | undefined;
      if ("ObjectOwner" in owner) {
        vaultId = owner.ObjectOwner;
      } else if ("AddressOwner" in owner) {
        vaultId = owner.AddressOwner;
      }
      if (!vaultId) return null;

      try {
        const vaultObj = await getObject(client, vaultId);
        const vault = moveFields<{ id: { id: string }; dao_id: string }>(vaultObj);
        const parentId = vault.dao_id;

        const parentDaoObj = await getObject(client, parentId);
        const parentDao = moveFields<DaoFields>(parentDaoObj);
        const charterObj = await getObject(client, parentDao.charter_id);
        const charter = moveFields<CharterFields>(charterObj);

        return { parentId, parentName: charter.name };
      } catch {
        return null;
      }
    },
    enabled: !!daoId,
  });
}

export function useDAOHierarchy(daoId: string, vaultId: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: cacheKeys.hierarchy(daoId),
    queryFn: async (): Promise<DAOHierarchy> => {
      // Fetch the root DAO info
      const daoObj = await getObject(client, daoId);
      const dao = moveFields<DaoFields>(daoObj);
      const charterObj = await getObject(client, dao.charter_id);
      const charter = moveFields<CharterFields>(charterObj);

      const statusVariant =
        "variant" in dao.status ? dao.status.variant : "Active";

      // Get SubDAO children from vault
      const children: SubDAONode[] = [];
      if (vaultId) {
        const fields = await getDynamicFields(client, vaultId);
        const subDaoControlFields = fields.filter((f) =>
          f.objectType.includes("SubDAOControl"),
        );

        if (subDaoControlFields.length > 0) {
          const controlObjectIds = subDaoControlFields.map((f) => f.objectId);
          const controlObjects = await multiGetObjects(client, controlObjectIds);

          const childDaoIds: string[] = [];
          for (const obj of controlObjects) {
            const controlFields = moveFields<{ id: { id: string }; subdao_id: string }>(obj);
            childDaoIds.push(controlFields.subdao_id);
          }

          if (childDaoIds.length > 0) {
            const childDaoObjects = await multiGetObjects(client, childDaoIds);
            for (const childObj of childDaoObjects) {
              try {
                const childDao = moveFields<DaoFields>(childObj);
                const childCharterObj = await getObject(client, childDao.charter_id);
                const childCharter = moveFields<CharterFields>(childCharterObj);

                const childVaultFields = await getDynamicFields(
                  client,
                  childDao.capability_vault_id,
                );
                const childSubDaoCount = childVaultFields.filter((f) =>
                  f.objectType.includes("SubDAOControl"),
                ).length;

                const childStatus =
                  "variant" in childDao.status ? childDao.status.variant : "Active";

                children.push({
                  daoId: childDao.id.id,
                  name: childCharter.name,
                  status: childStatus as "Active" | "Migrating",
                  controllerPaused: childDao.controller_paused,
                  executionPaused: childDao.execution_paused,
                  childCount: childSubDaoCount,
                });
              } catch {
                // Skip unreadable children
              }
            }
          }
        }
      }

      // Determine parent
      let parentId: string | null = null;
      const controllerVec = dao.controller_cap_id?.vec;
      if (controllerVec && controllerVec.length > 0) {
        try {
          const capObj = await getObject(client, controllerVec[0], {
            showContent: true,
            showOwner: true,
            showType: true,
          });
          const owner = capObj.data?.owner;
          if (owner && typeof owner === "object") {
            let ownerVaultId: string | undefined;
            if ("ObjectOwner" in owner) {
              ownerVaultId = owner.ObjectOwner;
            } else if ("AddressOwner" in owner) {
              ownerVaultId = owner.AddressOwner;
            }
            if (ownerVaultId) {
              const vaultObj = await getObject(client, ownerVaultId);
              const vault = moveFields<{ id: { id: string }; dao_id: string }>(vaultObj);
              parentId = vault.dao_id;
            }
          }
        } catch {
          // Parent discovery failed; treat as root
        }
      }

      // Get root's own child count from vault fields
      let rootChildCount = children.length;

      return {
        root: {
          daoId,
          name: charter.name,
          status: statusVariant as "Active" | "Migrating",
          controllerPaused: dao.controller_paused,
          executionPaused: dao.execution_paused,
          childCount: rootChildCount,
        },
        children,
        parentId,
      };
    },
    enabled: !!daoId && !!vaultId,
  });
}
