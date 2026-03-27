import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
} from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableRow,
  TableCell,
} from "@/components/ui/table";
import { PROPOSAL_TYPE_MAP } from "@/config/proposal-types";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { useCoinMetadataMap } from "@/hooks/useDao";
import { useMemo, type ReactNode } from "react";
import { AnimatedCoinBalance } from "@/components/ui/AnimatedCoinBalance";
import { AnimatedValue } from "@/components/ui/AnimatedValue";
import { AddressName } from "@/components/AddressName";

interface PayloadSummaryProps {
  typeKey: string;
  payload: Record<string, unknown>;
  /** Full Move type string, e.g. "…::SendCoin<0x2::sui::SUI>". Used to extract generic coin type. */
  payloadType?: string;
}

export function PayloadSummary({ typeKey, payload, payloadType }: PayloadSummaryProps) {
  const typeDef = PROPOSAL_TYPE_MAP[typeKey];

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">
          {typeDef?.label ?? typeKey} — Payload
        </CardTitle>
      </CardHeader>
      <CardContent>
        <PayloadRenderer typeKey={typeKey} payload={payload} payloadType={payloadType} />
      </CardContent>
    </Card>
  );
}

/** Extract the generic type parameter from a Move type string, e.g. "::SendCoin<0x2::sui::SUI>" → "0x2::sui::SUI". */
function extractCoinType(payloadType: string | undefined): string | undefined {
  if (!payloadType) return undefined;
  const start = payloadType.indexOf("<");
  const end = payloadType.lastIndexOf(">");
  if (start === -1 || end === -1) return undefined;
  return payloadType.slice(start + 1, end);
}

function PayloadRenderer({
  typeKey,
  payload,
  payloadType,
}: {
  typeKey: string;
  payload: Record<string, unknown>;
  payloadType?: string;
}) {
  switch (typeKey) {
    case "SetBoard":
      return <SetBoardSummary payload={payload} />;
    case "TreasuryWithdraw":
      return <CoinProposalSummary payload={payload} payloadType={payloadType} recipientLabel="Recipient" recipientField="recipient" />;
    case "CharterUpdate":
      return <CharterUpdateSummary payload={payload} />;
    case "EnableProposalType":
    case "UpdateProposalConfig":
      return <ProposalConfigSummary payload={payload} />;
    case "CreateSubDAO":
      return <CreateSubDAOSummary payload={payload} />;
    case "DisableProposalType":
    case "UnfreezeProposalType":
      return <TypeKeySummary payload={payload} />;
    case "TransferFreezeAdmin":
      return <TransferFreezeAdminSummary payload={payload} />;
    case "SendCoinToDAO":
      return <CoinProposalSummary payload={payload} payloadType={payloadType} recipientLabel="Recipient Treasury" recipientField="recipient_treasury" />;
    case "SendSmallPayment":
      return <CoinProposalSummary payload={payload} payloadType={payloadType} recipientLabel="Recipient" recipientField="recipient" />;
    case "SpinOutSubDAO":
      return <ObjectIdSummary label="SubDAO" payload={payload} field="subdao_id" />;
    case "SpawnDAO":
      return <SpawnDAOSummary payload={payload} />;
    case "UpdateFreezeConfig":
      return <UpdateFreezeConfigSummary payload={payload} />;
    case "UpdateFreezeExemptTypes":
      return <UpdateFreezeExemptTypesSummary payload={payload} />;
    case "TransferCapToSubDAO":
      return <TransferCapSummary payload={payload} />;
    case "ReclaimCapFromSubDAO":
      return <ReclaimCapSummary payload={payload} />;
    case "ProposeUpgrade":
      return <ProposeUpgradeSummary payload={payload} />;
    case "PauseSubDAOExecution":
    case "UnpauseSubDAOExecution":
      return <ObjectIdSummary label="Control ID" payload={payload} field="control_id" />;
    case "TransferAssets":
      return <TransferAssetsSummary payload={payload} />;
    default:
      return <GenericSummary payload={payload} />;
  }
}

function SetBoardSummary({ payload }: { payload: Record<string, unknown> }) {
  const members = (payload.new_members as string[] ?? payload.members as string[]) ?? [];
  const { data: nameMap } = useCharacterNames(members);
  return (
    <div className="space-y-2">
      <p className="text-sm">
        <span className="text-muted-foreground">New board:</span>{" "}
        {members.length} member(s)
      </p>
      <div className="space-y-1">
        {members.map((m, i) => (
          <div key={i} className="flex items-center gap-2">
            <AddressName address={m} charName={nameMap?.get(m)} />
          </div>
        ))}
      </div>
    </div>
  );
}

/** Shorten "0xABCDEF0123456789…::module::TYPE" → "0xABCD…6789::module::TYPE" */
function truncateCoinType(coinType: string): string {
  const parts = coinType.split("::");
  if (parts.length < 3) return coinType;
  const pkg = parts[0];
  const rest = parts.slice(1).join("::");
  if (pkg.length > 12) {
    return `${pkg.slice(0, 6)}…${pkg.slice(-4)}::${rest}`;
  }
  return coinType;
}

/** Coin-aware summary used by TreasuryWithdraw, SendCoinToDAO, and SendSmallPayment.
 *  Extracts the coin type from the generic payloadType, fetches on-chain metadata,
 *  and formats the raw amount with the correct decimals and symbol. */
function CoinProposalSummary({
  payload,
  payloadType,
  recipientLabel,
  recipientField,
}: {
  payload: Record<string, unknown>;
  payloadType?: string;
  recipientLabel: string;
  recipientField: string;
}) {
  const coinType = extractCoinType(payloadType);
  const coinTypes = useMemo(() => (coinType ? [coinType] : []), [coinType]);
  const { data: metadataMap } = useCoinMetadataMap(coinTypes);

  const meta = coinType ? metadataMap?.[coinType] : undefined;
  const decimals = meta?.decimals ?? 9;
  const symbol = meta?.symbol ?? (coinType ? coinType.split("::").pop() ?? "" : "");

  const rawAmount = String(payload.amount ?? "0");
  let formattedAmount: ReactNode;
  try {
    const amt = BigInt(rawAmount);
    formattedAmount = (
      <AnimatedCoinBalance balance={amt} decimals={decimals} symbol={symbol} />
    );
  } catch {
    formattedAmount = rawAmount;
  }

  const recipient = String(payload[recipientField] ?? "");
  const recipientAddrs = useMemo(() => (recipient ? [recipient] : []), [recipient]);
  const { data: recipientNameMap } = useCharacterNames(recipientAddrs);

  const coinDisplay = coinType ? (
    <span className="flex items-center gap-1.5" title={coinType}>
      <Badge variant="secondary" className="font-mono text-xs">{symbol}</Badge>
      <span className="font-mono text-xs text-muted-foreground">{truncateCoinType(coinType)}</span>
    </span>
  ) : "—";

  return (
    <Table>
      <TableBody>
        <KVRow label={recipientLabel} value={recipient ? <AddressName address={recipient} charName={recipientNameMap?.get(recipient)} /> : "—"} />
        <KVRow label="Amount" value={formattedAmount} />
        <KVRow label="Coin" value={coinDisplay} />
      </TableBody>
    </Table>
  );
}

function CharterUpdateSummary({
  payload,
}: {
  payload: Record<string, unknown>;
}) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Name" value={String(payload.name ?? "")} />
        <KVRow
          label="Description"
          value={
            String(payload.description ?? "").slice(0, 100) +
            (String(payload.description ?? "").length > 100 ? "..." : "")
          }
        />
        <KVRow label="Image URL" value={String(payload.imageUrl ?? "")} />
      </TableBody>
    </Table>
  );
}

/** Extract a value from a Sui Option variant ({ variant: "Some", fields: T }). */
function unwrapOption(val: unknown): unknown {
  if (val != null && typeof val === "object" && "variant" in (val as Record<string, unknown>)) {
    const opt = val as { variant: string; fields: unknown };
    return opt.variant === "Some" ? opt.fields : undefined;
  }
  return val;
}

function ProposalConfigSummary({
  payload,
}: {
  payload: Record<string, unknown>;
}) {
  // EnableProposalType: { type_key, config: { quorum, approval_threshold, ... } }
  // UpdateProposalConfig: { target_type_key, quorum: Option, approval_threshold: Option, ... }
  const typeKey = String(payload.type_key ?? payload.target_type_key ?? "");
  const nested = payload.config as Record<string, unknown> | undefined;

  const quorum = Number(nested ? nested.quorum : unwrapOption(payload.quorum) ?? 0);
  const approvalThreshold = Number(nested ? nested.approval_threshold : unwrapOption(payload.approval_threshold) ?? 0);
  const proposeThreshold = Number(nested ? nested.propose_threshold : unwrapOption(payload.propose_threshold) ?? 0);
  const expiryMs = Number(nested ? nested.expiry_ms : unwrapOption(payload.expiry_ms) ?? 0);
  const executionDelayMs = Number(nested ? nested.execution_delay_ms : unwrapOption(payload.execution_delay_ms) ?? 0);
  const cooldownMs = Number(nested ? nested.cooldown_ms : unwrapOption(payload.cooldown_ms) ?? 0);

  return (
    <div className="space-y-2">
      <p className="text-sm">
        <span className="text-muted-foreground">Type:</span>{" "}
        <Badge variant="outline">{typeKey}</Badge>
      </p>
      <Table>
        <TableBody>
          <KVRow
            label="Quorum"
            value={<AnimatedValue value={quorum / 100} suffix="%" />}
          />
          <KVRow
            label="Approval"
            value={<AnimatedValue value={approvalThreshold / 100} suffix="%" />}
          />
          <KVRow
            label="Propose Threshold"
            value={<AnimatedValue value={proposeThreshold} />}
          />
          <KVRow label="Voting Period" value={formatDuration(expiryMs)} />
          <KVRow label="Exec Delay" value={formatDuration(executionDelayMs)} />
          <KVRow label="Cooldown" value={formatDuration(cooldownMs)} />
        </TableBody>
      </Table>
    </div>
  );
}

function formatDuration(ms: number): string {
  if (ms === 0) return "0";
  const hours = ms / 3_600_000;
  if (hours >= 24) {
    const days = Math.floor(hours / 24);
    const rem = Math.round(hours % 24);
    return rem > 0 ? `${days}d ${rem}h` : `${days}d`;
  }
  if (hours >= 1) return `${hours.toFixed(1)}h`;
  return `${ms}ms`;
}

function CreateSubDAOSummary({
  payload,
}: {
  payload: Record<string, unknown>;
}) {
  const types = (payload.proposalTypes as Array<{ typeKey: string }>) ?? [];
  return (
    <div className="space-y-2">
      <Table>
        <TableBody>
          <KVRow label="Name" value={String(payload.name ?? "")} />
          <KVRow
            label="Board"
            value={`${((payload.board as string[]) ?? []).length} member(s)`}
          />
          <KVRow label="Charter" value={String(payload.charterName ?? "")} />
          <KVRow label="Funding" value={`${payload.fundingAmount ?? 0} MIST`} />
        </TableBody>
      </Table>
      <div className="flex flex-wrap gap-1">
        {types.map((t) => (
          <Badge key={t.typeKey} variant="outline">
            {t.typeKey}
          </Badge>
        ))}
      </div>
    </div>
  );
}

function TypeKeySummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Type Key" value={String(payload.type_key ?? "")} />
      </TableBody>
    </Table>
  );
}

function TransferFreezeAdminSummary({
  payload,
}: {
  payload: Record<string, unknown>;
}) {
  const newAdmin = String(payload.new_admin ?? "");
  const addrs = useMemo(() => (newAdmin ? [newAdmin] : []), [newAdmin]);
  const { data: nameMap } = useCharacterNames(addrs);
  return (
    <Table>
      <TableBody>
        <KVRow label="New Admin" value={newAdmin ? <AddressName address={newAdmin} charName={nameMap?.get(newAdmin)} /> : "—"} />
      </TableBody>
    </Table>
  );
}



function ObjectIdSummary({ label, payload, field }: { label: string; payload: Record<string, unknown>; field: string }) {
  return (
    <Table>
      <TableBody>
        <KVRow label={label} value={String(payload[field] ?? "")} mono />
      </TableBody>
    </Table>
  );
}

function SpawnDAOSummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Name" value={String(payload.name ?? "")} />
        <KVRow label="Description" value={String(payload.description ?? "")} />
      </TableBody>
    </Table>
  );
}

function UpdateFreezeConfigSummary({ payload }: { payload: Record<string, unknown> }) {
  const ms = Number(payload.new_max_freeze_duration_ms ?? 0);
  const hours = Math.floor(ms / 3_600_000);
  return (
    <Table>
      <TableBody>
        <KVRow label="New Max Duration" value={hours > 0 ? `${hours}h (${ms}ms)` : `${ms}ms`} />
      </TableBody>
    </Table>
  );
}

function UpdateFreezeExemptTypesSummary({ payload }: { payload: Record<string, unknown> }) {
  const toAdd = payload.types_to_add;
  const toRemove = payload.types_to_remove;
  return (
    <Table>
      <TableBody>
        <KVRow label="Types to Add" value={Array.isArray(toAdd) ? toAdd.join(", ") : String(toAdd ?? "")} />
        <KVRow label="Types to Remove" value={Array.isArray(toRemove) ? toRemove.join(", ") : String(toRemove ?? "")} />
      </TableBody>
    </Table>
  );
}

function TransferCapSummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Capability ID" value={String(payload.cap_id ?? "")} mono />
        <KVRow label="Target SubDAO" value={String(payload.target_subdao ?? "")} mono />
      </TableBody>
    </Table>
  );
}

function ReclaimCapSummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="SubDAO" value={String(payload.subdao_id ?? "")} mono />
        <KVRow label="Capability ID" value={String(payload.cap_id ?? "")} mono />
        <KVRow label="Control ID" value={String(payload.control_id ?? "")} mono />
      </TableBody>
    </Table>
  );
}

function ProposeUpgradeSummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Package" value={String(payload.package_id ?? "")} mono />
        <KVRow label="UpgradeCap" value={String(payload.cap_id ?? "")} mono />
        <KVRow label="Digest" value={String(payload.digest ?? "")} mono />
        <KVRow label="Policy" value={String(payload.policy ?? "")} />
      </TableBody>
    </Table>
  );
}

function TransferAssetsSummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Target DAO" value={String(payload.target_dao_id ?? "")} mono />
        <KVRow label="Target Treasury" value={String(payload.target_treasury_id ?? "")} mono />
        <KVRow label="Target Vault" value={String(payload.target_vault_id ?? "")} mono />
        <KVRow label="Coin Types" value={Array.isArray(payload.coin_types) ? payload.coin_types.join(", ") : String(payload.coin_types ?? "")} />
        <KVRow label="Capability IDs" value={Array.isArray(payload.cap_ids) ? payload.cap_ids.join(", ") : String(payload.cap_ids ?? "")} />
      </TableBody>
    </Table>
  );
}

/** Map on-chain snake_case field names to readable labels. */
const FIELD_LABELS: Record<string, string> = {
  type_key: "Type Key",
  new_admin: "New Admin",
  new_members: "New Members",
  recipient: "Recipient",
  amount: "Amount",
  recipient_treasury: "Recipient Treasury",
  cap_id: "Capability ID",
  target_subdao: "Target SubDAO",
  subdao_id: "SubDAO ID",
  control_id: "Control ID",
  package_id: "Package ID",
  digest: "Digest",
  policy: "Policy",
  new_max_freeze_duration_ms: "Max Freeze Duration (ms)",
  types_to_add: "Types to Add",
  types_to_remove: "Types to Remove",
  coin_type: "Coin Type",
};

const SUI_ADDRESS_RE = /^0x[a-fA-F0-9]{64}$/;

function GenericSummary({ payload }: { payload: Record<string, unknown> }) {
  const entries = Object.entries(payload).filter(
    ([k]) => k !== "metadataIpfs",
  );
  const addressValues = useMemo(
    () => entries
      .map(([, v]) => String(v ?? ""))
      .filter((v) => SUI_ADDRESS_RE.test(v)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [JSON.stringify(payload)],
  );
  const { data: nameMap } = useCharacterNames(addressValues);

  if (entries.length === 0) {
    return <p className="text-muted-foreground text-sm">No payload data.</p>;
  }
  return (
    <Table>
      <TableBody>
        {entries.map(([key, value]) => {
          const strVal = typeof value === "object" ? JSON.stringify(value) : String(value ?? "");
          const isAddress = SUI_ADDRESS_RE.test(strVal);
          return (
            <KVRow
              key={key}
              label={FIELD_LABELS[key] ?? key}
              value={isAddress ? <AddressName address={strVal} charName={nameMap?.get(strVal)} /> : strVal}
            />
          );
        })}
      </TableBody>
    </Table>
  );
}

function KVRow({
  label,
  value,
  mono,
}: {
  label: string;
  value: ReactNode;
  mono?: boolean;
}) {
  const isEmpty = value === "" || value === null || value === undefined;
  return (
    <TableRow>
      <TableCell className="text-muted-foreground text-sm">{label}</TableCell>
      <TableCell
        className={`text-sm ${mono ? "font-mono" : ""}`}
      >
        {isEmpty ? "—" : value}
      </TableCell>
    </TableRow>
  );
}
