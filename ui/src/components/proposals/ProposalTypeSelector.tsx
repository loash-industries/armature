import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
} from "@/components/ui/command";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from "@/components/ui/tooltip";
import { PROPOSAL_TYPE_CATEGORIES } from "@/config/proposal-types";

interface ProposalTypeSelectorProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  enabledTypes: string[];
  frozenTypes: string[];
  onSelect: (typeKey: string) => void;
}

export function ProposalTypeSelector({
  open,
  onOpenChange,
  enabledTypes,
  frozenTypes,
  onSelect,
}: ProposalTypeSelectorProps) {
  const [search, setSearch] = useState("");

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg p-0">
        <DialogHeader className="px-4 pt-4">
          <DialogTitle>New Proposal</DialogTitle>
        </DialogHeader>
        <Command>
          <CommandInput
            placeholder="Search proposal types..."
            value={search}
            onValueChange={setSearch}
          />
          <CommandList className="max-h-80">
            <CommandEmpty>No matching proposal types.</CommandEmpty>
            {PROPOSAL_TYPE_CATEGORIES.map((category) => {
              const visibleTypes = category.types.filter((t) =>
                enabledTypes.includes(t.key),
              );
              const frozenInCategory = category.types.filter((t) =>
                frozenTypes.includes(t.key),
              );
              if (visibleTypes.length === 0 && frozenInCategory.length === 0)
                return null;

              return (
                <CommandGroup key={category.label} heading={category.label}>
                  {visibleTypes.map((t) => (
                    <CommandItem
                      key={t.key}
                      value={t.key}
                      onSelect={() => {
                        onSelect(t.key);
                        onOpenChange(false);
                      }}
                    >
                      <div className="flex flex-col gap-0.5">
                        <span className="font-mono text-sm">{t.label}</span>
                        <span className="text-muted-foreground text-xs">
                          {t.description}
                        </span>
                      </div>
                    </CommandItem>
                  ))}
                  {frozenInCategory.map((t) => (
                    <Tooltip key={t.key}>
                      <TooltipTrigger render={<CommandItem value={t.key} disabled className="opacity-50" />}>
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-sm">
                            {t.label}
                          </span>
                          <Badge variant="destructive" className="text-xs">
                            Frozen
                          </Badge>
                        </div>
                      </TooltipTrigger>
                      <TooltipContent>
                        This proposal type is currently frozen
                      </TooltipContent>
                    </Tooltip>
                  ))}
                </CommandGroup>
              );
            })}
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}
