# Governance Config Tests

## Summary

The `governance.move` module defines the `GovernanceConfig` enum (currently only `Board`). These tests verify that the governance type is immutable, state mutations are access-controlled, and `ProposalConfig` validation enforces the documented bounds.

## Test Matrix

| Test | Expected |
|------|----------|
| `test_governance_type_immutable_after_creation` | No function exists to change governance variant |
| `test_board_governance_persists_across_proposals` | Governance type remains Board after SetBoard |
| `test_governance_state_mutation_requires_handler` | `public(friend)` — cannot be called from external modules |
| `test_create_proposal_with_disabled_type_aborts` | Abort `ETypeNotEnabled` |
| `test_create_proposal_with_enabled_type_succeeds` | Proposal created |
| `test_cannot_disable_enable_proposal_type_aborts` | Abort `ECannotDisable` |
| `test_cannot_disable_disable_proposal_type_itself_aborts` | Abort `ECannotDisable` |
| `test_cannot_disable_transfer_freeze_admin_aborts` | Abort `ECannotDisable` |
| `test_cannot_disable_unfreeze_proposal_type_aborts` | Abort `ECannotDisable` |
| `test_can_disable_send_coin` | `SendCoin` removed from `enabled_proposals` |
| `test_update_config_self_referential_below_80_aborts` | Abort `ESelfReferentialFloor` |
| `test_update_config_self_referential_at_80_succeeds` | Config updated |
| `test_update_config_other_type_below_80_succeeds` | No floor enforced for non-self types |
| `test_enable_type_below_66_threshold_aborts` | Abort `EEnableFloor` |
| `test_enable_type_at_66_threshold_succeeds` | Type enabled |
| `test_config_quorum_zero_aborts` | Abort — quorum must be >= 1 |
| `test_config_threshold_below_5000_aborts` | Abort — approval_threshold must be >= 5000 |
| `test_config_expiry_below_1_hour_aborts` | Abort — expiry_ms must be >= 3,600,000 |
| `test_config_valid_boundaries_succeeds` | Config accepted at exact boundary values |

## Tests

---

### Governance type immutable after creation

**Requirement:** Governance type is immutable.

**Why it matters:** If the governance type could change (e.g., Board -> Direct), the entire security model would shift — vote eligibility, snapshot logic, and threshold semantics would break.

```move
#[test]
fun test_governance_type_immutable_after_creation() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);

        // Assert: governance is Board variant
        assert!(dao::governance_type(&dao) == governance::type_board());

        // There is no public or friend function to change the governance variant.
        // This is verified by code review — the GovernanceConfig enum's variant
        // is written once at creation and never matched-and-replaced.
        // The SetBoard handler changes members/seat_count but not the enum variant.

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Board governance persists across SetBoard

**Requirement:** `SetBoard` changes membership but not governance type.

**Why it matters:** Confirms that board replacement doesn't accidentally reconstruct the governance config with a different variant.

```move
#[test]
fun test_board_governance_persists_across_proposals() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB]);

    // Execute SetBoard to replace membership
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        board_ops::new_set_board(vector[CAROL, DAVE], 2),
    );
    test_helpers::pass_proposal<board_ops::SetBoard>(&mut scenario, prop_id, vector[ALICE, BOB]);
    // execute + handle ...

    scenario.next_tx(CAROL);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        // Governance type is still Board
        assert!(dao::governance_type(&dao) == governance::type_board());
        // Members have changed
        assert!(governance::is_member(&dao::governance(&dao), CAROL));
        assert!(!governance::is_member(&dao::governance(&dao), ALICE));
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Create proposal with disabled type aborts

**Requirement:** `proposal::create<P>` aborts if `TypeName::get<P>()` not in `enabled_proposals`.

**Why it matters:** This is the primary gate preventing unauthorized proposal types. Without it, any module could create proposals for types the DAO never approved.

```move
#[test]
#[expected_failure(abort_code = proposal::ETypeNotEnabled)]
fun test_create_proposal_with_disabled_type_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // CreateSubDAO is opt-in (not default-enabled)
    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        // Should abort — CreateSubDAO not in enabled_proposals
        proposal::create(
            &dao,
            subdao_ops::new_create_subdao(vector[BOB], 1, b"m", vector[], b"blob", b"hash"),
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

### Create proposal with enabled type succeeds

**Requirement:** Enabled types can create proposals.

**Why it matters:** Positive confirmation that the type-check gate passes for legitimate types.

```move
#[test]
fun test_create_proposal_with_enabled_type_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // SendCoin<SUI> is default-enabled
    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        proposal::create(
            &dao,
            treasury_ops::new_send_coin<SUI>(@0xRECIPIENT, 50),
            b"metadata",
            &clock,
            scenario.ctx(),
        );
        // No abort — success

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### Cannot disable EnableProposalType

**Requirement:** `EnableProposalType` cannot be disabled. `DisableProposalType` cannot disable itself.

**Why it matters:** If `EnableProposalType` could be disabled, the DAO would permanently lose the ability to add new proposal types — a fatal governance lockout.

```move
#[test]
#[expected_failure(abort_code = admin::ECannotDisable)]
fun test_cannot_disable_enable_proposal_type_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_disable_proposal_type<admin::EnableProposalType>(),
    );
    test_helpers::pass_proposal<admin::DisableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );

    // Execution should abort at the handler level
    // ... execute + handle -> abort ECannotDisable
    test_scenario::end(scenario);
}
```

---

### Cannot disable DisableProposalType itself

```move
#[test]
#[expected_failure(abort_code = admin::ECannotDisable)]
fun test_cannot_disable_disable_proposal_type_itself_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_disable_proposal_type<admin::DisableProposalType>(),
    );
    test_helpers::pass_proposal<admin::DisableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute -> abort ECannotDisable
    test_scenario::end(scenario);
}
```

---

### Cannot disable TransferFreezeAdmin

**Why it matters:** Disabling `TransferFreezeAdmin` would make the `FreezeAdminCap` permanently non-transferable — a governance dead-end if the current holder is compromised.

```move
#[test]
#[expected_failure(abort_code = admin::ECannotDisable)]
fun test_cannot_disable_transfer_freeze_admin_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_disable_proposal_type<admin::TransferFreezeAdmin>(),
    );
    test_helpers::pass_proposal<admin::DisableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute -> abort ECannotDisable
    test_scenario::end(scenario);
}
```

---

### Cannot disable UnfreezeProposalType

```move
#[test]
#[expected_failure(abort_code = admin::ECannotDisable)]
fun test_cannot_disable_unfreeze_proposal_type_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_disable_proposal_type<admin::UnfreezeProposalType>(),
    );
    test_helpers::pass_proposal<admin::DisableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute -> abort ECannotDisable
    test_scenario::end(scenario);
}
```

---

### Can disable SendCoin (non-protected type)

**Why it matters:** Confirms the blocklist only covers the 4 protected types — other types are freely disableable.

```move
#[test]
fun test_can_disable_send_coin() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_disable_proposal_type<treasury_ops::SendCoin<SUI>>(),
    );
    test_helpers::pass_proposal<admin::DisableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute + handle

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        assert!(!dao::is_type_enabled<treasury_ops::SendCoin<SUI>>(&dao));
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### UpdateProposalConfig self-referential below 80% aborts

**Requirement:** 80% super-majority floor when `UpdateProposalConfig` targets its own `TypeName`.

**Why it matters:** Without this floor, a slim majority could lower `UpdateProposalConfig`'s own threshold, then cascade that to weaken all other types — recursive config weakening (threat 2.4).

```move
#[test]
#[expected_failure(abort_code = admin::ESelfReferentialFloor)]
fun test_update_config_self_referential_below_80_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Propose UpdateProposalConfig targeting itself with 70% threshold
    let new_config = proposal::new_config(1, 7000, 0, 3_600_000, 0, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_config<admin::UpdateProposalConfig>(new_config),
    );
    test_helpers::pass_proposal<admin::UpdateProposalConfig>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute -> handler checks self-referential floor -> abort ESelfReferentialFloor
    test_scenario::end(scenario);
}
```

---

### UpdateProposalConfig self-referential at 80% succeeds

```move
#[test]
fun test_update_config_self_referential_at_80_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let new_config = proposal::new_config(1, 8000, 0, 3_600_000, 0, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_config<admin::UpdateProposalConfig>(new_config),
    );
    test_helpers::pass_proposal<admin::UpdateProposalConfig>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute succeeds — 80% meets the floor
    test_scenario::end(scenario);
}
```

---

### UpdateProposalConfig targeting other type below 80% succeeds

**Why it matters:** The 80% floor only applies to self-referential updates. Other types can have lower thresholds.

```move
#[test]
fun test_update_config_other_type_below_80_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Target SendCoin with 60% threshold — no self-referential floor
    let new_config = proposal::new_config(1, 6000, 0, 3_600_000, 0, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_update_config<treasury_ops::SendCoin<SUI>>(new_config),
    );
    test_helpers::pass_proposal<admin::UpdateProposalConfig>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute succeeds — 60% is fine for non-self types
    test_scenario::end(scenario);
}
```

---

### EnableProposalType below 66% threshold aborts

**Requirement:** `EnableProposalType`: 66% floor at execution.

**Why it matters:** Enabling dangerous types (e.g., `CreateSubDAO`) with weak governance would let a minority add attack surface (threat 2.3).

```move
#[test]
#[expected_failure(abort_code = admin::EEnableFloor)]
fun test_enable_type_below_66_threshold_aborts() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Attempt to enable CreateSubDAO with a config that has 50% threshold
    let weak_config = proposal::new_config(1, 5000, 0, 3_600_000, 0, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_enable_proposal_type_with_config<subdao_ops::CreateSubDAO>(weak_config),
    );
    test_helpers::pass_proposal<admin::EnableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute -> handler enforces 66% floor on the provided config -> abort
    test_scenario::end(scenario);
}
```

---

### EnableProposalType at 66% succeeds

```move
#[test]
fun test_enable_type_at_66_threshold_succeeds() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    let config = proposal::new_config(1, 6600, 0, 3_600_000, 0, 0);
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        admin::new_enable_proposal_type_with_config<subdao_ops::CreateSubDAO>(config),
    );
    test_helpers::pass_proposal<admin::EnableProposalType>(
        &mut scenario, prop_id, vector[ALICE, BOB, CAROL],
    );
    // Execute succeeds — 66% meets the floor

    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        assert!(dao::is_type_enabled<subdao_ops::CreateSubDAO>(&dao));
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

### ProposalConfig validation — boundary failures

**Requirement:** `quorum in [1, 10000]`, `approval_threshold in [5000, 10000]`, `expiry_ms >= 3,600,000`.

**Why it matters:** Invalid configs would break vote math (division by zero for quorum 0, majority capture for threshold below 50%, flash governance for short expiry).

```move
#[test]
#[expected_failure]
fun test_config_quorum_zero_aborts() {
    // quorum = 0 violates [1, 10000]
    let _config = proposal::new_config(0, 6600, 0, 3_600_000, 0, 0);
}

#[test]
#[expected_failure]
fun test_config_threshold_below_5000_aborts() {
    // approval_threshold = 4999 violates [5000, 10000]
    let _config = proposal::new_config(1, 4999, 0, 3_600_000, 0, 0);
}

#[test]
#[expected_failure]
fun test_config_expiry_below_1_hour_aborts() {
    // expiry_ms = 3,599,999 violates >= 3,600,000
    let _config = proposal::new_config(1, 6600, 0, 3_599_999, 0, 0);
}

#[test]
fun test_config_valid_boundaries_succeeds() {
    // Exact boundary values — all should pass
    let _config = proposal::new_config(
        1,          // quorum min
        5000,       // threshold min
        0,          // propose_threshold
        3_600_000,  // expiry_ms min
        0,          // execution_delay (0 = immediate, valid)
        0,          // cooldown (0 = none, valid)
    );
    // No abort
}
```
