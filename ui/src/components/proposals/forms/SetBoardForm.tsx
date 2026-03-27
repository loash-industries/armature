import { useState, useEffect } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import { Textarea } from "@/components/ui/textarea";
import { RecipientCombobox } from "@/components/ui/RecipientCombobox";
import { setBoardSchema } from "@/lib/schemas";
import { useGovernanceDetail } from "@/hooks/useDao";
import { useCharacterNames } from "@/hooks/useCharacterNames";
import { SubmitProposalButton } from "@/components/proposals/SubmitProposalButton";
import { BoardSizeImpact } from "@/components/proposals/BoardSizeImpact";
import type { SetBoardPayload } from "@/types/proposal";

interface SetBoardFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: SetBoardPayload) => void;
  onSubmitAndVote?: (data: SetBoardPayload) => void;
}

export function SetBoardForm({ daoId, isPending, onSubmit, onSubmitAndVote }: SetBoardFormProps) {
  const { data: govDetail } = useGovernanceDetail(daoId);
  const currentMembers = govDetail?.members.map((m) => m.address) ?? [];

  const form = useForm({
    resolver: zodResolver(setBoardSchema),
    defaultValues: {
      members: currentMembers.length > 0 ? currentMembers : [""],
      metadataIpfs: "",
    },
  });

  const { fields, append, remove } = useFieldArray({
    control: form.control,
    name: "members" as never,
  });

  useEffect(() => {
    if (currentMembers.length > 0) {
      form.reset({ members: currentMembers, metadataIpfs: "" });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [govDetail]);

  const [newAddr, setNewAddr] = useState("");

  const watchedMembers = form.watch("members") as string[];
  const added = watchedMembers.filter(
    (m) => m && !currentMembers.includes(m),
  );
  const removed = currentMembers.filter(
    (m) => !watchedMembers.includes(m),
  );

  const { data: nameMap } = useCharacterNames([...added, ...removed]);

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit((data) =>
          onSubmit(data as SetBoardPayload),
        )}
        className="space-y-4"
      >
        <div>
          <FormLabel>Board Members</FormLabel>
          <div className="mt-2 flex gap-2">
            <RecipientCombobox
              value={newAddr}
              onChange={setNewAddr}
            />
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => {
                if (newAddr) {
                  append(newAddr as never);
                  setNewAddr("");
                }
              }}
            >
              Add
            </Button>
          </div>
          <div className="mt-2 space-y-2">
            {fields.map((field, index) => (
              <div key={field.id} className="flex items-center gap-2">
                <FormField
                  control={form.control}
                  name={`members.${index}`}
                  render={({ field }) => (
                    <FormItem className="flex-1">
                      <FormControl>
                        <RecipientCombobox
                          value={field.value as string}
                          onChange={field.onChange}
                          onBlur={field.onBlur}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <Button
                  type="button"
                  variant="destructive"
                  size="sm"
                  onClick={() => remove(index)}
                >
                  Remove
                </Button>
              </div>
            ))}
          </div>
        </div>

        {(added.length > 0 || removed.length > 0) && (
          <div className="bg-muted/30 space-y-2 rounded p-3">
            <p className="text-sm font-medium">Board Changes Preview</p>
            {added.map((a) => (
              <div key={a} className="flex items-center gap-2">
                <Badge variant="default">+ Added</Badge>
                <span className="font-mono text-xs">{a}</span>
                {nameMap?.get(a) && (
                  <Badge variant="secondary" className="text-xs">
                    {nameMap.get(a)}
                  </Badge>
                )}
              </div>
            ))}
            {removed.map((r) => (
              <div key={r} className="flex items-center gap-2">
                <Badge variant="destructive">- Removed</Badge>
                <span className="font-mono text-xs">{r}</span>
                {nameMap?.get(r) && (
                  <Badge variant="secondary" className="text-xs">
                    {nameMap.get(r)}
                  </Badge>
                )}
              </div>
            ))}
          </div>
        )}

        {watchedMembers.filter(Boolean).length !== currentMembers.length && (
          <BoardSizeImpact
            daoId={daoId}
            currentSize={currentMembers.length}
            newSize={watchedMembers.filter(Boolean).length}
          />
        )}

        <FormField
          control={form.control}
          name="metadataIpfs"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Description (optional)</FormLabel>
              <FormControl>
                <Textarea placeholder="Describe this proposal..." {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <SubmitProposalButton
          isPending={isPending}
          onSubmit={() => form.handleSubmit((data) => onSubmit(data as SetBoardPayload))()}
          onSubmitAndVote={() => form.handleSubmit((data) => {
            if (onSubmitAndVote) onSubmitAndVote(data as SetBoardPayload);
            else onSubmit(data as SetBoardPayload);
          })()}
        />
      </form>
    </Form>
  );
}
