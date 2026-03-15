import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
  Badge,
  Table,
  TableBody,
  TableRow,
  TableCell,
} from "@awar.dev/ui";
import { PROPOSAL_TYPE_MAP } from "@/config/proposal-types";

interface PayloadSummaryProps {
  typeKey: string;
  payload: Record<string, unknown>;
}

export function PayloadSummary({ typeKey, payload }: PayloadSummaryProps) {
  const typeDef = PROPOSAL_TYPE_MAP[typeKey];

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">
          {typeDef?.label ?? typeKey} — Payload
        </CardTitle>
      </CardHeader>
      <CardContent>
        <PayloadRenderer typeKey={typeKey} payload={payload} />
      </CardContent>
    </Card>
  );
}

function PayloadRenderer({
  typeKey,
  payload,
}: {
  typeKey: string;
  payload: Record<string, unknown>;
}) {
  switch (typeKey) {
    case "SetBoard":
      return <SetBoardSummary payload={payload} />;
    case "TreasuryWithdraw":
      return <TreasuryWithdrawSummary payload={payload} />;
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
    case "SendSmallPayment":
      return <CoinTransferSummary payload={payload} />;
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
  return (
    <div className="space-y-2">
      <p className="text-sm">
        <span className="text-muted-foreground">New board:</span>{" "}
        {members.length} member(s)
      </p>
      <div className="space-y-1">
        {members.map((m, i) => (
          <div key={i} className="font-mono text-xs">
            {m}
          </div>
        ))}
      </div>
    </div>
  );
}

function TreasuryWithdrawSummary({
  payload,
}: {
  payload: Record<string, unknown>;
}) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Coin Type" value={String(payload.coinType ?? "")} />
        <KVRow label="Amount" value={String(payload.amount ?? "")} />
        <KVRow label="Recipient" value={String(payload.recipient ?? "")} mono />
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

function ProposalConfigSummary({
  payload,
}: {
  payload: Record<string, unknown>;
}) {
  const config = payload.config as Record<string, number> | undefined;
  return (
    <div className="space-y-2">
      <p className="text-sm">
        <span className="text-muted-foreground">Type:</span>{" "}
        <Badge variant="outline">{String(payload.typeKey ?? "")}</Badge>
      </p>
      {config && (
        <Table>
          <TableBody>
            <KVRow
              label="Quorum"
              value={`${(config.quorum / 100).toFixed(1)}%`}
            />
            <KVRow
              label="Approval"
              value={`${(config.approvalThreshold / 100).toFixed(1)}%`}
            />
            <KVRow label="Voting Period" value={`${config.expiryMs}ms`} />
            <KVRow label="Exec Delay" value={`${config.executionDelayMs}ms`} />
            <KVRow label="Cooldown" value={`${config.cooldownMs}ms`} />
          </TableBody>
        </Table>
      )}
    </div>
  );
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
  return (
    <Table>
      <TableBody>
        <KVRow label="New Admin" value={String(payload.new_admin ?? "")} mono />
      </TableBody>
    </Table>
  );
}

function CoinTransferSummary({ payload }: { payload: Record<string, unknown> }) {
  return (
    <Table>
      <TableBody>
        <KVRow label="Recipient" value={String(payload.recipient ?? payload.recipient_treasury ?? "")} mono />
        <KVRow label="Amount" value={String(payload.amount ?? "")} />
        <KVRow label="Coin Type" value={String(payload.coin_type ?? "")} mono />
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

function GenericSummary({ payload }: { payload: Record<string, unknown> }) {
  const entries = Object.entries(payload).filter(
    ([k]) => k !== "metadataIpfs",
  );
  if (entries.length === 0) {
    return <p className="text-muted-foreground text-sm">No payload data.</p>;
  }
  return (
    <Table>
      <TableBody>
        {entries.map(([key, value]) => (
          <KVRow
            key={key}
            label={FIELD_LABELS[key] ?? key}
            value={typeof value === "object" ? JSON.stringify(value) : String(value ?? "")}
          />
        ))}
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
  value: string;
  mono?: boolean;
}) {
  return (
    <TableRow>
      <TableCell className="text-muted-foreground text-sm">{label}</TableCell>
      <TableCell
        className={`text-sm ${mono ? "font-mono" : ""}`}
      >
        {value || "—"}
      </TableCell>
    </TableRow>
  );
}
