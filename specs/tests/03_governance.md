# Governance Config Tests

## Summary

`governance.move` holds the Board roster: a `Table<address, Member>` with a `member_count` and a `roster_version` that increments once per membership change. `GovernanceConfig` is a struct and Board is the only governance model; every member votes with weight 1. `ou.move` holds the rules for configuring proposal types: which types may be submitted, which may never be disabled, the approval floors every stored config must meet, and who may grant permission bits and borrow scopes. `proposal::new_config` validates the bounds of a `ProposalConfig`.

These tests verify the roster and its aborts, the type gate at submission, the undisableable set, the floors, the grant rules and config validation. Handler-level behaviour of the admin types is in `10_admin_proposals.md`, pass math in `09_board_voting.md`.

## Test Matrix

**Roster (`governance.move`)**

| Test | Expected | Where |
|------|----------|-------|
| `test_governance_type_immutable_after_creation` | Board after creation; `GovernanceConfig` is a struct with no variant to change | `ou_tests` (structural) |
| `test_board_governance_persists_across_proposals` | `set_board` adds a member and keeps the others | `ou_tests` |
| `test_roster_version_and_snapshot_version` | Version starts at 0; +1 per change; a batch counts once; a batch that adds nobody does not bump it; `was_member_at` covers `[joined, left)`; proposals record the version | `proposal_tests` |
| `test_root_size_independent_of_board_size` | Adding and removing 20 members leaves the root's BCS size unchanged | `ou_tests` |
| `test_setboard_empty_change_aborts` | `set_board` with both lists empty: `governance::ENoBoardChange` | `encrypted_entry_tests` |
| `test_set_board_empty_members_aborts` | `SetBoard` removing every member: `governance::EEmptyBoard` | `armature_proposals::board_ops_tests` |
| `test_set_board_same_address_in_both_lists_aborts` | `governance::EDuplicateBoardMember` | planned |
| `test_set_board_add_existing_member_aborts` | `governance::EDuplicateBoardMember` | planned |
| `test_set_board_remove_non_member_aborts` | `governance::ENotBoardMember` | planned |
| `test_add_member_duplicate_aborts` | `governance::EDuplicateBoardMember` | `armature_proposals::member_ops_tests` |
| `test_remove_nonmember_aborts` | `governance::ENotBoardMember` | `armature_proposals::member_ops_tests` |
| `test_remove_last_member_aborts` | `governance::EEmptyBoard` | `armature_proposals::member_ops_tests` |
| `test_batch_add_members_existing_member_skipped` | Existing members are skipped and reported in `MembersBatchAdded.skipped` | `armature_proposals::member_ops_tests` |
| `test_batch_add_members_internal_duplicate_aborts` | Same address twice in the batch: `governance::EDuplicateBoardMember` | `armature_proposals::member_ops_tests` |
| `test_batch_remove_members_would_empty_aborts` | `governance::EEmptyBoard` | `armature_proposals::member_ops_tests` |
| `test_setboard_member_removal_auto_rotates_epoch` | A removal bumps `encrypt_epoch`; an add-only change does not (`test_setboard_member_addition_does_not_rotate_epoch`) | `encrypted_entry_tests` |

**Type gate at submission**

| Test | Expected | Where |
|------|----------|-------|
| `submit_proposal_aborts_for_type_without_slot` | A payload type with no slot: `board_voting::ETypeNotEnabled`, even when another type is enabled | `board_voting_tests` |
| `submit_proposal_succeeds_with_enabled_type` | `Proposal.type_key` is the slot's display key | `board_voting_tests` |
| `submit_proposal_default_type_uses_its_payload_slot` | A `SetBoard` payload uses the default "SetBoard" slot | `board_voting_tests` |
| `test_submit_by_non_member_aborts` | `governance::ENotBoardMember` on the two-PTB path (atomic path: `submit_vote_execute_tests::test_sve__non_member_aborts`) | planned |
| `test_propose_threshold__above_board_weight_aborts` | `propose_threshold` 2 blocks every Board member: `board_voting::EProposeThresholdNotMet` | `board_voting_tests` |

**Undisableable types**

| Test | Expected | Where |
|------|----------|-------|
| `disable_core_type_enable_proposal_type_aborts` | `admin_ops::EUndisableableType` | `armature_proposals::admin_ops_tests` |
| `disable_core_type_unfreeze_proposal_type_aborts` | `admin_ops::EUndisableableType` | `armature_proposals::admin_ops_tests` |
| `test_cannot_disable_disable_proposal_type_itself_aborts` | `admin_ops::EUndisableableType` | planned |
| `test_cannot_disable_transfer_freeze_admin_aborts` | `admin_ops::EUndisableableType` | planned |
| `test_cannot_disable_bypass_meta_types_aborts` | `EnableBypassType` / `DisableBypassType`: `admin_ops::EUndisableableType` | planned |
| `test_can_disable_ordinary_type` | `admin_ops::execute_disable_proposal_type` removes the slot and display key and emits `ProposalTypeDisabled` (registry effect covered via the seam by `ou_tests::test_enable_then_disable_leaves_nothing_behind`) | planned |
| `test_disable_unknown_display_key_aborts` | `admin_ops::ETypeNotEnabled` | planned |

**Approval floors**

| Test | Expected | Where |
|------|----------|-------|
| `permission_floor_values` | `ou::permission_floor` is 80% iff the mask holds `TYPE_ADMIN`, `MIGRATE`, `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT` | `permissions_tests` |
| `enable_with_high_bits_under_floor_aborts` | Enabling a type holding `VAULT_EXTRACT` at 79.99%: `ou::EThresholdBelowMinimum` | `permissions_tests` |
| `update_lowering_threshold_under_permission_floor_aborts` | Lowering a `TYPE_ADMIN` holder to 50%: `ou::EThresholdBelowMinimum` | `permissions_tests` |
| `framework_type_fixed_bits_need_their_floor` | Enabling `SpawnOU` (fixed `MIGRATE`) at 50%: `ou::EThresholdBelowMinimum` | `permissions_tests` |
| `framework_type_enabled_without_bits_gets_fixed_set` | `SpawnOU` enabled at 80% gets `MIGRATE` | `permissions_tests` |
| `execute_enable_proposal_type_adds_slot` | A non-framework type with no bits is enabled at 50% through the handler | `armature_proposals::admin_ops_tests` |
| `update_config_below_floor_aborts` | `UpdateProposalConfig` lowering `EnableProposalType` to 50%: `ou::EThresholdBelowMinimum` | `armature_proposals::admin_ops_tests` |
| `type_floor_holds_on_direct_update` | Same floor when `ou::update_proposal_config` is called directly | `permissions_tests` |
| `test_update_config_self_below_80_aborts` | `UpdateProposalConfig` lowering its own threshold below 80%: `ou::EThresholdBelowMinimum` at execution | planned |
| `enable_proposal_type_submission_floor_rejects_below_80_percent` | `EnableProposalType` config below 80% at submission: `board_voting::EFloorNotMet` | `armature_proposals::admin_ops_tests` |
| `enable_proposal_type_submission_floor_allows_80_percent` | Exactly 80% submits | `armature_proposals::admin_ops_tests` |
| `test_sve__enable_proposal_type_below_floor_aborts` | Same check on the atomic path | `submit_vote_execute_tests` |
| `update_proposal_config_self_submission_floor_rejects_below_80_percent` | `propose_update_proposal_config` targeting itself while its config is below 80%: `admin_ops::EFloorNotMet` | `armature_proposals::admin_ops_tests` |
| `update_proposal_config_self_submission_floor_allows_80_percent` | Exactly 80% submits | `armature_proposals::admin_ops_tests` |
| `update_proposal_config_non_self_target_succeeds` | An `UpdateProposalConfig` targeting `SetBoard` executes and changes its quorum (the test lowers `UpdateProposalConfig`'s own config with `test_update_config`) | `armature_proposals::admin_ops_tests` |
| `create_wired_subou_aborts_on_update_proposal_config_below_floor` | Creation-time override of `UpdateProposalConfig` below 80%: `ou::EThresholdBelowMinimum` | `tribe_tests` |

**Who may grant bits and scopes**

| Test | Expected | Where |
|------|----------|-------|
| `enable_by_non_meta_type_with_bits_aborts` | A non-meta request enabling a type with bits: `ou::EPermissionChangeNotAllowed` | `permissions_tests` |
| `enable_by_non_meta_type_without_bits_passes` | Without bits, any `TYPE_ADMIN` request may enable | `permissions_tests` |
| `update_bits_by_non_meta_type_aborts` | `ou::EPermissionChangeNotAllowed` | `permissions_tests` |
| `update_without_bit_change_by_non_meta_type_passes` | Other fields may change when the bits stay | `permissions_tests` |
| `enable_proposal_type_grants_low_bits`, `enable_proposal_type_grants_high_bits`, `enable_bypass_type_grants_high_bits` | `ou` accepts a grant, including an 80% bit, from a meta-type request (all three sit at 80%) | `permissions_tests` |
| `update_proposal_config_grants_and_revokes_high_bits` | `UpdateProposalConfig` grants, then revokes, `MIGRATE` | `permissions_tests` |
| `update_proposal_config_preserves_permissions` | The handler keeps the target's bits when the payload leaves them unset | `armature_proposals::admin_ops_tests` |
| `privileged_request_may_change_bits` | A controller (privileged) request skips the grant rules | `permissions_tests` |
| `framework_type_enabled_with_other_bits_aborts` | `ou::EFixedPermissions` | `permissions_tests` |
| `update_proposal_config_self_grant_aborts` | `UpdateProposalConfig` changing its own bits: `ou::EFixedPermissions` | `permissions_tests` |
| `composite_payload_cannot_hold_bits` | `ou::EFixedPermissions`, even for a privileged request | `permissions_tests` |
| `scope_change_needs_meta_type`, `enable_with_scope_needs_meta_type` | A borrow-scope change is a grant: `ou::EPermissionChangeNotAllowed` | `borrow_scope_tests` |
| `framework_type_scope_cannot_be_changed` | `ou::EFixedPermissions` | `borrow_scope_tests` |
| `add_step_rejects_enable_proposal_type` | `composite::EUseTypedStep` | `permissions_tests` |
| `composite_enable_step_with_bits_aborts`, `composite_enable_step_with_scope_aborts`, `composite_update_step_changing_bits_aborts`, `composite_update_step_changing_scope_aborts` | `composite::EGrantInComposite` | `permissions_tests` |

**`ProposalConfig` validation**

| Test | Expected | Where |
|------|----------|-------|
| `test_config_valid_boundaries_succeeds` | quorum 1 and 10000, threshold 5000 and 10000, expiry 1 hour accepted | `ou_tests` |
| `test_config_quorum_zero_aborts` | `proposal::EInvalidQuorum` (test uses a bare `expected_failure`) | `ou_tests` |
| `test_config_quorum_above_max_aborts` | `proposal::EInvalidQuorum` (bare `expected_failure`) | `ou_tests` |
| `test_config_threshold_below_min_aborts` | `proposal::EInvalidApprovalThreshold` (bare `expected_failure`) | `ou_tests` |
| `test_config_threshold_above_max_aborts` | `proposal::EInvalidApprovalThreshold` | planned |
| `test_config_expiry_below_min_aborts` | `proposal::EInvalidExpiryMs` (bare `expected_failure`) | `ou_tests` |
| `config_permissions_builder_and_accessors` | New configs hold no bits; `with_permissions` replaces the mask | `permissions_tests` |
| `with_permissions_rejects_unknown_bit` | `permissions::EUnknownPermission` | `permissions_tests` |
| `enable_proposal_type_composable_cooldown_conflict_aborts` | `cooldown_ms > 0` with `composable_allowed`: `admin_ops::EComposableCooldownConflict` | `armature_proposals::admin_ops_tests` |

## Tests

---

### Board is the only governance model

**Requirement:** `governance::init_board(members)` is the only `GovernanceTypeInit`. `GovernanceConfig` is a struct `{ members: Table<address, Member>, member_count, roster_version }`; there is no enum variant to switch. Each `Member` keeps its tenures (`joined`, `left`); a former member's entry is closed, not deleted, and re-adding opens a new tenure. `is_board_member` is true while the last tenure is open; `was_member_at(addr, v)` is true if a tenure covers version `v` (`joined <= v < left`). Every member votes with weight 1 (`governance::member_vote_weight`).

**Why it matters:** Proposals store the roster version they were created at instead of copying the roster, so the history must be kept for every address that was ever a member. The roster lives in a `Table` so the OU root does not grow with the board.

```move
// From proposal_tests::test_roster_version_and_snapshot_version
let mut ou = scenario.take_shared<OU>();
assert!(ou.governance().roster_version() == 0);
ou.governance_mut().add_board_members(vector[@0xC1, @0xC2]);
assert!(ou.governance().roster_version() == 1);          // a batch is one change
ou.governance_mut().add_board_members(vector[@0xC1, @0xC2]);
assert!(ou.governance().roster_version() == 1);          // nothing added, no bump
ou.governance_mut().remove_board_members(vector[@0xC1, @0xC2]);
assert!(ou.governance().roster_version() == 2);
assert!(ou.governance().was_member_at(@0xC1, 1));
assert!(!ou.governance().was_member_at(@0xC1, 2));       // left at version 2
assert!(!ou.governance().is_board_member(@0xC1));
test_scenario::return_shared(ou);
```

---

### Roster changes and their aborts

**Requirement:** Roster changes are `public(package)` in `governance` and reached through the gated `ou` mutators (`set_board_governance` needs `BOARD_SET`; `add_board_member(s)_governance` `BOARD_ADD`; `remove_board_member(s)_governance` `BOARD_REMOVE`). `set_board(to_add, to_remove)` applies a diff as one change and checks everything before mutating: `governance::ENoBoardChange` if both lists are empty, `governance::EDuplicateBoardMember` if an address appears twice across the lists or an address to add is already a member, `governance::ENotBoardMember` if an address to remove is not a member, `governance::EEmptyBoard` if the board would be empty. `add_board_members` skips existing members and aborts only on duplicates inside the batch. Any removal bumps the OU's `encrypt_epoch`.

**Why it matters:** A board must never become empty (nobody could propose again), and a malformed diff must fail as a whole rather than apply partly.

```move
#[test, expected_failure(abort_code = governance::EDuplicateBoardMember)]
fun test_set_board_same_address_in_both_lists_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);   // board [CREATOR, MEMBER_B]
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    ou.governance_mut().set_board(vector[MEMBER_C], vector[MEMBER_C]);
    abort 0
}
```

The handler-level cases are in `armature_proposals::board_ops_tests` and `member_ops_tests` (see `12_board_ops.md`).

---

### Only enabled types can be submitted

**Requirement:** `board_voting::submit_proposal<P>` finds the config through `P`'s slot; there is no `type_key` argument. It aborts `board_voting::ETypeNotEnabled` if `P` has no slot, `governance::ENotBoardMember` unless the sender is a current member, and `board_voting::EProposeThresholdNotMet` if the member's weight (1) is below `propose_threshold`. The proposal records the slot's display key as `type_key`.

**Why it matters:** This is the gate that keeps unapproved types off the OU. Because the slot is keyed by the Move type, no string can be spoofed to submit one payload under another type's config.

```move
// From board_voting_tests::submit_proposal_aborts_for_type_without_slot
#[test, expected_failure(abort_code = armature::board_voting::ETypeNotEnabled)]
fun submit_proposal_aborts_for_type_without_slot() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());
    create_ou_single_member_with_custom_key(&mut scenario);   // enables TestPayload only

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        board_voting::submit_proposal(&ou, option::none(), AltPayload { label: 99 }, &clock, scenario.ctx());
        test_scenario::return_shared(ou);
    };
    clock.destroy_for_testing();
    scenario.end();
}
```

---

### Core types cannot be disabled

**Requirement:** `ou::is_undisableable_type` covers `EnableProposalType`, `DisableProposalType`, `EnableBypassType`, `DisableBypassType`, `TransferFreezeAdmin` and `UnfreezeProposalType`. `admin_ops::execute_disable_proposal_type` resolves the payload's display key (`admin_ops::ETypeNotEnabled` if no type carries it), aborts `admin_ops::EUndisableableType` for these types, and otherwise removes the slot through `ou::disable_proposal_type` (`TYPE_ADMIN`). The undisableable check lives in the handler; `ou::disable_proposal_type` checks only the request's OU and `TYPE_ADMIN`.

**Why it matters:** Without `EnableProposalType` an OU could never add a type again; without `UnfreezeProposalType` it could not lift a freeze by vote; without `TransferFreezeAdmin` it could not hand the freeze-admin role over by vote (that handler also needs the cap itself; see `08_emergency.md`).

```move
// From armature_proposals::admin_ops_tests::disable_core_type_enable_proposal_type_aborts
#[test, expected_failure(abort_code = admin_ops::EUndisableableType)]
fun disable_core_type_enable_proposal_type_aborts() {
    // ... submit disable_proposal_type::new(b"EnableProposalType".to_ascii_string()), vote it through
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut ou, proposal, &freeze, &clock, scenario.ctx());
        admin_ops::execute_disable_proposal_type(&mut ou, ticket);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };
    // ...
}
```

---

### Approval floors

**Requirement:** Every path that stores a config (`ou::enable_proposal_type`, `ou::update_proposal_config`, creation-time overrides) runs `assert_config_floors`: the threshold must meet the type's own floor (`ou::min_approval_threshold_for_type`: 80% for `EnableProposalType`, `UpdateProposalConfig` and `EnableBypassType`) and the floor of the bits it holds (`ou::permission_floor`: 80% if it holds `TYPE_ADMIN`, `MIGRATE`, `TREASURY_WITHDRAW`, `VAULT_BORROW` or `VAULT_EXTRACT`). Failure aborts `ou::EThresholdBelowMinimum`. A framework type's fixed bits count, so `SpawnOU`, `CreateSubOU`, `SpinOutSubOU` and `TransferAssets` need 80% configs, as do `DisableProposalType` and `DisableBypassType` through `TYPE_ADMIN`.

Submission-time checks repeat two of these floors as defence in depth: `board_voting::EFloorNotMet` when `EnableProposalType`'s config is below 80%, and `admin_ops::EFloorNotMet` when `admin_ops::propose_update_proposal_config` targets `UpdateProposalConfig` while its config is below 80%. Since `ou` keeps both configs at or above 80%, the tests lower them with `ou::test_update_config` to reach these checks.

**Why it matters:** A slim majority must not be able to weaken the rules that protect high-impact powers, nor approve those powers at a lower bar than they require.

```move
// From permissions_tests
#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// SpawnOU carries MIGRATE, so a config below 80% cannot enable it.
fun framework_type_fixed_bits_need_their_floor() {
    with_ou!(|ou| {
        let r = req<EnableProposalType>(ou);
        ou.enable_proposal_type<armature::spawn_ou::SpawnOU, EnableProposalType>(
            b"SpawnOU".to_ascii_string(),
            config_at(5_000, 0),
            &r,
        );
        abort 0
    });
}
```

---

### Who may grant permission bits and borrow scopes

**Requirement:** A config change that alters a type's bits or borrow scope must come from an `EnableProposalType`, `EnableBypassType` or `UpdateProposalConfig` request, or a privileged (controller) request; otherwise `ou::EPermissionChangeNotAllowed`. A scope change counts as granting `VAULT_BORROW`. The floor of the bits added must not exceed the granter's own floor (`ou::EGrantFloorNotMet`); all three meta-types sit at 80%, so no test can reach that abort today. Framework types always hold exactly `ou::framework_permissions` and `ou::framework_borrow_scope`: enabling one with any other non-empty set, or updating it to anything else, aborts `ou::EFixedPermissions`, also for a privileged request. Grants are standalone-only: `composite::add_step` refuses `EnableProposalType` and `UpdateProposalConfig` (`composite::EUseTypedStep`), and the typed step builders refuse any bit or scope change (`composite::EGrantInComposite`).

**Why it matters:** Bits bound what a request can do. If any type could hand out bits, a low-threshold type could escalate itself.

```move
// From permissions_tests
#[test, expected_failure(abort_code = ou::EPermissionChangeNotAllowed)]
fun enable_by_non_meta_type_with_bits_aborts() {
    with_ou!(|ou| {
        // A request of type Granted (not a meta-type) carrying every bit.
        enable_target<Granted>(ou, config_at(5_000, permissions::board_add()));
    });
}
```

---

### ProposalConfig validation

**Requirement:** `proposal::new_config(quorum, approval_threshold, propose_threshold, expiry_ms, execution_delay_ms, cooldown_ms)` aborts `proposal::EInvalidQuorum` unless `1 <= quorum <= 10000`, `proposal::EInvalidApprovalThreshold` unless `5000 <= approval_threshold <= 10000`, and `proposal::EInvalidExpiryMs` unless `expiry_ms >= 3_600_000`. There is no upper bound on `expiry_ms`, `execution_delay_ms`, `cooldown_ms` or `propose_threshold`; deadlines saturate at `u64::MAX` (see `04_proposals.md`). A new config is not composable, holds no bits and has an empty borrow scope; `with_composable_allowed`, `with_permissions` (`permissions::EUnknownPermission` for undefined bits) and `with_borrow_scope` return modified copies. Building a config grants nothing: the OU applies floors and grant rules when it is stored.

**Why it matters:** A zero quorum would let one vote pass a proposal however large the board, a threshold under 50% would let a minority pass proposals, and a very short expiry would allow flash governance.

```move
#[test, expected_failure(abort_code = proposal::EInvalidQuorum)]
fun test_config_quorum_zero_aborts() {
    proposal::new_config(0, 5_000, 0, 3_600_000, 0, 0);
}

#[test, expected_failure(abort_code = proposal::EInvalidApprovalThreshold)]
fun test_config_threshold_above_max_aborts() {   // planned
    proposal::new_config(1, 10_001, 0, 3_600_000, 0, 0);
}

#[test]
fun test_config_valid_boundaries_succeeds() {
    proposal::new_config(1, 5_000, 0, 3_600_000, 0, 0);
    proposal::new_config(10_000, 10_000, 1_000_000, 604_800_000, 86_400_000, 86_400_000);
}
```

(`ou_tests` writes the abort tests with a bare `#[expected_failure]`; the named codes above are what they hit.)
