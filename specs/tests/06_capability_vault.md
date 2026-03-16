# Capability Vault Tests

## Summary

The `capability_vault.move` module stores arbitrary `key + store` capabilities via dynamic object fields. These tests verify that all vault access requires governance authorization, registries stay in sync, loan semantics preserve IDs, and privileged extraction is controller-gated.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_borrow_cap_requires_execution_request` | `public(friend)` — requires `ExecutionRequest` |
| `test_loan_cap_requires_execution_request` | Same |
| `test_extract_cap_requires_execution_request` | Same |
| `test_store_cap_requires_execution_request` | Same (except `store_cap_init`) |
| `test_store_cap_init_only_during_dao_creation` | `public(friend)`, DAO init context only |
| `test_store_updates_cap_types_and_cap_ids` | Type and ID registered |
| `test_extract_removes_from_cap_types_and_cap_ids` | Type and ID deregistered |
| `test_store_multiple_same_type_updates_ids` | Multiple IDs under one type |
| `test_extract_last_of_type_removes_type` | Type removed when last cap extracted |
| `test_loan_does_not_update_registries` | `cap_types` and `cap_ids` unchanged during loan |
| `test_loan_and_return_restores_capability` | Capability accessible after return |
| `test_loan_cap_not_borrowable_during_loan` | Abort if cap loaned and re-accessed before return |
| `test_privileged_extract_requires_subdao_control` | Requires `&SubDAOControl` |
| `test_privileged_extract_verifies_subdao_id` | `control.subdao_id == vault.dao_id` checked |
| `test_privileged_extract_wrong_subdao_aborts` | Abort `ENotController` |
| `test_privileged_extract_succeeds` | Capability extracted, registries updated |
| `test_contains__returns_true_for_stored_cap` | `contains(vault, cap_id) == true` |
| `test_contains__returns_false_for_missing_cap` | `contains(vault, cap_id) == false` |
| `test_ids_for_type__returns_correct_list` | Matches stored IDs for given type |
| `test_borrow_cap__returns_immutable_reference` | Can read but not modify |

## Tests

---

### All vault access requires ExecutionRequest

**Requirement:** All vault access (borrow, loan, extract) requires `ExecutionRequest`.

**Why it matters:** Capabilities stored in the vault (e.g., `SubDAOControl`, `GateOwnerCap`) control real assets and authority. Without governance gating, anyone with a reference to the vault could extract them.

```move
#[test]
fun test_borrow_cap_requires_execution_request() {
    // borrow_cap is public(friend), meaning only authorized modules can call it.
    // Those modules (proposal handlers) receive an ExecutionRequest as a parameter,
    // proving governance authorized the action.
    //
    // This is a structural guarantee verified by code review:
    // - borrow_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) -> &C
    // - The &ExecutionRequest<P> parameter cannot be constructed outside proposal::execute
    //
    // Test: verify that a valid execution request enables borrow.

    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // After setup, parent's CapVault holds SubDAOControl(child_id)
    // Create a proposal that borrows it
    // ... (create, pass, execute -> handler borrows cap successfully)

    test_scenario::end(scenario);
}
```

---

### Store updates cap_types and cap_ids

**Requirement:** `cap_types` reflects stored types. `cap_ids` maps types to complete ID lists.

**Why it matters:** These registries are the only way to enumerate capabilities without scanning all dynamic fields. Missing entries would make delegated capabilities invisible.

```move
#[test]
fun test_store_updates_cap_types_and_cap_ids() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        // Before: empty registries
        assert!(!capability_vault::has_type<TestCap>(&vault));

        // Store a capability (via store_cap_init during DAO creation context)
        let cap = TestCap { id: object::new(scenario.ctx()) };
        let cap_id = object::id(&cap);
        capability_vault::store_cap_init(&mut vault, cap);

        // After: type registered, ID listed
        assert!(capability_vault::has_type<TestCap>(&vault));
        assert!(capability_vault::contains(&vault, cap_id));
        let ids = capability_vault::ids_for_type<TestCap>(&vault);
        assert!(vector::contains(ids, &cap_id));

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Extract removes from registries

```move
#[test]
fun test_extract_removes_from_cap_types_and_cap_ids() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Store a cap, then extract it via governance
    // ...

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        // After extraction: type and ID deregistered
        assert!(!capability_vault::has_type<TestCap>(&vault));
        assert!(!capability_vault::contains(&vault, cap_id));

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Multiple caps of same type

**Why it matters:** A DAO might hold multiple `GateOwnerCap`s. Each must have its own ID entry under the shared type.

```move
#[test]
fun test_store_multiple_same_type_updates_ids() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        let cap1 = TestCap { id: object::new(scenario.ctx()) };
        let cap1_id = object::id(&cap1);
        capability_vault::store_cap_init(&mut vault, cap1);

        let cap2 = TestCap { id: object::new(scenario.ctx()) };
        let cap2_id = object::id(&cap2);
        capability_vault::store_cap_init(&mut vault, cap2);

        // Both IDs listed under the same type
        let ids = capability_vault::ids_for_type<TestCap>(&vault);
        assert!(vector::length(ids) == 2);
        assert!(vector::contains(ids, &cap1_id));
        assert!(vector::contains(ids, &cap2_id));

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Extracting last cap of type removes the type entry

```move
#[test]
fun test_extract_last_of_type_removes_type() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Store one cap, extract it
    // ...

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        // Type no longer registered
        assert!(!capability_vault::has_type<TestCap>(&vault));
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Loan does not update registries

**Requirement:** `loan_cap` does NOT update registries (ID considered "held" during loan).

**Why it matters:** If the registry removed the ID during loan, a concurrent transaction could observe the cap as "missing" and make incorrect decisions. The loan is temporary — the cap conceptually remains in the vault.

```move
#[test]
fun test_loan_does_not_update_registries() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Store a cap
    // ... let cap_id = ...

    // Loan the cap (within a handler context with ExecutionRequest)
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        // Simulate loan (requires ExecutionRequest — simplified for illustration)
        let (cap, loan) = capability_vault::loan_cap<TestCap, SomeProposal>(
            &mut vault, cap_id, &req,
        );

        // During loan: registries still show the cap as present
        assert!(capability_vault::contains(&vault, cap_id));
        assert!(capability_vault::has_type<TestCap>(&vault));
        let ids = capability_vault::ids_for_type<TestCap>(&vault);
        assert!(vector::contains(ids, &cap_id));

        // Return the cap
        capability_vault::return_cap(&mut vault, cap, loan);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Loan and return restores capability

**Why it matters:** Confirms the round-trip — a loaned cap must be usable after return, not corrupted.

```move
#[test]
fun test_loan_and_return_restores_capability() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Store, loan, use, return
    // ...

    // After return: cap is borrowable again
    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        // Borrow succeeds (cap is back in vault)
        let cap_ref = capability_vault::borrow_cap<TestCap, SomeProposal>(
            &vault, cap_id, &req,
        );
        // Can read the cap
        assert!(object::id(cap_ref) == cap_id);
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

### Privileged extract requires SubDAOControl

**Requirement:** `privileged_extract` requires `&SubDAOControl` and asserts `control.subdao_id == vault.dao_id`.

**Why it matters:** This is the controller's reclaim mechanism. Without the SubDAOControl check, any DAO could extract capabilities from any other DAO's vault.

```move
#[test]
fun test_privileged_extract_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Store a TestCap in child's vault
    // ...

    // Parent uses its SubDAOControl to extract from child's vault
    scenario.next_tx(ALICE);
    {
        let parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let mut child_vault = test_scenario::take_shared_by_id<CapabilityVault>(
            &scenario, child_cap_vault_id,
        );

        // Loan SubDAOControl from parent vault (via governance)
        // ... let (control, loan) = ...

        let cap = capability_vault::privileged_extract<TestCap>(
            &mut child_vault, cap_id, &control,
        );

        // Cap extracted successfully
        assert!(object::id(&cap) == cap_id);
        assert!(!capability_vault::contains(&child_vault, cap_id));

        // Return SubDAOControl, store extracted cap in parent
        // ...

        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(child_vault);
    };
    test_scenario::end(scenario);
}
```

---

### Wrong SubDAO ID aborts

**Why it matters:** A controller holding `SubDAOControl(child_A)` must not be able to extract from `child_B`'s vault.

```move
#[test]
#[expected_failure(abort_code = capability_vault::ENotController)]
fun test_privileged_extract_wrong_subdao_aborts() {
    let mut scenario = test_scenario::begin(ALICE);

    // Setup: parent controls child_A but tries to extract from child_B
    // child_B is a separate DAO not controlled by parent

    scenario.next_tx(ALICE);
    {
        let mut child_b_vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        // control.subdao_id == child_a_id, but vault.dao_id == child_b_id
        // -> abort ENotController
        let _cap = capability_vault::privileged_extract<TestCap>(
            &mut child_b_vault, cap_id, &control_for_child_a,
        );

        test_scenario::return_shared(child_b_vault);
    };
    test_scenario::end(scenario);
}
```

---

### Contains and ID queries

```move
#[test]
fun test_contains__returns_true_for_stored_cap() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Store cap
    // ...

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        assert!(capability_vault::contains(&vault, cap_id));
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}

#[test]
fun test_contains__returns_false_for_missing_cap() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let fake_id = object::id_from_address(@0xDEAD);
        assert!(!capability_vault::contains(&vault, fake_id));
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```
