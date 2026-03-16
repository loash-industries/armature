# SubDAO Operations Tests

## Summary

The `proposals/subdao_ops.move` module handles 6 proposal types: `CreateSubDAO`, `SpinOutSubDAO`, `TransferCapToSubDAO`, `ReclaimCapFromSubDAO`, `PauseSubDAOExecution`, and `UnpauseSubDAOExecution`. These tests verify hierarchy invariants, control semantics, and atomic reclaim.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_subdao_cannot_enable_spawn_dao_aborts` | Abort `EBlockedType` |
| `test_subdao_cannot_enable_spinout_aborts` | Abort `EBlockedType` |
| `test_subdao_cannot_enable_create_subdao_aborts` | Abort `EBlockedType` |
| `test_controller_cap_id_set_at_creation` | `controller_cap_id == Some(control_id)` |
| `test_controller_cap_id_cleared_at_spinout` | `controller_cap_id == None` |
| `test_only_one_control_per_subdao` | Cannot create duplicate `SubDAOControl` |
| `test_pause_requires_privileged_submit` | Pause only via controller with `SubDAOControl` |
| `test_unpause_requires_privileged_submit` | Unpause only via controller |
| `test_paused_subdao_cannot_execute_aborts` | Abort `EControllerPaused` on any type |
| `test_paused_subdao_can_still_create_proposals` | Create succeeds (only execute blocked) |
| `test_spinout_clears_paused_flag` | `controller_paused = false` after spinout |
| `test_acyclic_graph_enforced` | Cannot transfer SubDAOControl to a DAO that controls the transferrer |
| `test_each_subdao_has_at_most_one_controller` | Each SubDAO has at most one controller |
| `test_create_subdao__creates_child_with_board` | Child DAO created with specified board |
| `test_create_subdao__stores_control_in_parent_vault` | `SubDAOControl` in parent's `CapabilityVault` |
| `test_create_subdao__excludes_hierarchy_types` | Child does not have `CreateSubDAO` etc. enabled |
| `test_create_subdao__funds_child_treasury` | Child treasury funded from parent |
| `test_create_subdao__emits_subdao_created_event` | `SubDAOCreated` event |
| `test_spinout__destroys_control` | `SubDAOControl` consumed and gone |
| `test_spinout__enables_hierarchy_types` | `SpawnDAO`, `CreateSubDAO`, `SpinOutSubDAO` now enableable |
| `test_spinout__emits_subdao_spun_out_event` | `SubDAOSpunOut` event |
| `test_transfer_cap__moves_cap_to_subdao_vault` | Cap in child's vault, removed from parent's |
| `test_transfer_cap__requires_subdao_control` | Must hold `SubDAOControl` for target |
| `test_reclaim_cap__returns_cap_to_parent` | Cap back in parent's vault |
| `test_atomic_reclaim__full_sequence` | Pause -> SetBoard -> extract -> unpause in one test |

## Tests

---

### SubDAO cannot enable hierarchy-altering types

**Requirement:** Controlled SubDAO cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO`.

**Why it matters:** If a SubDAO could create its own SubDAOs, it could transfer the controller's delegated capabilities downward, effectively laundering authority outside the controller's reach.

```move
#[test]
#[expected_failure(abort_code = subdao_ops::EBlockedType)]
fun test_subdao_cannot_enable_create_subdao_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // On child DAO, attempt to enable CreateSubDAO
    scenario.next_tx(DAVE); // Dave is on child board
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let clock = clock::create_for_testing(scenario.ctx());

        let config = proposal::new_config(1, 6600, 0, 3_600_000, 0, 0);
        // The create or handler should check the blocklist
        proposal::create(
            &child_dao,
            admin::new_enable_proposal_type_with_config<subdao_ops::CreateSubDAO>(config),
            b"try to enable",
            &clock,
            scenario.ctx(),
        ); // abort EBlockedType

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = subdao_ops::EBlockedType)]
fun test_subdao_cannot_enable_spinout_aborts() {
    // Same pattern — SpinOutSubDAO is blocked
    // ...
}
```

---

### controller_cap_id set at creation

**Requirement:** `controller_cap_id` set at creation, cleared at spinout.

**Why it matters:** This is the on-chain proof of the control relationship. Without it, the SubDAO can't verify who its controller is.

```move
#[test]
fun test_controller_cap_id_set_at_creation() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);

        // controller_cap_id is Some(...)
        assert!(option::is_some(&dao::controller_cap_id(&child_dao)));

        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}
```

---

### controller_cap_id cleared at spinout

```move
#[test]
fun test_controller_cap_id_cleared_at_spinout() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Enable SpinOutSubDAO on parent
    test_helpers::enable_proposal_type<subdao_ops::SpinOutSubDAO>(&mut scenario, parent_id);

    // Propose and execute SpinOutSubDAO
    let prop_id = test_helpers::create_proposal(
        &mut scenario, parent_id,
        subdao_ops::new_spinout_subdao(child_id),
    );
    test_helpers::pass_proposal<subdao_ops::SpinOutSubDAO>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle: destroys SubDAOControl, clears child's controller_cap_id

    scenario.next_tx(ALICE);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);

        // controller_cap_id is None — child is now independent
        assert!(option::is_none(&dao::controller_cap_id(&child_dao)));

        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}
```

---

### Paused SubDAO cannot execute any proposal type

**Requirement:** When `controller_paused == true`, `proposal::execute` aborts for all types.

**Why it matters:** Complete execution freeze is essential for atomic reclaim. Any gap (e.g., allowing "safe" types during pause) could be exploited by a rogue board to exfiltrate assets.

```move
#[test]
#[expected_failure(abort_code = proposal::EControllerPaused)]
fun test_paused_subdao_cannot_execute_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Parent pauses child via privileged_submit + PauseSubDAOExecution
    // ...

    // On child: create and pass a harmless proposal (UpdateMetadata)
    scenario.next_tx(DAVE);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let clock = clock::create_for_testing(scenario.ctx());
        proposal::create(
            &child_dao,
            admin::new_update_metadata(b"new"),
            b"m",
            &clock,
            scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(child_dao);
    };
    // Pass it
    // ...

    // Attempt to execute — abort EControllerPaused
    scenario.next_tx(DAVE);
    {
        let mut prop = test_scenario::take_shared<Proposal<admin::UpdateMetadata>>(&scenario);
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let freeze = test_scenario::take_shared<EmergencyFreeze>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let _req = proposal::execute(&mut prop, &child_dao, &freeze, &clock, scenario.ctx());
        // ^ aborts EControllerPaused

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(prop);
        test_scenario::return_shared(child_dao);
        test_scenario::return_shared(freeze);
    };
    test_scenario::end(scenario);
}
```

---

### SpinOut clears paused flag

**Requirement:** `SpinOutSubDAO` clears `controller_paused` to `false`.

**Why it matters:** A newly independent DAO must be fully functional. If the pause flag persisted after spinout, the DAO would be permanently frozen with no controller to unpause it.

```move
#[test]
fun test_spinout_clears_paused_flag() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Parent pauses child
    // ...

    // Parent spins out child
    // ...

    scenario.next_tx(DAVE);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        assert!(!dao::controller_paused(&child_dao));
        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}
```

---

### CreateSubDAO: stores SubDAOControl in parent vault

**Why it matters:** The `SubDAOControl` must end up in the parent's `CapabilityVault` — not transferred to an address, not dropped. Without it, the parent has no mechanism to control the child.

```move
#[test]
fun test_create_subdao__stores_control_in_parent_vault() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        // SubDAOControl for child_id should be in parent's vault
        assert!(capability_vault::has_type<subdao_ops::SubDAOControl>(&parent_vault));
        // The control's subdao_id should match child_id
        // ...

        test_scenario::return_shared(parent_vault);
    };
    test_scenario::end(scenario);
}
```

---

### TransferCapToSubDAO: moves cap to child vault

**Why it matters:** Capability delegation is how DAOs distribute authority downward. The cap must leave the parent's vault and enter the child's vault atomically.

```move
#[test]
fun test_transfer_cap__moves_cap_to_subdao_vault() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Store a TestCap in parent's vault
    // ... let cap_id = ...

    // Enable TransferCapToSubDAO, propose, pass, execute
    // ...

    scenario.next_tx(ALICE);
    {
        let parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let child_vault = test_scenario::take_shared_by_id<CapabilityVault>(
            &scenario, /* child_vault_id */,
        );

        // Cap no longer in parent vault
        assert!(!capability_vault::contains(&parent_vault, cap_id));
        // Cap now in child vault
        assert!(capability_vault::contains(&child_vault, cap_id));

        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(child_vault);
    };
    test_scenario::end(scenario);
}
```

---

### Atomic Reclaim: full sequence

**Why it matters:** This is the emergency override mechanism (threat 2.6). The entire sequence must complete atomically — any gap allows the compromised board to preemptively move capabilities.

```move
#[test]
fun test_atomic_reclaim__full_sequence() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Transfer a valuable cap (GateOwnerCap) to child
    // ... let gate_cap_id = ...

    // Parent executes atomic reclaim in a single PTB:
    //
    // Step 1: PauseSubDAOExecution (via privileged_submit)
    //   -> child.controller_paused = true
    //   -> child cannot execute any proposals
    //
    // Step 2: SetBoard (via privileged_submit)
    //   -> child board replaced with trusted members
    //   -> old compromised board immediately loses governance rights
    //
    // Step 3: privileged_extract(child_vault, gate_cap_id, &control)
    //   -> GateOwnerCap extracted from child's vault to parent
    //   -> no governance approval needed on child (that's the point)
    //
    // Step 4: UnpauseSubDAOExecution (via privileged_submit)
    //   -> child.controller_paused = false
    //   -> child resumes normal operations with new board

    // Verify final state
    scenario.next_tx(ALICE);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        let child_vault = test_scenario::take_shared_by_id<CapabilityVault>(
            &scenario, /* child_vault_id */,
        );

        // Child is unpaused
        assert!(!dao::controller_paused(&child_dao));

        // Cap is back in parent's vault
        assert!(capability_vault::contains(&parent_vault, gate_cap_id));
        assert!(!capability_vault::contains(&child_vault, gate_cap_id));

        // Child board was replaced
        let gov = dao::governance(&child_dao);
        assert!(!governance::is_member(gov, DAVE)); // old compromised member
        assert!(governance::is_member(gov, FRANK)); // new trusted member

        test_scenario::return_shared(child_dao);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(child_vault);
    };
    test_scenario::end(scenario);
}
```
