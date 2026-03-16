# Admin Proposal Tests (6 types)

## Summary

The `proposals/admin.move` module handles 6 proposal types: `UpdateProposalConfig`, `EnableProposalType`, `DisableProposalType`, `UpdateMetadata`, `TransferFreezeAdmin`, and `UnfreezeProposalType`. These tests verify handler execution, safety rails (governance floors), and edge cases.

> Note: Governance floor tests (protected-type disable blocklist, self-referential config floor, enable threshold floor) are in `03_governance.md`. This file covers handler behavior and remaining admin-specific tests.

## Test Matrix

| Type | Test | Expected |
|------|------|----------|
| UpdateProposalConfig | `test_update_config__changes_config_for_target_type` | Config updated in `proposal_configs` table |
| UpdateProposalConfig | `test_update_config__does_not_affect_other_types` | Other types' configs unchanged |
| UpdateProposalConfig | `test_update_config__invalid_config_aborts` | Abort if new config violates validation bounds |
| EnableProposalType | `test_enable_type__adds_to_enabled_proposals` | Type added to `enabled_proposals` |
| EnableProposalType | `test_enable_type__sets_config_atomically` | `ProposalConfig` set alongside enable |
| EnableProposalType | `test_enable_type__already_enabled_aborts` | Abort — cannot double-enable |
| EnableProposalType | `test_enable_type__subdao_blocklist_enforced` | SubDAO cannot enable `SpawnDAO`/`SpinOutSubDAO`/`CreateSubDAO` |
| DisableProposalType | `test_disable_type__removes_from_enabled` | Type removed from `enabled_proposals` |
| DisableProposalType | `test_disable_type__already_disabled_no_op` | Idempotent or abort — design choice |
| UpdateMetadata | `test_update_metadata__changes_ipfs_cid` | `metadata_ipfs` updated |
| TransferFreezeAdmin | `test_transfer_freeze_admin__transfers_cap` | `FreezeAdminCap` transferred to new holder |
| TransferFreezeAdmin | `test_transfer_freeze_admin__cannot_be_frozen` | Execution succeeds even if other types frozen |
| UnfreezeProposalType | `test_unfreeze__removes_frozen_type` | Type removed from `frozen_types` |
| UnfreezeProposalType | `test_unfreeze__cannot_be_frozen` | Execution succeeds even if other types frozen |
| UnfreezeProposalType | `test_unfreeze__unfreezing_not_frozen_type_is_noop` | No abort on unfreezing non-frozen type |
| UpdateFreezeConfig | `test_update_freeze_config__changes_max_duration` | `max_freeze_duration_ms` updated |

## Tests

---

### UpdateProposalConfig: changes config for target type

**Why it matters:** This is how DAOs tune governance parameters post-creation. Verifies the config is actually written to the `proposal_configs` table.

```move
#[test]
fun test_update_config__changes_config_for_target_type() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Change SendCoin's expiry from default to 7200000 (2 hours)
    let new_config = proposal::new_config(1, 6600, 0, 7_200_000, 0, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_config<treasury_ops::SendCoin<SUI>>(new_config),
    );
    test_helpers::pass_proposal<admin::UpdateProposalConfig>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let config = dao::proposal_config<treasury_ops::SendCoin<SUI>>(&dao);
        assert!(proposal::config_expiry_ms(config) == 7_200_000);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### EnableProposalType: adds to enabled and sets config atomically

**Why it matters:** Atomic enablement + config prevents a window where a type is enabled but has no config (which would use defaults or abort).

```move
#[test]
fun test_enable_type__sets_config_atomically() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let config = proposal::new_config(1, 8000, 0, 7_200_000, 86_400_000, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_enable_proposal_type_with_config<charter_ops::AmendCharter>(config),
    );
    test_helpers::pass_proposal<admin::EnableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        // Type is enabled
        assert!(dao::is_type_enabled<charter_ops::AmendCharter>(&dao));
        // Config was set at the same time
        let config = dao::proposal_config<charter_ops::AmendCharter>(&dao);
        assert!(proposal::config_approval_threshold(config) == 8000);
        assert!(proposal::config_execution_delay_ms(config) == 86_400_000);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### EnableProposalType: SubDAO blocklist enforced

**Why it matters:** A controlled SubDAO enabling `CreateSubDAO` or `SpinOutSubDAO` could bypass the controller's authority — creating sub-SubDAOs or declaring independence without controller approval.

```move
#[test]
#[expected_failure(abort_code = subdao_ops::EBlockedType)]
fun test_enable_type__subdao_blocklist_enforced() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // On the SubDAO (child), attempt to enable CreateSubDAO
    // The child's controller_cap_id is Some(...) -> blocklist applies
    let config = proposal::new_config(1, 6600, 0, 3_600_000, 0, 0);
    scenario.next_tx(DAVE); // Dave is on child board
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let clock = clock::create_for_testing(scenario.ctx());

        // Should abort — CreateSubDAO is in SubDAO blocklist
        proposal::create(
            &child_dao,
            admin::new_enable_proposal_type_with_config<subdao_ops::CreateSubDAO>(config),
            b"metadata",
            &clock,
            scenario.ctx(),
        );

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}
```

---

### DisableProposalType: removes type

```move
#[test]
fun test_disable_type__removes_from_enabled() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Disable UpdateMetadata
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_disable_proposal_type<admin::UpdateMetadata>(),
    );
    test_helpers::pass_proposal<admin::DisableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        assert!(!dao::is_type_enabled<admin::UpdateMetadata>(&dao));
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### TransferFreezeAdmin: cannot be frozen

**Why it matters:** If TransferFreezeAdmin could be frozen, a compromised freeze admin could freeze everything (including the mechanism to transfer the cap away from them).

```move
#[test]
fun test_transfer_freeze_admin__cannot_be_frozen() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Freeze every freezable type
    // ...

    // TransferFreezeAdmin proposal should still be executable
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_transfer_freeze_admin(BOB),
    );
    test_helpers::pass_proposal<admin::TransferFreezeAdmin>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute succeeds despite other types being frozen
    test_scenario::end(scenario);
}
```

---

### UpdateMetadata: changes IPFS CID

```move
#[test]
fun test_update_metadata__changes_ipfs_cid() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_metadata(b"QmNewMetadataCID123"),
    );
    test_helpers::pass_proposal<admin::UpdateMetadata>(&mut scenario, prop_id, vector[ALICE]);
    // Execute + handle ...

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        assert!(dao::metadata_ipfs(&dao) == b"QmNewMetadataCID123");
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```
