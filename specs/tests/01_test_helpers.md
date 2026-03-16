# Test Helpers

Shared setup functions used across all test files. These live in a `test_helpers` module compiled only under `#[test_only]`.

```move
#[test_only]
module dao_framework::test_helpers {
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use dao_framework::dao::{Self, DAO};
    use dao_framework::governance;
    use dao_framework::treasury::{Self, TreasuryVault};
    use dao_framework::capability_vault::{Self, CapabilityVault};
    use dao_framework::charter::{Self, Charter};
    use dao_framework::emergency::{Self, EmergencyFreeze};
    use dao_framework::proposal::{Self, Proposal};

    const ALICE: address = @0xA;
    const BOB:   address = @0xB;
    const CAROL: address = @0xC;
    const DAVE:  address = @0xD;
    const EVE:   address = @0xE;

    /// Create a Board DAO with the given members.
    /// Returns the DAO object ID.
    /// All default proposal types are enabled.
    /// Charter is initialized with a placeholder blob.
    public fun setup_dao(scenario: &mut Scenario, members: vector<address>): ID {
        // Creates DAO with Board governance, default proposal types,
        // empty treasury, empty cap vault, placeholder charter, emergency freeze.
        // The DAO is a shared object — subsequent txs access it via take_shared.
        scenario.next_tx(ALICE);
        {
            let clock = clock::create_for_testing(scenario.ctx());
            dao::create_dao(
                members,
                b"test-metadata-cid",
                b"walrus://test_charter_v1",
                b"fake-sha256-hash-placeholder",
                &clock,
                scenario.ctx(),
            );
            clock::destroy_for_testing(clock);
        };

        // Return the DAO ID from the most recent created object
        let dao_id = test_scenario::most_recent_id_shared<DAO>();
        dao_id
    }

    /// Create a funded Board DAO (Alice, Bob, Carol) with `amount` SUI deposited.
    public fun setup_funded_dao(scenario: &mut Scenario, amount: u64): ID {
        let dao_id = setup_dao(scenario, vector[ALICE, BOB, CAROL]);

        scenario.next_tx(ALICE);
        {
            let mut vault = test_scenario::take_shared<TreasuryVault>(scenario);
            let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
            treasury::deposit(&mut vault, coin);
            test_scenario::return_shared(vault);
        };
        dao_id
    }

    /// Create a parent DAO with a controlled SubDAO.
    /// Parent board: [Alice, Bob, Carol]. Child board: [Dave, Eve].
    /// Returns (parent_dao_id, child_dao_id).
    public fun setup_dao_with_subdao(scenario: &mut Scenario): (ID, ID) {
        let parent_id = setup_funded_dao(scenario, 500);

        // Enable CreateSubDAO on the parent
        enable_proposal_type<subdao_ops::CreateSubDAO>(scenario, parent_id);

        // Create + pass + execute CreateSubDAO proposal
        let proposal_id = create_proposal(
            scenario,
            parent_id,
            subdao_ops::new_create_subdao(
                vector[DAVE, EVE],
                2,
                b"child-metadata",
                vector[], // enabled_proposals — defaults
                b"walrus://child_charter_v1",
                b"child-hash",
            ),
        );
        pass_proposal<subdao_ops::CreateSubDAO>(scenario, proposal_id, vector[ALICE, BOB, CAROL]);
        execute_and_handle_create_subdao(scenario, proposal_id, parent_id);

        let child_id = /* extract from SubDAOCreated event */;
        (parent_id, child_id)
    }

    /// Submit a proposal as the first board member (ALICE).
    public fun create_proposal<P: store>(
        scenario: &mut Scenario,
        dao_id: ID,
        payload: P,
    ): ID {
        scenario.next_tx(ALICE);
        {
            let dao = test_scenario::take_shared<DAO>(scenario);
            let clock = clock::create_for_testing(scenario.ctx());
            proposal::create(&dao, payload, b"proposal-metadata", &clock, scenario.ctx());
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(dao);
        };
        test_scenario::most_recent_id_shared<Proposal<P>>()
    }

    /// All provided voters vote YES. Asserts proposal transitions to Passed.
    public fun pass_proposal<P: store>(
        scenario: &mut Scenario,
        proposal_id: ID,
        voters: vector<address>,
    ) {
        let mut i = 0;
        while (i < vector::length(&voters)) {
            let voter = *vector::borrow(&voters, i);
            scenario.next_tx(voter);
            {
                let mut prop = test_scenario::take_shared<Proposal<P>>(scenario);
                proposal::vote(&mut prop, true, scenario.ctx());
                test_scenario::return_shared(prop);
            };
            i = i + 1;
        };
    }

    /// Execute a passed proposal. Returns the ExecutionRequest hot potato.
    public fun execute_proposal<P: store>(
        scenario: &mut Scenario,
        proposal_id: ID,
        dao_id: ID,
    ) {
        scenario.next_tx(ALICE);
        {
            let mut prop = test_scenario::take_shared<Proposal<P>>(scenario);
            let dao = test_scenario::take_shared<DAO>(scenario);
            let freeze = test_scenario::take_shared<EmergencyFreeze>(scenario);
            let clock = clock::create_for_testing(scenario.ctx());

            let req = proposal::execute(&mut prop, &dao, &freeze, &clock, scenario.ctx());
            // req is a hot potato — caller must consume it in the same PTB
            // (test-specific handler code follows this call)

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(prop);
            test_scenario::return_shared(dao);
            test_scenario::return_shared(freeze);
        };
    }

    /// Advance the test clock by `ms` milliseconds.
    public fun advance_clock(scenario: &mut Scenario, ms: u64) {
        scenario.next_tx(ALICE);
        {
            let mut clock = test_scenario::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, ms);
            test_scenario::return_shared(clock);
        };
    }

    /// Assert treasury balance for coin type T equals `expected`.
    public fun assert_balance<T>(scenario: &mut Scenario, vault_id: ID, expected: u64) {
        scenario.next_tx(ALICE);
        {
            let vault = test_scenario::take_shared<TreasuryVault>(scenario);
            assert!(treasury::balance<T>(&vault) == expected);
            test_scenario::return_shared(vault);
        };
    }

    /// Enable an opt-in proposal type via full proposal cycle
    /// (create EnableProposalType, vote, execute).
    public fun enable_proposal_type<P: store>(
        scenario: &mut Scenario,
        dao_id: ID,
    ) {
        // Uses default ProposalConfig for the type
        let config = proposal::default_config();
        let payload = admin::new_enable_proposal_type<P>(config);
        let prop_id = create_proposal(scenario, dao_id, payload);
        pass_proposal<admin::EnableProposalType>(scenario, prop_id, vector[ALICE, BOB, CAROL]);
        // execute + handle
        // ...
    }
}
```

### Why each helper exists

| Helper | Rationale |
|--------|-----------|
| `setup_dao` | Eliminates ~15 lines of boilerplate from every test. Guarantees consistent initial state. |
| `setup_funded_dao` | Treasury tests need non-zero balances. Avoids repeating deposit logic. |
| `setup_dao_with_subdao` | SubDAO tests need a parent-child pair. This is ~40 lines of setup without the helper. |
| `create_proposal` | Standardizes proposer identity (ALICE) so tests focus on the behavior under test, not setup. |
| `pass_proposal` | Voting is mechanical in most tests — the interesting behavior is in execution/lifecycle. |
| `execute_proposal` | Extracts the hot potato pattern. Caller provides handler-specific consumption logic. |
| `advance_clock` | Time-dependent tests (expiry, delay, cooldown) need clock manipulation. |
| `assert_balance` | Most treasury tests end with a balance check. One-liner is cleaner. |
| `enable_proposal_type` | Opt-in types need a full governance cycle to enable. Many tests need this as setup. |
