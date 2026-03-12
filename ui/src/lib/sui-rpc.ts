import type {
  SuiObjectResponse,
  SuiObjectDataOptions,
  DynamicFieldInfo,
  SuiEvent,
} from "@mysten/sui/jsonRpc";
import type { SuiJsonRpcClient } from "@mysten/sui/jsonRpc";

const DEFAULT_OBJECT_OPTIONS: SuiObjectDataOptions = {
  showContent: true,
  showType: true,
  showOwner: true,
};

export async function getObject(
  client: SuiJsonRpcClient,
  id: string,
  options: SuiObjectDataOptions = DEFAULT_OBJECT_OPTIONS,
): Promise<SuiObjectResponse> {
  return client.getObject({ id, options });
}

export async function multiGetObjects(
  client: SuiJsonRpcClient,
  ids: string[],
  options: SuiObjectDataOptions = DEFAULT_OBJECT_OPTIONS,
): Promise<SuiObjectResponse[]> {
  return client.multiGetObjects({ ids, options });
}

export async function getDynamicFields(
  client: SuiJsonRpcClient,
  parentId: string,
): Promise<DynamicFieldInfo[]> {
  const fields: DynamicFieldInfo[] = [];
  let cursor: string | null = null;
  let hasNext = true;

  while (hasNext) {
    const page = await client.getDynamicFields({
      parentId,
      cursor: cursor ?? undefined,
      limit: 50,
    });
    fields.push(...page.data);
    cursor = page.nextCursor ?? null;
    hasNext = page.hasNextPage;
  }

  return fields;
}

export async function getDynamicFieldObject(
  client: SuiJsonRpcClient,
  parentId: string,
  name: { type: string; value: string },
): Promise<SuiObjectResponse> {
  return client.getDynamicFieldObject({ parentId, name });
}

export async function queryEvents(
  client: SuiJsonRpcClient,
  filter: { MoveModule: { package: string; module: string } },
  cursor?: string,
  limit: number = 50,
): Promise<{
  data: SuiEvent[];
  nextCursor: string | null;
  hasNextPage: boolean;
}> {
  const result = await client.queryEvents({
    query: filter,
    cursor: cursor ? { txDigest: cursor, eventSeq: "0" } : undefined,
    limit,
    order: "descending",
  });
  return {
    data: result.data,
    nextCursor: result.nextCursor?.txDigest ?? null,
    hasNextPage: result.hasNextPage,
  };
}

export async function getOwnedObjects(
  client: SuiJsonRpcClient,
  owner: string,
  filter?: { StructType: string },
): Promise<SuiObjectResponse[]> {
  const objects: SuiObjectResponse[] = [];
  let cursor: string | null = null;
  let hasNext = true;

  while (hasNext) {
    const page = await client.getOwnedObjects({
      owner,
      filter,
      options: DEFAULT_OBJECT_OPTIONS,
      cursor: cursor ?? undefined,
      limit: 50,
    });
    objects.push(...page.data);
    cursor = page.nextCursor ?? null;
    hasNext = page.hasNextPage;
  }

  return objects;
}
