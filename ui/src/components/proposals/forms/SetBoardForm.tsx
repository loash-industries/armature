import { useState, useEffect } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
  Input,
  Textarea,
  Button,
  Badge,
} from "@awar.dev/ui";
import { setBoardSchema } from "@/lib/schemas";
import { useGovernanceDetail } from "@/hooks/useDao";
import type { SetBoardPayload } from "@/types/proposal";

interface SetBoardFormProps {
  daoId: string;
  isPending?: boolean;
  onSubmit: (data: SetBoardPayload) => void;
}

export function SetBoardForm({ daoId, isPending, onSubmit }: SetBoardFormProps) {
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
  }, [govDetail]);

  const [newAddr, setNewAddr] = useState("");

  const watchedMembers = form.watch("members") as string[];
  const added = watchedMembers.filter(
    (m) => m && !currentMembers.includes(m),
  );
  const removed = currentMembers.filter(
    (m) => !watchedMembers.includes(m),
  );

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
            <Input
              placeholder="Add address 0x..."
              value={newAddr}
              onChange={(e) => setNewAddr(e.target.value)}
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
                        <Input placeholder="0x..." {...field} />
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
              </div>
            ))}
            {removed.map((r) => (
              <div key={r} className="flex items-center gap-2">
                <Badge variant="destructive">- Removed</Badge>
                <span className="font-mono text-xs">{r}</span>
              </div>
            ))}
          </div>
        )}

        <FormField
          control={form.control}
          name="metadataIpfs"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Proposal Description</FormLabel>
              <FormControl>
                <Textarea placeholder="Describe this proposal..." {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <Button type="submit" disabled={isPending}>
          {isPending ? "Submitting..." : "Create Proposal"}
        </Button>
      </form>
    </Form>
  );
}
