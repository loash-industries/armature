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
    default:
      return <GenericSummary payload={payload} />;
  }
}

function SetBoardSummary({ payload }: { payload: Record<string, unknown> }) {
  const members = (payload.members as string[]) ?? [];
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
            label={key}
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
