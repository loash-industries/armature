# Integration Flow Tests

## Summary

This file maps the demo steps of `02_demo_flows.md` (Flows A, B and C) to the current API and to the end-to-end tests that exercise them. There is no dedicated `test_flow_*` suite. Flow coverage comes from scenario tests that run whole governance sequences:

| Suite | End-to-end tests |
|-------|------------------|
| `armature_proposals/tests/lifecycle_tests.move` | `small_startup_lifecycle` (3-member DAO, small payments, board change, new board operates), `medium_enterprise_lifecycle` (5-member DAO, two SubDAOs, controller board change and freeze in one PTB, governance unfreeze, parent-to-SubDAO funding, SubDAO payroll) |
| `armature_proposals/tests/migration_tests.move` | `create_subdao_and_spin_out_e2e`, `controller_set_board_via_privileged_submit`, `spawn_dao_and_destroy_origin_e2e`, `migration_with_transfer_assets_e2e` |
| `armature_proposals/tests/subdao_ops_tests.move` | SubDAO creation, cap delegation and reclaim, pause/unpause, controller membership changes |
| `armature_framework/tests/tribe_tests.move` | Tribe → Officers → Members built in one transaction |
| `armature_world_bridge/tests/autojoin_e2e_tests.move` | EVE Frontier `Character` → tribe allowlist → board membership, no vote |
| `armature_external_type_tests/tests/external_type_lifecycle_tests.move` | A third-party type enabled by vote and by bypass, executed on every path, frozen and unfrozen |
| `armature_proposals/tests/composite_tests.move` | Several typed steps under one vote |

Conventions used in the sequences below:

- **Two-PTB vote.** `board_voting::submit_proposal<P>(&dao, metadata_ipfs, payload, &clock)` shares a `Proposal<P>`; members at its snapshot vote with `board_voting::vote(&mut proposal, &dao, approve, &clock)`; a current member executes with `board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock)`, which deletes the proposal and returns an `ExecutionTicket<P>` for `P`'s handler.
- **Atomic single vote.** When one member's YES passes the type's config and its `execution_delay_ms` is 0, `board_voting::submit_vote_execute<P>(&mut dao, metadata_ipfs, payload, &freeze, &clock)` does all of that in one PTB and creates no object (`09_board_voting.md`).
- **Opt-in types** are enabled first by an `EnableProposalType` vote (80%) executed with `admin_ops::execute_enable_proposal_type<P>`. The config in the payload must carry the bits `P`'s handler needs (`armature_proposals::type_permissions`; framework types get fixed bits) and meet their floor.
- The real tests set up opt-in types with the `dao.test_enable_type` seam, which skips that vote and the floors.

Status values: **Covered** (a real test exercises the step), **Partial** (the mechanism is tested but not the demo's exact scenario), **Planned** (buildable with the current API, no test yet), **Not implemented** (needs code that does not exist).

---

## Flow A — One Vision, One Tribe (Scaling)

### Test Matrix

| Step | Current API | Covered by | Status |
|------|-------------|------------|--------|
| A-1 Alice creates "Iron Haulers" | `dao::create(&governance::init_board(vector[ALICE]), name, metadata_uri, ctx)` | `dao_tests::test_create_dao`, `test_dao_created_event`, `test_default_proposal_types` | Covered |
| A-2 Recruit Bob and Carol | `set_board::new(vector[BOB, CAROL], vector[])` (or `batch_add_members::new`); Alice alone can use `submit_vote_execute<SetBoard>` | `board_ops_tests::test_grow_board_from_single`, `test_set_board_e2e`, `member_ops_tests::test_batch_add_members_e2e` | Covered |
| A-3 Pool resources | `treasury_vault::deposit<SUI>(&mut vault, coin, ctx)` × 3, permissionless | `treasury_vault_tests::test_deposit_permissionless`, `test_deposit_same_type_joins_balance` | Covered |
| A-4 Create Logistics SubDAO | Enable `CreateSubDAO` (EnableProposalType, 80%), then `create_subdao::new(name, vector[BOB, DAVE], metadata_uri)` → `lifecycle_ops::execute_create_subdao`; fund with a separate `SendCoinToDAO<SUI>` | `subdao_ops_tests::create_subdao_e2e`, `lifecycle_tests::medium_enterprise_lifecycle` (steps 4, 5, 9), `admin_ops_tests::enable_blocked_type_succeeds_for_independent_dao` | Covered |
| A-5 Structure | Parent vault holds the `SubDAOControl` and the SubDAO's `FreezeAdminCap`; SubDAO `controller_cap_id` set; no hierarchy or bypass meta-types on the SubDAO | `migration_tests::create_subdao_and_spin_out_e2e` (create phase), `dao_tests::test_subdao_default_types_omit_bypass_meta` | Covered |
| A-6 SubDAO pays Eve on its own | Logistics enables `SendCoin<SUI>` (80%), then `send_coin::new<SUI>(EVE, 10)` → `treasury_ops::execute_send_coin<SUI>` | `lifecycle_tests::medium_enterprise_lifecycle` (step 10), `treasury_ops_tests::send_coin_e2e` | Covered |
| A-7 Parent replaces Dave with Frank | Parent votes `ControllerBatchAddMembers` and `ControllerBatchRemoveMembers` and executes both in one PTB | `subdao_ops_tests::controller_batch_add_members_e2e`, `controller_batch_remove_members_e2e`, `migration_tests::controller_set_board_via_privileged_submit`, `lifecycle_tests::medium_enterprise_lifecycle` (step 7) | Covered |
| — | `test_flow_a__full_sequence` (planned): A-1 to A-7 in one scenario | closest: `lifecycle_tests::medium_enterprise_lifecycle`, `small_startup_lifecycle` | Planned |

### Tests

---

#### A-1: Alice creates the DAO

**Step:** Alice creates "Iron Haulers" with herself as the sole board member. The charter is the DAO's name plus a metadata URI (an IPFS CID of the document describing the tribe); there is no Walrus blob, hash or version on-chain.

**Why it matters:** This is the entry point for the protocol. Creation shares the `DAO`, `TreasuryVault`, `CapabilityVault`, `Charter` and `EmergencyFreeze`, transfers the `FreezeAdminCap` to Alice, and seeds the 14 default proposal types.

```move
let init = governance::init_board(vector[ALICE]);
let dao_id = dao::create(
    &init,
    string::utf8(b"Iron Haulers"),
    string::utf8(b"ipfs://<iron haulers metadata CID>"),
    scenario.ctx(),
);
// dao.status().is_active(); dao.governance().is_board_member(ALICE); member_count() == 1
// charter.name() == "Iron Haulers"; charter.metadata_uri() == the CID
```

---

#### A-2: Recruit via SetBoard

**Step:** Alice proposes adding Bob and Carol. As sole member her YES passes it; SetBoard's default config (quorum 5000, threshold 5000, delay 0) also allows the atomic path.

```move
let ticket = board_voting::submit_vote_execute<SetBoard>(
    &mut dao,
    option::some(string::utf8(b"Recruit Bob and Carol")),
    set_board::new(vector[BOB, CAROL], vector[]),
    &freeze,
    &clock,
    scenario.ctx(),
);
board_ops::execute_set_board(&mut dao, ticket);
// board: [ALICE, BOB, CAROL]; member_count() == 3
```

`board_ops_tests::test_grow_board_from_single` runs the same change ([A] → [A, B, C, D, E]) on the two-PTB path. Governance-sensitive types such as SetBoard should be given a non-zero `execution_delay_ms` once the board has more than one member, so they cannot use the atomic path (`09_board_voting.md`).

---

#### A-4 / A-5: Create and fund the Logistics SubDAO

**Step:** Bob proposes a Logistics department with board [Bob, Dave]. Alice and Bob vote YES, Carol abstains. `CreateSubDAO` carries no funding, so the parent funds the SubDAO with a second proposal.

```text
1. Enable CreateSubDAO (opt-in; framework type with fixed VAULT_STORE + VAULT_EXTRACT, floor 8000):
   enable_proposal_type::new(b"CreateSubDAO", type_name::with_defining_ids<CreateSubDAO>(),
                             proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0))
   → vote → admin_ops::execute_enable_proposal_type<CreateSubDAO>(&mut iron_haulers, ticket)

2. create_subdao::new(string::utf8(b"Logistics Dept"), vector[BOB, DAVE], string::utf8(b"ipfs://<logistics>"))
   Alice YES, Bob YES, Carol abstains: quorum 2 × 10000 ≥ 5000 × 3; threshold 2/2 ≥ 80% → Passed
   → lifecycle_ops::execute_create_subdao(&mut iron_haulers_vault, ticket, ctx)

3. Enable SendCoinToDAO<SUI> with type_permissions::treasury_spend() at ≥ 8000, then
   send_coin_to_dao::new<SUI>(logistics_treasury_id, 50)
   → treasury_ops::execute_send_coin_to_dao<SUI>(&mut iron_haulers_treasury, &mut logistics_treasury, ticket, ctx)
```

Resulting structure (A-5):

```
DAO Iron Haulers (independent)
├── TreasuryVault: 250 SUI
├── CapabilityVault: [SubDAOControl(Logistics), FreezeAdminCap(Logistics)]
└── Board: [Alice, Bob, Carol]
     └──► DAO Logistics Dept   controller_cap_id = some(SubDAOControl)
          ├── TreasuryVault: 50 SUI
          └── Board: [Bob, Dave]
```

`subdao_ops_tests::create_subdao_e2e` and `migration_tests::create_subdao_and_spin_out_e2e` check the vault contents and the SubDAO's `controller_cap_id`; `lifecycle_tests::medium_enterprise_lifecycle` creates two SubDAOs and funds one with `SendCoinToDAO<USDC>` (step 9).

---

#### A-6: SubDAO operates autonomously

**Step:** The Logistics board enables `SendCoin<SUI>` on its own DAO and pays Eve 10 SUI. The parent is not involved.

```text
Logistics: EnableProposalType for SendCoin<SUI> with type_permissions::treasury_spend() at ≥ 8000
Logistics: send_coin::new<SUI>(EVE, 10); Bob YES, Dave YES
           → treasury_ops::execute_send_coin<SUI>(&mut logistics_treasury, ticket, ctx)
```

`SendCoin<SUI>` is not SubDAO-blocked, so a controlled SubDAO may enable it. `lifecycle_tests::medium_enterprise_lifecycle` (step 10) has a Finance SubDAO enable `SendCoin<USDC>` and pay an employee.

---

#### A-7: Parent overrides the SubDAO board

**Step:** Dave goes inactive. The parent replaces him with Frank without a vote on the SubDAO.

```text
Iron Haulers enables ControllerBatchAddMembers and ControllerBatchRemoveMembers with
type_permissions::subdao_control() and subdao_control_scope() at ≥ 8000, then passes:
  controller_batch_add_members::new(control_id, vector[FRANK])
  controller_batch_remove_members::new(control_id, vector[DAVE])

One PTB, executed by a current Iron Haulers member:
  t1 = board_voting::ticket_from_vote(&mut iron_haulers, add_proposal, &freeze, &clock)
  subdao_ops::execute_controller_batch_add_members(&mut iron_haulers_vault, &mut logistics, t1, ctx)
  t2 = board_voting::ticket_from_vote(&mut iron_haulers, remove_proposal, &freeze, &clock)
  subdao_ops::execute_controller_batch_remove_members(&mut iron_haulers_vault, &mut logistics, t2, ctx)

Logistics board: [Bob, Frank]
```

Each handler loans the `SubDAOControl`, applies the change through a privileged request (`15_privileged_submit.md`) and returns the control. A single "replace the board" proposal needs a custom controller type or a composite of the two steps; `migration_tests::controller_set_board_via_privileged_submit` shows a SetBoard diff applied through a test controller type.

---

## Flow B — The Gate Builders (Emergence)

### Test Matrix

| Step | Current API | Covered by | Status |
|------|-------------|------------|--------|
| B-1 Dave pitches the project | `create_subdao::new(string::utf8(b"Gate Builders"), vector[DAVE, EVE], metadata_uri)`; the project charter is the SubDAO's `metadata_uri` | as A-4 | Covered |
| B-2 SubDAO materialises with 100 SUI | `execute_create_subdao`, then `SendCoinToDAO<SUI>` of 100 | as A-4 / A-5 | Covered |
| B-3 Gate caps deposited in the SubDAO vault | Needs a gate integration type (see below) | — | Not implemented |
| B-4 Configure gates by cap loan | A custom type with `VAULT_BORROW` scoped to the gate cap type; handler `loan_cap` → world call → `return_cap` | pattern: `upgrade_ops_tests::upgrade_e2e`, `borrow_scope_tests::request_carries_slot_scope_and_borrows_in_scope`, `capability_vault_tests::test_loan_and_return_restores_capability` | Partial (gate type not implemented) |
| B-5 Tolls accumulate | Revenue deposited with `treasury_vault::deposit` (permissionless) or recovered with `claim_coin` | `treasury_vault_tests::test_deposit_permissionless`, `test_claim_coin_recovers_direct_transfer` | Partial (no gate) |
| B-6 Revenue share to the parent | `SendCoinToDAO<SUI>` on Gate Builders: `send_coin_to_dao::new<SUI>(iron_haulers_treasury_id, 40)` | `treasury_ops_tests::send_coin_to_dao_e2e`, `composite_tests::composite_send_coin_to_dao_step_e2e` | Covered |
| B-6 On-chain revenue split (`RevenuePolicy`, split-on-deposit) | — | — | Not implemented |
| B-7 Charter change on the SubDAO | `UpdateMetadata` ("CharterUpdate", default on SubDAOs): `update_metadata::new(new_cid)` → `admin_ops::execute_update_metadata` | `charter_tests::charter_update_lifecycle` | Covered |
| B-7 Parent override of the charter | A custom controller type: loan the control, `privileged_submit` on Gate Builders, `charter::update_metadata(&mut charter, uri, &priv_req)` | `14_charter_ops.md`: `test_update_metadata__privileged_request_updates_subdao_charter` | Planned |
| B-7 Versioned amendment (`AmendCharter`) | — | `14_charter_ops.md`, "Planned (not implemented)" | Not implemented |
| — | `test_flow_b__full_sequence` | — | Not implemented (needs the gate type) |

### Tests

---

#### B-3 / B-4: Gate caps in a DAO vault

**Status:** No gate or SSU module exists in this repository. The original plan noted that the EVE Frontier world contracts let only a `Character` hold an assembly `OwnerCap`, and planned mock `gate` / `ssu` modules to work around it; those mocks were never written.

Two current constraints shape any future integration:

- **A cap enters a vault only through a handler.** `capability_vault::store_cap<T, P>` needs a request carrying `VAULT_STORE`, and `store_cap_init` is framework-internal. Today caps enter vaults through `AdoptCurrency<T>` (a `TreasuryCap<T>` passed by value to its handler), `TransferCapToSubDAO` / `ReclaimCapFromSubDAO` between DAOs, `TransferAssets` during migration, or an integrator type holding `VAULT_STORE`.
- **Loans are scoped.** A `ConfigureGateAccess` type would hold `VAULT_BORROW` with `borrow_scope = [GateOwnerCap]` at ≥ 8000, and its handler would `loan_cap<GateOwnerCap, ConfigureGateAccess>`, call the world contract, and `return_cap`. It could not reach any other cap in the vault (`proposal::EBorrowScopeDenied`). `upgrade_ops::execute_propose_upgrade` is the in-repo example: it loans the `UpgradeCap` under scope [`UpgradeCap`] and keeps it inside a `PendingUpgrade` hot potato.

---

#### B-6: Revenue share to the parent

**Step:** Eve proposes, on Gate Builders, to send 40 SUI (80% of 50 SUI of tolls) into the Iron Haulers treasury. The old plan used `SendCoin`, which pays an address; a treasury is reached with `SendCoinToDAO<T>`, which deposits into the `TreasuryVault` named in the payload.

```text
Gate Builders enables SendCoinToDAO<SUI> (TREASURY_WITHDRAW, ≥ 8000), then:
  send_coin_to_dao::new<SUI>(iron_haulers_treasury_id, 40); Dave YES, Eve YES
  → treasury_ops::execute_send_coin_to_dao<SUI>(&mut gate_builders_treasury, &mut iron_haulers_treasury, ticket, ctx)
```

Nothing enforces the 80% split: the framework has no `RevenuePolicy` object and `deposit` never splits. The share is paid by the SubDAO's own vote; the parent's recourse is the controller types (board change, pause, reclaim).

---

#### B-7: Charter change and parent override

**Step:** Dave proposes moving the revenue split to 70/30 by publishing a new charter document and updating the SubDAO's metadata URI. The Gate Builders board passes it with `UpdateMetadata`.

Alice then proposes, on Iron Haulers, to revert it. No first-party controller type rewrites a SubDAO's metadata, so this needs a custom type holding `VAULT_BORROW` scoped to `SubDAOControl` (≥ 8000). The vote is split: Alice YES, Bob NO, Carol abstains. Quorum is met (2 of 3 voted) but YES is 1 of 2 votes cast, 50% < 80%, so the proposal stays Active; if no further votes arrive it expires and anyone can delete it with `proposal::delete_expired_proposal`. The amendment stands.

---

## Flow C — Gate Network Franchise (Integration)

### Test Matrix

| Step | Current API | Covered by | Status |
|------|-------------|------------|--------|
| C-1 Gate caps into the DAO vault | See B-3 | — | Not implemented |
| C-2 Propose `ConfigureGateAccess` | Enable a custom type (`VAULT_BORROW`, scope [`GateOwnerCap`], ≥ 8000) | pattern: `permissions_tests::enable_proposal_type_grants_high_bits`, `borrow_scope_tests::meta_type_may_change_scope` | Not implemented |
| C-3 Execute via cap loan | See B-4 | pattern tests as B-4 | Partial |
| C-4 Toll revenue into the treasury | See B-5 | as B-5 | Partial |
| C-5 Third-party reads | `dao.governance().is_board_member(addr)`, `dao.is_governance_member(addr)`, `member_count()`, `dao.is_type_enabled<P>()`, `dao.type_config<P>()`, `vault.ids_for_type<T>()`, `treasury.balance<T>()` | `encrypted_entry_tests::test_is_governance_member_distinguishes_members`, `dao_tests::test_default_proposal_types` | Covered (reads) |
| C-6 Delegate a gate to Logistics | `transfer_cap_to_subdao::new(cap_id, logistics_id)` → `subdao_ops::execute_transfer_cap<T>`; reclaim with `ReclaimCapFromSubDAO` | `subdao_ops_tests::transfer_cap_to_subdao_e2e`, `reclaim_cap_from_subdao_e2e` (with a test cap type) | Covered |
| C-7 SSU supply depot | — | — | Not implemented |
| C-alt EVE membership integration (autojoin) | On an independent DAO: `ConfigureAutojoin` vote + `EnableBypassType` for `AutojoinDAO`; players call `autojoin_ops::autojoin` | `autojoin_e2e_tests` (8 tests; the bypass enable is set up with test seams) | Covered (autojoin); Partial (enabling vote) |
| C-alt Third-party type on every path | `Rebalance<T>` enabled by vote and by bypass | `external_type_lifecycle_tests::enabled_type_executes_on_every_path` | Covered |
| — | `test_flow_c__full_sequence` | — | Not implemented (needs gate / SSU types) |

### Tests

---

#### C-5: Third-party reads

**Step:** A route-planning DApp checks whether a pilot is a member of the DAO that runs a gate network.

Membership is readable per address: `governance::is_board_member(dao.governance(), addr)` (open tenure) and `dao::is_governance_member(&dao, addr)`. The roster is a `Table`, so there is no on-chain member list to fetch; an indexer rebuilds the list from `DAOBoardInitialized`, `BoardUpdated`, `MemberAdded` / `MemberRemoved`, `MembersBatchAdded` / `MembersBatchRemoved`, `ControllerMembersBatchAdded` / `ControllerMembersBatchRemoved` and `MemberAutojoined`. Proposal history comes from the proposal events, since executed and expired proposals are deleted.

---

#### C-6: Delegate a gate to the Logistics SubDAO

**Step:** Iron Haulers moves one gate's cap into the Logistics vault; it can take it back later.

```move
// subdao_ops_tests::transfer_cap_to_subdao_e2e (with a TestCap standing in for the gate cap)
let payload = transfer_cap_to_subdao::new(test_cap_id, subdao_id);
// ... submit, vote, ticket_from_vote on the parent ...
subdao_ops::execute_transfer_cap<TestCap>(&mut parent_vault, &mut subdao_vault, ticket);
assert!(!parent_vault.contains(test_cap_id));
assert!(subdao_vault.contains(test_cap_id));
```

Reclaim is `ReclaimCapFromSubDAO` (`subdao_ops_tests::reclaim_cap_from_subdao_e2e`), which uses the parent's `SubDAOControl` and needs no action from the SubDAO (`13_subdao_ops.md`).

---

#### C-alt: EVE Frontier membership through autojoin

**Step:** Instead of gate mocks, the shipped world integration lets a pilot whose `Character` belongs to an approved tribe join a DAO's board without a vote.

```text
Board of an independent DAO:
  EnableProposalType for ConfigureAutojoin (opt-in type, no bits), then
  ConfigureAutojoin: configure_autojoin::new(vector[42], vector[], option::some(true))
    → configure_autojoin::execute_configure_autojoin(&mut dao, ticket)
  EnableBypassType for AutojoinDAO (config with autojoin_ops::autojoin_permissions() = BOARD_ADD;
  the vote must reach 80% of the whole board)
    → external_execution::execute_enable_bypass_type<AutojoinDAO>(&mut dao, &mut vault, ticket, ctx)

Pilot (no vote):
  autojoin_ops::autojoin(&mut dao, &vault, cap_id, &character, &freeze, &clock, ctx)
```

`EnableBypassType` is SubDAO-blocked and not seeded on SubDAOs, so with first-party types autojoin can be enabled only on an independent DAO; a controlled SubDAO (such as a tribe's Members SubDAO) cannot vote it in. The e2e tests do not run the enabling vote: `setup_dao_with_autojoin` creates an independent DAO with `dao::create`, enables `AutojoinDAO` and `ConfigureAutojoin` with the `dao.test_enable_type` seam and stores a cap made by `proposal::new_external_execution_cap_for_testing<AutojoinDAO>`; only `ConfigureAutojoin` goes through a real vote.

`autojoin` checks that the sender is the character's address (`autojoin_ops::ESenderNotCharacterOwner`), that the allowlist exists (`EAllowlistNotInitialized`), is enabled (`EAutojoinDisabled`) and contains the character's tribe (`ETribeIdNotAllowed`), then mints the bypass ticket itself and adds exactly the sender (`autojoin_adds_only_the_sender`). Joining twice aborts `governance::EDuplicateBoardMember` (`autojoin_double_join_aborts`).
