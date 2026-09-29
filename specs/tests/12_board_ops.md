# Board Operations Tests

## Summary

Board membership changes through five framework types, all seeded on every OU with fixed permission bits and no approval floor:

| Type | Handler | Bit | Event |
|------|---------|-----|-------|
| `SetBoard { to_add, to_remove }` | `board_ops::execute_set_board(ou, ticket)` | `BOARD_SET` | `BoardUpdated { ou_id, added, removed }` |
| `AddMember { member }` | `member_ops::execute_add_member(ou, ticket)` | `BOARD_ADD` | `MemberAdded` |
| `RemoveMember { member }` | `member_ops::execute_remove_member(ou, ticket)` | `BOARD_REMOVE` | `MemberRemoved` |
| `BatchAddMembers { members }` | `member_ops::execute_batch_add_members(ou, ticket)` | `BOARD_ADD` | `MembersBatchAdded { ou_id, added, skipped }` |
| `BatchRemoveMembers { members }` | `member_ops::execute_batch_remove_members(ou, ticket)` | `BOARD_REMOVE` | `MembersBatchRemoved { ou_id, removed }` |

`SetBoard` applies a **diff**, not a full-slate replacement: the roster is a `Table<address, Member>`, which cannot be enumerated on-chain. Replacing the whole board means listing every current member in `to_remove` and the new ones in `to_add`. `governance::set_board` validates everything before mutating, in this order:

1. Both lists empty → `governance::ENoBoardChange`
2. An address appears twice across `to_add` and `to_remove` → `governance::EDuplicateBoardMember`
3. An address in `to_add` is already a member → `governance::EDuplicateBoardMember`
4. An address in `to_remove` is not a member → `governance::ENotBoardMember`
5. The result would be empty → `governance::EEmptyBoard`

Each change advances `roster_version` once (a batch counts once; a batch add that adds nobody does not advance it) and updates `member_count`. Removed members keep a closed tenure; re-adding opens a new one. Any removal rotates the OU's `encrypt_epoch` (Seal-encrypted entries). The handlers check the ticket's OU (`board_ops::EOuMismatch`, `member_ops::EOuMismatch`), and the `ou` mutators check the bit (`proposal::EPermissionDenied`).

Effects on governance rights, all immediate:

- A removed member can no longer submit (`governance::ENotBoardMember`) or execute (`proposal::ENotEligible`), but can still vote on proposals created while they were a member (eligibility is `was_member_at(snapshot_version)`).
- An added member can submit at once, but cannot vote on proposals created before they joined (`proposal::ENotInSnapshot`).

Default configs: quorum 5000, threshold 5000, delay 0; `SetBoard`, `AddMember` and `RemoveMember` are composable, the batch types are not. With delay 0 these types can take the atomic single-vote path; `09_board_voting.md` recommends a non-zero delay for them. A controller changes a SubOU's board with `ControllerBatchAddMembers` / `ControllerBatchRemoveMembers` (`13_subou_ops.md`).

Real suites: `packages/armature_proposals/tests/board_ops_tests.move` (6) and `member_ops_tests.move` (15), plus tests cited from `encrypted_entry_tests.move`, `gate_tests.move`, `proposal_tests.move`, `composite_tests.move` and `lifecycle_tests.move`.

## Test Matrix

| Type | Test | Expected |
|------|------|----------|
| SetBoard | `test_set_board_e2e` | [A, B] + add C: C is a member, A and B remain |
| SetBoard | `test_full_board_replacement` | [A, B] → [C, D, E] in one change |
| SetBoard | `test_shrink_board_to_single_member` | [A, B, C] → [A] |
| SetBoard | `test_grow_board_from_single` | [A] → [A, B, C, D, E] |
| SetBoard | `test_sequential_board_changes` | [A, B] → [A, C] → [C, D] |
| SetBoard | `test_set_board_empty_members_aborts` | Remove every member: Abort `governance::EEmptyBoard` |
| SetBoard | `encrypted_entry_tests::test_setboard_empty_change_aborts` | Both lists empty: Abort `governance::ENoBoardChange` |
| SetBoard | `encrypted_entry_tests::test_setboard_member_removal_auto_rotates_epoch` | A removal bumps `encrypt_epoch` |
| SetBoard | `encrypted_entry_tests::test_setboard_member_addition_does_not_rotate_epoch` | Additions only: `encrypt_epoch` unchanged |
| SetBoard | `encrypted_entry_tests::test_setboard_full_replacement_rotates_epoch` | Add and remove in one change: epoch bumped |
| SetBoard | `gate_tests::set_board_governance_needs_board_set` | Request with every bit but BOARD_SET: Abort `proposal::EPermissionDenied` |
| SetBoard | `composite_tests::composite_set_board_step_e2e` | SetBoard runs as a composite step |
| SetBoard | `ou_tests::test_board_governance_persists_across_proposals` | Governance is still Board after a set_board change |
| SetBoard | `lifecycle_tests::small_startup_lifecycle` | After [A, B, C] → [A, B, D, E], D proposes and D + E pass a payment |
| SetBoard | `test_set_board__add_existing_member_aborts` (planned) | Abort `governance::EDuplicateBoardMember` |
| SetBoard | `test_set_board__remove_non_member_aborts` (planned) | Abort `governance::ENotBoardMember` |
| SetBoard | `test_set_board__address_in_both_lists_aborts` (planned) | Abort `governance::EDuplicateBoardMember` |
| SetBoard | `test_set_board__removed_member_cannot_propose_aborts` (planned) | Removed member calls `submit_proposal`: Abort `governance::ENotBoardMember` |
| SetBoard | `test_set_board__updates_member_count_and_roster_version` (planned) | `member_count` = new size; `roster_version` + 1 |
| SetBoard | `test_set_board__emits_board_updated` (planned) | `BoardUpdated { ou_id, added: to_add, removed: to_remove }` |
| AddMember | `test_add_member_e2e` | Member added |
| AddMember | `test_add_member_duplicate_aborts` | Already a member: Abort `governance::EDuplicateBoardMember` |
| RemoveMember | `test_remove_member_e2e` | Member removed |
| RemoveMember | `test_remove_nonmember_aborts` | Abort `governance::ENotBoardMember` |
| RemoveMember | `test_remove_last_member_aborts` | Abort `governance::EEmptyBoard` |
| BatchAddMembers | `test_batch_add_members_e2e` | All listed members added |
| BatchAddMembers | `test_batch_add_members_existing_member_skipped` | Batch [new, existing]: no abort; the new address is added (the existing one goes to `MembersBatchAdded.skipped`) |
| BatchAddMembers | `test_batch_add_members_internal_duplicate_aborts` | Same address twice in the batch: Abort `governance::EDuplicateBoardMember` |
| BatchAddMembers | `test_batch_add_members_empty_aborts` | Abort `member_ops::EEmptyBatch` |
| BatchAddMembers | `test_batch_add_members_oversize_aborts` | 101 addresses: Abort `member_ops::EBatchTooLarge` |
| BatchRemoveMembers | `test_batch_remove_members_e2e` | All listed members removed |
| BatchRemoveMembers | `test_batch_remove_members_nonmember_aborts` | Abort `governance::ENotBoardMember` |
| BatchRemoveMembers | `test_batch_remove_members_internal_duplicate_aborts` | Abort `governance::EDuplicateBoardMember` |
| BatchRemoveMembers | `test_batch_remove_members_would_empty_aborts` | Abort `governance::EEmptyBoard` |
| BatchRemoveMembers | `test_batch_remove_members_empty_aborts` | Abort `member_ops::EEmptyBatch` |
| (roster) | `proposal_tests::test_roster_version_and_snapshot_version` | A batch counts as one version; a batch adding nobody does not bump; former members keep `was_member_at` history |
| (roster) | `proposal_tests::test_removed_member_keeps_vote_on_old_proposal` | A removed member still votes on an older proposal |
| (roster) | `proposal_tests::test_new_member_cannot_vote_on_old_proposal` | Abort `proposal::ENotInSnapshot` |
| (roster) | `proposal_tests::test_removed_member_cannot_execute` | Abort `proposal::ENotEligible` |
| (roster) | `ou_tests::test_root_size_independent_of_board_size` | Adding and removing a batch of members leaves the OU root's BCS size unchanged |

Unqualified names are in `board_ops_tests.move` (SetBoard) or `member_ops_tests.move` (member types). The five mutator gates (`add_board_member(s)_governance`, `remove_board_member(s)_governance`, `set_board_governance`) each have a denial test in `gate_tests.move`.

## Tests

---

### SetBoard: applies an add/remove diff

**Why it matters:** SetBoard is the general membership-management type. It must apply exactly the listed additions and removals, as one roster change.

```move
// test_set_board_e2e (condensed)
let payload = set_board::new(vector[NEW_MEMBER], vector[]); // to_add, to_remove
board_voting::submit_proposal(&ou, option::some(string::utf8(b"Add NEW_MEMBER to board")), payload, &clock, scenario.ctx());
// CREATOR votes YES: 1 of 2 meets quorum 5000 and threshold 5000
...
let ticket = board_voting::ticket_from_vote(&mut ou, proposal, &freeze, &clock, scenario.ctx());
board_ops::execute_set_board(&mut ou, ticket);

let gov = ou.governance();
assert!(gov.is_board_member(CREATOR));
assert!(gov.is_board_member(MEMBER_B));
assert!(gov.is_board_member(NEW_MEMBER));
```

`test_full_board_replacement` does a whole-board swap as `set_board::new(vector[C, D, E], vector[A, B])`: both old members lose membership and all three new ones gain it in the same change.

---

### SetBoard: the board can never be empty

**Why it matters:** A zero-member board could never propose, vote or execute again; the OU would be permanently ungovernable.

```move
#[test, expected_failure(abort_code = armature::governance::EEmptyBoard)]
fun test_set_board_empty_members_aborts() {
    // OU [CREATOR, MEMBER_B]
    let payload = set_board::new(vector[], vector[CREATOR, MEMBER_B]);
    // ... submit, vote, ticket_from_vote ...
    board_ops::execute_set_board(&mut ou, ticket); // aborts in governance::set_board
}
```

`RemoveMember` and `BatchRemoveMembers` enforce the same rule (`test_remove_last_member_aborts`, `test_batch_remove_members_would_empty_aborts`), as does OU creation with an empty initial board (`tribe_tests::create_tribe_aborts_on_empty_tribe_board`).

---

### SetBoard: an empty change aborts

**Requirement:** `set_board` with both lists empty aborts with `governance::ENoBoardChange`.

**Why it matters:** A no-op change would still advance `roster_version` and emit `BoardUpdated`, misleading indexers into recording a membership change.

`encrypted_entry_tests::test_setboard_empty_change_aborts` calls `ou.set_board_governance(vector[], vector[], &req)` with a test request.

---

### SetBoard: removals rotate the encryption epoch

**Requirement:** `ou::set_board_governance` bumps `encrypt_epoch` whenever `to_remove` is non-empty; additions alone leave it unchanged. `remove_board_member(s)_governance` bump it on every call.

**Why it matters:** Seal-encrypted entries are keyed to the epoch. A removed member must not be able to read entries published after they left.

`test_setboard_member_removal_auto_rotates_epoch`, `test_setboard_member_addition_does_not_rotate_epoch`, `test_setboard_full_replacement_rotates_epoch`, `test_setboard_multiple_removals_each_rotate_epoch` and `test_setboard_removal_makes_existing_entries_stale` in `encrypted_entry_tests.move`.

---

### Removed members lose rights at once; in-flight votes follow the snapshot

**Why it matters:** After a board change there must be no window in which both old and new boards can act, but proposals already open must keep a fixed electorate.

- A removed member cannot execute: `proposal_tests::test_removed_member_cannot_execute` (`proposal::ENotEligible`).
- A removed member cannot submit (planned `test_set_board__removed_member_cannot_propose_aborts`): `board_voting::submit_proposal` calls `governance::assert_board_member` and aborts with `governance::ENotBoardMember`.
- A removed member keeps a vote on proposals created while they were a member: `proposal_tests::test_removed_member_keeps_vote_on_old_proposal`.
- A new member cannot vote on an older proposal: `proposal_tests::test_new_member_cannot_vote_on_old_proposal` (`proposal::ENotInSnapshot`), but can submit and vote on new ones (`lifecycle_tests::small_startup_lifecycle`, step 10).

---

### AddMember / RemoveMember

**Why it matters:** Single-address changes are the lightweight alternative to SetBoard, and must reject no-op changes rather than silently succeed.

```move
// test_add_member_duplicate_aborts
let payload = add_member::new(MEMBER_B); // MEMBER_B is already on the board
// ... submit, vote, ticket_from_vote ...
member_ops::execute_add_member(&mut ou, ticket); // Abort governance::EDuplicateBoardMember
```

`test_remove_nonmember_aborts` (`governance::ENotBoardMember`) and `test_remove_last_member_aborts` (`governance::EEmptyBoard`) cover RemoveMember.

---

### BatchAddMembers: skips existing members, rejects proposer errors

**Requirement:** `execute_batch_add_members` aborts on an empty batch (`member_ops::EEmptyBatch`), a batch over 100 addresses (`member_ops::EBatchTooLarge`), or an address listed twice (`governance::EDuplicateBoardMember`). Addresses already on the board are skipped, not rejected, and reported in `MembersBatchAdded.skipped`.

**Why it matters:** Bulk onboarding lists often contain people who are already members; aborting the whole batch for that would force a re-vote. A duplicate inside the batch has no benign reading, so it aborts.

```move
// test_batch_add_members_existing_member_skipped
let payload = batch_add_members::new(vector[BATCH_MEMBER_1, MEMBER_B]); // MEMBER_B already a member
// ... submit, vote, ticket_from_vote ...
member_ops::execute_batch_add_members(&mut ou, ticket);
let gov = ou.governance();
assert!(gov.is_board_member(BATCH_MEMBER_1));
assert!(gov.is_board_member(MEMBER_B));
```

---

### BatchRemoveMembers: atomic

**Requirement:** `execute_batch_remove_members` aborts on an empty or oversize batch (`member_ops::EEmptyBatch`, `member_ops::EBatchTooLarge`), and `governance::remove_board_members` aborts, before any change, on a non-member (`governance::ENotBoardMember`), an in-batch duplicate (`governance::EDuplicateBoardMember`) or a removal that would empty the board (`governance::EEmptyBoard`).

**Why it matters:** Unlike batch add, a batch removal naming a non-member is treated as an error: removing the wrong set of people is not a benign overlap.

`test_batch_remove_members_e2e`, `test_batch_remove_members_nonmember_aborts`, `test_batch_remove_members_internal_duplicate_aborts`, `test_batch_remove_members_would_empty_aborts`, `test_batch_remove_members_empty_aborts` in `member_ops_tests.move`.

---

### The roster does not grow the OU root

**Requirement:** The roster is a `Table`, so the OU object's serialized size is independent of the board's size.

**Why it matters:** Sui charges storage and computation on the whole object on every write; a board stored inline would make every OU transaction more expensive as the board grows.

`ou_tests::test_root_size_independent_of_board_size` adds a batch of 20 members and removes them, asserting `member_count` and that `std::bcs::to_bytes(&ou).length()` is unchanged at each step.
