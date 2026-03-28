import { useCallback, useRef } from "react";
import { useForm, type FieldValues } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { PROPOSAL_SCHEMAS } from "@/lib/schemas";
import { TIER1_FIELD_DEFS, type FieldDef } from "./form-fields";
import { useProposalFormOptions } from "@/hooks/useProposalFormOptions";
import { SubmitProposalButton } from "./SubmitProposalButton";

interface GenericProposalFormProps {
  typeKey: string;
  daoId: string;
  isPending?: boolean;
  pendingStep?: "creating" | "voting" | null;
  onSubmit: (data: Record<string, unknown>) => void;
  onSubmitAndVote?: (data: Record<string, unknown>) => void;
}

export function GenericProposalForm({
  typeKey,
  daoId,
  isPending,
  pendingStep,
  onSubmit,
  onSubmitAndVote,
}: GenericProposalFormProps) {
  const schema = PROPOSAL_SCHEMAS[typeKey];
  const fieldDefs = TIER1_FIELD_DEFS[typeKey] ?? [];
  const options = useProposalFormOptions(daoId);
  const voteRef = useRef(false);

  const handleSubmit = useCallback(
    (data: FieldValues) => {
      const d = data as Record<string, unknown>;
      if (voteRef.current && onSubmitAndVote) {
        onSubmitAndVote(d);
      } else {
        onSubmit(d);
      }
      voteRef.current = false;
    },
    [onSubmit, onSubmitAndVote],
  );

  const form = useForm<FieldValues>({
    resolver: schema ? zodResolver(schema) : undefined,
    defaultValues: buildDefaults(fieldDefs),
  });

  const optionsMap: Record<string, string[]> = {
    enabledTypes: options.enabledTypes,
    frozenTypes: options.frozenTypes,
    disabledTypes: options.disabledTypes,
  };

  return (
    <Form {...form}>
      <form
        // eslint-disable-next-line react-hooks/refs
        onSubmit={form.handleSubmit(handleSubmit)}
        className="space-y-4"
      >
        {fieldDefs.map((field) => (
          <FieldRenderer
            key={field.name}
            field={field}
            form={form}
            optionsMap={optionsMap}
          />
        ))}

        <FormField
          control={form.control}
          name="metadataIpfs"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Description (optional)</FormLabel>
              <FormControl>
                <Textarea
                  placeholder="Describe this proposal..."
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <SubmitProposalButton
          isPending={isPending}
          pendingStep={pendingStep}
          actionType={typeKey}
          onSubmit={() => {
            voteRef.current = false;
            form.handleSubmit((data) => onSubmit(data as Record<string, unknown>))();
          }}
          onSubmitAndVote={() => {
            voteRef.current = true;
            form.handleSubmit((data) => {
              if (onSubmitAndVote) onSubmitAndVote(data as Record<string, unknown>);
              else onSubmit(data as Record<string, unknown>);
              voteRef.current = false;
            })();
          }}
        />
      </form>
    </Form>
  );
}

function FieldRenderer({
  field,
  form,
  optionsMap,
}: {
  field: FieldDef;
  form: ReturnType<typeof useForm<FieldValues>>;
  optionsMap: Record<string, string[]>;
}) {
  return (
    <FormField
      control={form.control}
      name={field.name}
      render={({ field: formField }) => (
        <FormItem>
          <FormLabel>{field.label}</FormLabel>
          <FormControl>
            {field.type === "select" ? (
              <Select
                value={formField.value as string}
                onValueChange={formField.onChange}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select..." />
                </SelectTrigger>
                <SelectContent>
                  {(optionsMap[field.optionsKey] ?? []).map((opt) => (
                    <SelectItem key={opt} value={opt}>
                      {opt}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : field.type === "number" || field.type === "duration" ? (
              <Input
                type="number"
                min={field.type === "number" ? field.min : undefined}
                placeholder={field.placeholder}
                value={String(formField.value ?? "")}
                name={formField.name}
                ref={formField.ref}
                onBlur={formField.onBlur}
                onChange={(e) =>
                  formField.onChange(
                    e.target.value ? Number(e.target.value) : "",
                  )
                }
              />
            ) : (
              <Input
                placeholder={
                  field.type === "address"
                    ? "0x..."
                    : (field.placeholder ?? "")
                }
                {...formField}
              />
            )}
          </FormControl>
          <FormMessage />
        </FormItem>
      )}
    />
  );
}

function buildDefaults(
  fieldDefs: FieldDef[],
): Record<string, string | number> {
  const defaults: Record<string, string | number> = { metadataIpfs: "" };
  for (const f of fieldDefs) {
    if (f.type === "number" || f.type === "duration") {
      defaults[f.name] = 0;
    } else {
      defaults[f.name] = "";
    }
  }
  return defaults;
}
