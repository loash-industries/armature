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

/**
 * Recursively unwrap Sui JSON-RPC Move struct wrappers.
 *
 * The JSON-RPC API wraps every nested Move struct as `{ type: "...", fields: { ... } }`.
 * This function strips those wrappers so callers can access fields directly,
 * e.g. `dao.enabled_proposal_types.contents` instead of
 * `dao.enabled_proposal_types.fields.contents`.
 *
 * Enum variants (objects with a `variant` key) are preserved as-is since
 * `{ variant, fields }` is meaningful, but their `fields` value is still unwrapped.
 */
export function unwrapMoveStruct(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map(unwrapMoveStruct);
  if (typeof value !== "object") return value;

  const obj = value as Record<string, unknown>;

  // Move struct wrapper: has `type` (string) and `fields` (object), no `variant`
  if (
    typeof obj.type === "string" &&
    obj.fields != null &&
    typeof obj.fields === "object" &&
    !("variant" in obj)
  ) {
    return unwrapMoveStruct(obj.fields);
  }

  // Enum variant: has `variant` and `fields` — keep variant, unwrap fields
  if ("variant" in obj && obj.fields != null && typeof obj.fields === "object") {
    return {
      variant: obj.variant,
      fields: unwrapMoveStruct(obj.fields),
    };
  }

  // Regular object: recurse into each value
  const result: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    result[k] = unwrapMoveStruct(v);
  }
  return result;
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
