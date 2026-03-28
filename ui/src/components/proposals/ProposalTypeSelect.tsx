import {
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { PROPOSAL_TYPE_DISPLAY_NAME } from "@/config/proposal-types";
import type { Control, FieldValues, FieldPath } from "react-hook-form";

function displayName(typeKey: string): string {
  return (
    PROPOSAL_TYPE_DISPLAY_NAME[
      typeKey as keyof typeof PROPOSAL_TYPE_DISPLAY_NAME
    ] ?? typeKey
  );
}

interface ProposalTypeSelectProps<T extends FieldValues = FieldValues> {
  control: Control<T>;
  name?: FieldPath<T>;
  label?: string;
  types: string[];
  placeholder?: string;
}

export function ProposalTypeSelect<T extends FieldValues = FieldValues>({
  control,
  name = "typeKey" as FieldPath<T>,
  label = "Proposal Type",
  types,
  placeholder = "Select type...",
}: ProposalTypeSelectProps<T>) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem>
          <FormLabel>{label}</FormLabel>
          <FormControl>
            <Select value={field.value} onValueChange={field.onChange}>
              <SelectTrigger>
                <SelectValue placeholder={placeholder}>
                  {field.value ? displayName(field.value) : undefined}
                </SelectValue>
              </SelectTrigger>
              <SelectContent alignItemWithTrigger={false} align="start" className="w-auto min-w-(--anchor-width)">
                {types.map((t) => (
                  <SelectItem key={t} value={t}>
                    {displayName(t)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormControl>
          <FormMessage />
        </FormItem>
      )}
    />
  );
}
