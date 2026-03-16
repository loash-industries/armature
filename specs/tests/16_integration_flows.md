# Integration Flow Tests

## Summary

These tests map directly to the 21 demo steps across three flows from `02_demo_flows.md`. Each test validates a full step (or multi-step sequence) end-to-end, simulating what a user would do via PTBs on testnet.

---

## Flow A — One Vision, One Tribe (Scaling)

### Test Matrix

| Step | Test | What it validates |
|------|------|-------------------|
| A-1 | `test_flow_a__step1_alice_creates_dao` | Solo founder creates DAO with charter |
| A-2 | `test_flow_a__step2_recruit_via_set_board` | SetBoard adds Bob and Carol |
| A-3 | `test_flow_a__step3_pool_resources` | Permissionless deposits from all members |
| A-4 | `test_flow_a__step4_create_logistics_subdao` | CreateSubDAO proposal, child DAO created |
| A-5 | `test_flow_a__step5_subdao_structure_correct` | Parent holds SubDAOControl, child has board |
| A-6 | `test_flow_a__step6_subdao_sends_coin_autonomously` | SubDAO executes SendCoin without parent |
| A-7 | `test_flow_a__step7_parent_overrides_subdao_board` | privileged_submit replaces child board |
| — | `test_flow_a__full_sequence` | All 7 steps in order |

### Tests

---

#### A-1: Alice creates DAO

**Step:** Alice creates "Iron Haulers" with herself as sole board member and a charter on Walrus.

**Why it matters:** This is the entry point for the entire protocol. If DAO creation fails, nothing else works.

```move
#[test]
fun test_flow_a__step1_alice_creates_dao() {
    let mut scenario = test_scenario::begin(ALICE);

    // Create DAO with Alice as sole member
    scenario.next_tx(ALICE);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        dao::create_dao(
            vector[ALICE],
            b"Iron Haulers - mining and logistics tribe",
            b"walrus://ironhaulers_v1",
            b"sha256-of-iron-haulers-charter",
            &clock,
            scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
    };

    // Verify: DAO exists with correct state
    scenario.next_tx(ALICE);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        assert!(dao::status(&dao) == dao::status_active());

        let gov = dao::governance(&dao);
        assert!(governance::is_member(gov, ALICE));
        assert!(governance::seat_count(gov) == 1);

        // Charter exists with v1
        let charter = test_scenario::take_shared<Charter>(&scenario);
        assert!(charter::version(&charter) == 1);
        assert!(charter::current_blob_id(&charter) == b"walrus://ironhaulers_v1");

        test_scenario::return_shared(dao);
        test_scenario::return_shared(charter);
    };
    test_scenario::end(scenario);
}
```

---

#### A-2: Recruit via SetBoard

**Step:** Alice proposes SetBoard to add Bob and Carol. As sole member, her YES vote passes it.

```move
#[test]
fun test_flow_a__step2_recruit_via_set_board() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE]);

    // Propose SetBoard: [Alice] → [Alice, Bob, Carol]
    let prop_id = test_helpers::create_proposal(
        &mut scenario, dao_id,
        board_ops::new_set_board(vector[ALICE, BOB, CAROL], 3),
    );

    // Alice votes YES (sole member → instant pass)
    test_helpers::pass_proposal<board_ops::SetBoard>(
        &mut scenario, prop_id, vector[ALICE],
    );
    // Execute + handle SetBoard

    // Verify: board is now [Alice, Bob, Carol]
    scenario.next_tx(BOB);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let gov = dao::governance(&dao);
        assert!(governance::is_member(gov, ALICE));
        assert!(governance::is_member(gov, BOB));
        assert!(governance::is_member(gov, CAROL));
        assert!(governance::seat_count(gov) == 3);
        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```

---

#### A-3: Pool resources

**Step:** All three members deposit SUI. No proposal needed.

```move
#[test]
fun test_flow_a__step3_pool_resources() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Each member deposits 100 SUI
    let depositors = vector[ALICE, BOB, CAROL];
    let mut i = 0;
    while (i < 3) {
        scenario.next_tx(*vector::borrow(&depositors, i));
        {
            let mut vault = test_scenario::take_shared<TreasuryVault>(&scenario);
            let coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
            treasury::deposit(&mut vault, coin);
            test_scenario::return_shared(vault);
        };
        i = i + 1;
    };

    // Verify: treasury has 300 SUI
    scenario.next_tx(ALICE);
    {
        let vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        assert!(treasury::balance<SUI>(&vault) == 300);
        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

#### A-4/A-5: Create Logistics SubDAO

**Step:** Bob proposes CreateSubDAO. Alice and Bob vote YES, Carol abstains.

```move
#[test]
fun test_flow_a__step4_create_logistics_subdao() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_funded_dao(&mut scenario, 300);

    // Enable CreateSubDAO
    test_helpers::enable_proposal_type<subdao_ops::CreateSubDAO>(&mut scenario, dao_id);

    // Bob proposes CreateSubDAO
    scenario.next_tx(BOB);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        proposal::create(
            &dao,
            subdao_ops::new_create_subdao(
                vector[BOB, DAVE],     // initial board
                2,                       // seat_count
                b"Logistics Dept",       // metadata
                vector[],                // enabled_proposals (defaults)
                b"walrus://logistics_charter_v1",
                b"logistics-charter-hash",
            ),
            b"Create Logistics department",
            &clock,
            scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(dao);
    };

    // Alice: YES, Bob: YES (Carol abstains)
    // ... vote sequence

    // Execute + handle CreateSubDAO (includes 50 SUI funding)

    // Verify structure
    scenario.next_tx(ALICE);
    {
        // Parent treasury reduced by funding amount
        let parent_vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        assert!(treasury::balance<SUI>(&parent_vault) == 250);
        test_scenario::return_shared(parent_vault);

        // SubDAOControl in parent's cap vault
        let parent_cap_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        assert!(capability_vault::has_type<SubDAOControl>(&parent_cap_vault));
        test_scenario::return_shared(parent_cap_vault);
    };
    test_scenario::end(scenario);
}
```

---

#### A-6: SubDAO operates autonomously

**Step:** Bob proposes SendCoin on the Logistics SubDAO to pay Eve. No parent approval needed.

```move
#[test]
fun test_flow_a__step6_subdao_sends_coin_autonomously() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Fund child treasury
    // ...

    // On child DAO: Bob proposes SendCoin to Eve
    scenario.next_tx(BOB);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let clock = clock::create_for_testing(scenario.ctx());
        proposal::create(
            &child_dao,
            treasury_ops::new_send_coin<SUI>(EVE, 10),
            b"Pay hauler Eve",
            &clock,
            scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(child_dao);
    };

    // Bob and Dave (child board) vote YES
    // ...

    // Execute — no parent involvement
    // ...

    // Eve receives 10 SUI
    scenario.next_tx(EVE);
    {
        let coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&coin) == 10);
        test_scenario::return_to_sender(&scenario, coin);
    };
    test_scenario::end(scenario);
}
```

---

#### A-7: Parent overrides SubDAO board

**Step:** Dave goes inactive. Parent uses privileged_submit to replace Logistics board.

```move
#[test]
fun test_flow_a__step7_parent_overrides_subdao_board() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Parent proposes "replace child board" (internal proposal type)
    // ... create, pass on parent board

    // Execute: privileged_submit SetBoard on child
    // SetBoard payload: [Bob, Frank] (Dave removed, Frank added)
    // ...

    // Verify: child board is now [Bob, Frank]
    scenario.next_tx(ALICE);
    {
        let child_dao = test_scenario::take_shared_by_id<DAO>(&scenario, child_id);
        let gov = dao::governance(&child_dao);
        assert!(governance::is_member(gov, BOB));
        assert!(governance::is_member(gov, FRANK));
        assert!(!governance::is_member(gov, DAVE));
        test_scenario::return_shared(child_dao);
    };
    test_scenario::end(scenario);
}
```

---

## Flow B — The Gate Builders (Emergence)

### Test Matrix

| Step | Test | What it validates |
|------|------|-------------------|
| B-1 | `test_flow_b__step1_propose_gate_builders_subdao` | CreateSubDAO with charter describing revenue split |
| B-2 | `test_flow_b__step2_subdao_materializes` | Child created with 100 SUI funding |
| B-3 | `test_flow_b__step3_deploy_gate_caps_to_vault` | GateOwnerCaps stored in child CapVault |
| B-4 | `test_flow_b__step4_configure_gates_via_loan` | Caps loaned, configured, returned |
| B-5 | `test_flow_b__step5_tolls_accumulate` | Treasury balance increases from revenue |
| B-6 | `test_flow_b__step6_revenue_share_to_parent` | SendCoin transfers 80% to parent |
| B-7 | `test_flow_b__step7_charter_amendment_and_override` | AmendCharter on child, parent override via privileged_submit |
| — | `test_flow_b__full_sequence` | All 7 steps in order |

### Tests

---

#### B-3: Deploy gate caps to vault

**Step:** Dave deploys 3 gates and deposits ownership caps into Gate Builders' CapVault.

```move
#[test]
fun test_flow_b__step3_deploy_gate_caps_to_vault() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Dave creates 3 mock GateOwnerCaps and stores them in child vault
    scenario.next_tx(DAVE);
    {
        let mut vault = test_scenario::take_shared_by_id<CapabilityVault>(
            &scenario, /* child_vault_id */,
        );

        let cap1 = mock_gate::deploy(b"system_a", b"system_b", scenario.ctx());
        let cap1_id = object::id(&cap1);
        capability_vault::store_cap_init(&mut vault, cap1);

        let cap2 = mock_gate::deploy(b"system_b", b"system_c", scenario.ctx());
        capability_vault::store_cap_init(&mut vault, cap2);

        let cap3 = mock_gate::deploy(b"system_c", b"system_a", scenario.ctx());
        capability_vault::store_cap_init(&mut vault, cap3);

        // 3 GateOwnerCaps stored
        let ids = capability_vault::ids_for_type<mock_gate::GateOwnerCap>(&vault);
        assert!(vector::length(ids) == 3);

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

#### B-6: Revenue share to parent

**Step:** Eve proposes SendCoin to transfer 80% of tolls to parent treasury.

```move
#[test]
fun test_flow_b__step6_revenue_share_to_parent() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Fund child treasury (simulating toll revenue)
    scenario.next_tx(ALICE);
    {
        let mut child_vault = test_scenario::take_shared_by_id<TreasuryVault>(
            &scenario, /* child_vault_id */,
        );
        let coin = coin::mint_for_testing<SUI>(50, scenario.ctx());
        treasury::deposit(&mut child_vault, coin);
        test_scenario::return_shared(child_vault);
    };

    // Eve proposes SendCoin: 40 SUI (80% of 50) to parent treasury
    // ... create, pass, execute on child DAO

    // Verify: parent treasury increased, child treasury decreased
    scenario.next_tx(ALICE);
    {
        let parent_vault = test_scenario::take_shared<TreasuryVault>(&scenario);
        // Parent received 40 SUI (on top of existing balance)
        // ...
        test_scenario::return_shared(parent_vault);

        let child_vault = test_scenario::take_shared_by_id<TreasuryVault>(
            &scenario, /* child_vault_id */,
        );
        assert!(treasury::balance<SUI>(&child_vault) == 10); // 50 - 40
        test_scenario::return_shared(child_vault);
    };
    test_scenario::end(scenario);
}
```

---

## Flow C — Gate Network Franchise (Integration)

### Test Matrix

| Step | Test | What it validates |
|------|------|-------------------|
| 1 | `test_flow_c__step1_acquire_gate_caps` | GateOwnerCaps deposited in DAO vault |
| 2 | `test_flow_c__step2_propose_gate_config` | ConfigureGateAccess proposal created |
| 3 | `test_flow_c__step3_execute_gate_config_via_loan` | Caps loaned, hook set, caps returned |
| 4 | `test_flow_c__step4_toll_revenue_flows` | Revenue deposited into treasury |
| 5 | `test_flow_c__step5_third_party_reads` | On-chain state readable by external DApps |
| 6 | `test_flow_c__step6_delegate_gate_to_subdao` | TransferCapToSubDAO moves GateOwnerCap |
| 7 | `test_flow_c__step7_ssu_integration` | SSUOwnerCap stored, access controlled by membership |
| — | `test_flow_c__full_sequence` | All 7 steps in order |

### Tests

---

#### Step 3: Execute gate config via cap loan

**Step:** Execution loans GateOwnerCaps, calls gate::set_access_hook, returns caps.

**Why it matters:** Demonstrates the cap loan round-trip with a real (mocked) external contract call — the core value proposition of DAO-held capabilities.

```move
#[test]
fun test_flow_c__step3_execute_gate_config_via_loan() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Store a GateOwnerCap in vault
    // ... let gate_cap_id = ...

    // Enable a custom ConfigureGateAccess proposal type
    // ... (or use a generic "use cap" proposal pattern)

    // Create, pass, execute proposal
    // ...

    // In the handler PTB:
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        // Loan the gate cap
        let (gate_cap, loan) = capability_vault::loan_cap<mock_gate::GateOwnerCap, SomeType>(
            &mut vault, gate_cap_id, &req,
        );

        // Use it: configure the gate
        mock_gate::set_access_hook(&gate_cap, /* policy params */);

        // Return it
        capability_vault::return_cap(&mut vault, gate_cap, loan);

        // Cap is back in vault
        assert!(capability_vault::contains(&vault, gate_cap_id));

        test_scenario::return_shared(vault);
    };
    test_scenario::end(scenario);
}
```

---

#### Step 6: Delegate gate to SubDAO

**Step:** Parent transfers GateOwnerCap to Logistics SubDAO via TransferCapToSubDAO.

```move
#[test]
fun test_flow_c__step6_delegate_gate_to_subdao() {
    let mut scenario = test_scenario::begin(ALICE);
    let (parent_id, child_id) = test_helpers::setup_dao_with_subdao(&mut scenario);

    // Store GateOwnerCap in parent vault
    // ... let gate_cap_id = ...

    // Enable TransferCapToSubDAO on parent, propose, pass, execute
    // ...

    // Verify: cap moved from parent to child
    scenario.next_tx(ALICE);
    {
        let parent_vault = test_scenario::take_shared<CapabilityVault>(&scenario);
        assert!(!capability_vault::contains(&parent_vault, gate_cap_id));
        test_scenario::return_shared(parent_vault);

        let child_vault = test_scenario::take_shared_by_id<CapabilityVault>(
            &scenario, /* child_vault_id */,
        );
        assert!(capability_vault::contains(&child_vault, gate_cap_id));
        test_scenario::return_shared(child_vault);
    };

    // Parent can still reclaim via SubDAOControl
    // (verified in atomic reclaim test)
    test_scenario::end(scenario);
}
```

---

#### Step 7: SSU integration

**Step:** DAO deploys an SSU and stores its ownership cap. Access is controlled by membership.

```move
#[test]
fun test_flow_c__step7_ssu_integration() {
    let mut scenario = test_scenario::begin(ALICE);
    let dao_id = test_helpers::setup_dao(&mut scenario, vector[ALICE, BOB, CAROL]);

    // Deploy mock SSU
    scenario.next_tx(ALICE);
    {
        let mut vault = test_scenario::take_shared<CapabilityVault>(&scenario);

        let ssu_cap = mock_ssu::deploy(b"base_station_1", scenario.ctx());
        let ssu_cap_id = object::id(&ssu_cap);
        capability_vault::store_cap_init(&mut vault, ssu_cap);

        assert!(capability_vault::contains(&vault, ssu_cap_id));
        assert!(capability_vault::has_type<mock_ssu::SSUOwnerCap>(&vault));

        test_scenario::return_shared(vault);
    };

    // SSU access hook checks DAO membership
    // (mocked — in production this would be an on-chain callback)
    scenario.next_tx(BOB);
    {
        let dao = test_scenario::take_shared<DAO>(&scenario);
        let gov = dao::governance(&dao);

        // BOB is a member → access allowed
        assert!(governance::is_member(gov, BOB));
        // EVE is not a member → access denied
        assert!(!governance::is_member(gov, EVE));

        test_scenario::return_shared(dao);
    };
    test_scenario::end(scenario);
}
```
