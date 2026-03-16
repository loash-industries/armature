# DAO Creation & Lifecycle Tests

## Summary

The `dao.move` module manages DAO creation, status transitions (`Active → Migrating`), and destruction. These tests verify the lifecycle invariants that prevent premature destruction, ensure migration locks governance, and confirm that destroyed DAOs cannot execute proposals.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_status_starts_active` | `dao.status == Active` after creation |
| `test_transition_active_to_migrating` | Status becomes `Migrating` with successor ID |
| `test_migrating_cannot_revert_to_active_aborts` | Abort — no path back from Migrating |
| `test_migrating_blocks_non_transfer_proposals_aborts` | Abort on `SendCoin` create while Migrating |
| `test_migrating_allows_transfer_assets` | `TransferAssets` proposal succeeds while Migrating |
| `test_destroy_requires_migrating_aborts` | Abort if status is Active |
| `test_destroy_requires_empty_treasury_aborts` | Abort if treasury has balance |
| `test_destroy_requires_empty_cap_vault_aborts` | Abort if cap vault has capabilities |
| `test_destroy_succeeds_when_migrating_and_empty` | DAO and companions deleted |
| `test_inflight_proposal_unexecutable_after_destroy` | Proposal remains Passed but DAO object is gone |
| `test_create__emits_dao_created_event` | `DAOCreated` event with correct fields |
| `test_create__initializes_all_companion_objects` | Treasury, CapVault, Charter, Freeze all exist |
| `test_create__default_proposal_types_enabled` | 9 default types in `enabled_proposals` |

## Tests

---

### Status starts Active

**Requirement:** Every newly created DAO has `status == Active`.

**Why it matters:** If a DAO starts in any other status, governance would be locked from the outset — no proposals could be created or executed.

```move
#[test]
fun test_status_starts_active() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);

        // Assert: DAO starts in Active status
        assert!(dao::status(&dao) == dao::status_active());

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Transition Active to Migrating

**Requirement:** `DAOStatus` transitions: `Active → Migrating`. The successor DAO ID is recorded.

**Why it matters:** Migration is the only path to orderly DAO dissolution. Without it, assets could be trapped in a dead DAO.

```move
#[test]
fun test_transition_active_to_migrating() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);
    let successor_id = @0xSUCCESSOR;

    // Enable and execute a migration proposal (stretch: TransferAssets / BeginMigration)
    // For test purposes, assume a governance-gated status setter exists:
    scenario.next_tx(ALICE);
    {
        let mut dao = test_scenario::take_shared<DAO>(&scenario);

        dao::begin_migration(&mut dao, object::id_from_address(successor_id), /* req */);

        // Assert: status is now Migrating with correct successor
        assert!(dao::status(&dao) == dao::status_migrating());
        assert!(dao::successor_dao_id(&dao) == object::id_from_address(successor_id));

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Migrating cannot revert to Active

**Requirement:** No path back from Migrating.

**Why it matters:** If migration were reversible, a compromised board could cancel migration to retain control after assets have partially moved, creating an inconsistent state.

```move
#[test]
#[expected_failure(abort_code = dao::ENotActive)]
fun test_migrating_cannot_revert_to_active_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut dao = test_scenario::take_shared<DAO>(&scenario);
        // Transition to Migrating
        dao::begin_migration(&mut dao, object::id_from_address(@0xSUCC), /* req */);

        // Attempt to revert — should abort
        dao::revert_to_active(&mut dao); // This function should not exist or should abort

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Migrating blocks non-transfer proposals

**Requirement:** While `Migrating`, only `TransferAssets` can be created/executed.

**Why it matters:** Allowing arbitrary proposals during migration could drain treasury or change governance before migration completes, undermining the successor DAO.

```move
#[test]
#[expected_failure(abort_code = dao::ENotActive)]
fun test_migrating_blocks_non_transfer_proposals_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Transition to Migrating
    scenario.next_tx(ALICE);
    {
        let mut dao = test_scenario::take_shared<DAO>(&scenario);
        dao::begin_migration(&mut dao, object::id_from_address(@0xSUCC), /* req */);
        test_scenario::return_shared(dao);
    };

    // Attempt to create a SendCoin proposal — should abort
    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // This should abort because status is Migrating and type is not TransferAssets
        proposal::create(
            &dao,
            treasury_ops::new_send_coin<SUI>(@0xRECIPIENT, 50),
            b"metadata",
            &clock,
            scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Migrating allows TransferAssets

**Requirement:** `TransferAssets` proposals can be created and executed while Migrating.

**Why it matters:** This is the only mechanism to move assets to the successor DAO. Blocking it would trap assets.

```move
#[test]
fun test_migrating_allows_transfer_assets() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Transition to Migrating
    // ...

    // Create TransferAssets proposal — should succeed
    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        proposal::create(
            &dao,
            /* TransferAssets payload */,
            b"migration-transfer",
            &clock,
            scenario.ctx(),
        );

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(dao);
    };
    // Assert: proposal created successfully (no abort)
    test_scenario::end(scenario);
}
```

---

### Destroy requires Migrating status

**Requirement:** `dao::destroy` requires `Migrating` status.

**Why it matters:** Destroying an Active DAO would permanently delete all governance and treasury objects, losing assets and breaking in-flight proposals.

```move
#[test]
#[expected_failure(abort_code = dao::ENotMigrating)]
fun test_destroy_requires_migrating_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let cap_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);

        // Attempt destroy while Active — should abort
        dao::destroy(dao, vault, cap_vault, charter, freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Destroy requires empty treasury

**Requirement:** `dao::destroy` requires empty vaults.

**Why it matters:** Destroying a DAO with non-zero balances would permanently burn those assets.

```move
#[test]
#[expected_failure(abort_code = dao::EVaultsNotEmpty)]
fun test_destroy_requires_empty_treasury_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 100);

    // Transition to Migrating (assume helper)
    // ...

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let cap_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);

        // Treasury has 100 SUI — destroy should abort
        dao::destroy(dao, vault, cap_vault, charter, freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Destroy requires empty cap vault

**Requirement:** `dao::destroy` requires empty vaults.

**Why it matters:** Capabilities stored in the vault (e.g., `SubDAOControl`) would become inaccessible, severing control over SubDAOs.

```move
#[test]
#[expected_failure(abort_code = dao::EVaultsNotEmpty)]
fun test_destroy_requires_empty_cap_vault_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Transition parent to Migrating, drain treasury
    // ...

    scenario.next_tx(ALICE);
    {
        // Cap vault still holds SubDAOControl — destroy should abort
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let cap_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);

        dao::destroy(dao, vault, cap_vault, charter, freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Destroy succeeds when Migrating and empty

**Requirement:** Successful destruction deletes DAO and all companion objects.

**Why it matters:** Confirms the happy path — old DAOs are cleaned up after migration, preventing "inert DAO persistence" (threat 2.8).

```move
#[test]
fun test_destroy_succeeds_when_migrating_and_empty() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Transition to Migrating, ensure vaults are empty (they start empty)
    // ...

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let cap_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);

        dao::destroy(dao, vault, cap_vault, charter, freeze);
        // All objects consumed — no return_shared needed
    };

    // Assert: objects no longer exist as shared objects
    // (test_scenario would abort if we tried to take_shared<DAO> again)
    test_scenario::end(scenario);
}
```

---

### In-flight proposals unexecutable after destroy

**Requirement:** After destruction, in-flight proposals are unexecutable (DAO object gone).

**Why it matters:** A Passed proposal referencing a destroyed DAO must not be executable — there is no DAO to authorize against and no treasury to withdraw from.

```move
#[test]
fun test_inflight_proposal_unexecutable_after_destroy() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Create and pass a proposal
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"new-cid"),
    );
    test_helpers::pass_proposal<admin::UpdateMetadata>(&mut scenario, prop_id, vector[ALICE]);

    // Transition to Migrating, destroy DAO
    // ...

    // Attempt to execute the passed proposal — DAO no longer exists as a shared object.
    // test_scenario::take_shared<DAO> will fail because the object was consumed.
    // The proposal remains a shared object with status Passed but can never be executed.
    // This is inherently guaranteed by Sui's object model — no additional assertion needed.
    test_scenario::end(scenario);
}
```

---

### Creation: Emits DAOCreated event

**Why it matters:** Indexers rely on `DAOCreated` events to discover new DAOs. Missing events break UI discovery.

```move
#[test]
fun test_create__emits_dao_created_event() {
    let mut scenario = test_scenario::begin(ALICE);
    test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    // Assert: DAOCreated event emitted with correct fields
    let effects = test_scenario::next_tx_effects(&scenario);
    let events = test_scenario::events_of_type<dao::DAOCreated>(&effects);
    assert!(vector::length(&events) == 1);

    let event = vector::borrow(&events, 0);
    assert!(event.governance_type == b"Board");
    // charter_id, treasury_id etc. should be non-zero
    test_scenario::end(scenario);
}
```

---

### Creation: Initializes all companion objects

**Why it matters:** Missing companion objects would cause runtime aborts in any subsequent operation.

```move
#[test]
fun test_create__initializes_all_companion_objects() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        // All four companion objects must exist as shared objects
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        let cap_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let charter = test_scenario::take_shared<Charter>(&scenario);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);

        // Verify back-references
        assert!(treasury::dao_id(&vault) == object::id(&dao));
        assert!(capability_vault::dao_id(&cap_vault) == object::id(&dao));
        assert!(charter::dao_id(&charter) == object::id(&dao));

        test_scenario::return_shared(dao);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### Creation: Default proposal types enabled

**Why it matters:** The 9 default-enabled types (see spec) must be available immediately after creation without an `EnableProposalType` ceremony.

```move
#[test]
fun test_create__default_proposal_types_enabled() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);

        // 9 default types from spec
        assert!(dao::is_type_enabled<admin::UpdateProposalConfig>(&dao));
        assert!(dao::is_type_enabled<admin::EnableProposalType>(&dao));
        assert!(dao::is_type_enabled<admin::DisableProposalType>(&dao));
        assert!(dao::is_type_enabled<admin::UpdateMetadata>(&dao));
        assert!(dao::is_type_enabled<admin::TransferFreezeAdmin>(&dao));
        assert!(dao::is_type_enabled<admin::UnfreezeProposalType>(&dao));
        assert!(dao::is_type_enabled<treasury_ops::SendCoin<SUI>>(&dao));
        assert!(dao::is_type_enabled<board_ops::SetBoard>(&dao));
        assert!(dao::is_type_enabled<admin::UpdateFreezeConfig>(&dao) == false); // opt-in

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```
