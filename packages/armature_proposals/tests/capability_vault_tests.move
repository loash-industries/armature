#[test_only]
module armature_proposals::capability_vault_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::admin_ops;
use armature_proposals::enable_proposal_type::{Self, EnableProposalType};
use std::string;
use sui::clock;
use sui::test_scenario;

const OWNER: address = @0xA1;

public struct ForeignCap has key, store {
    id: UID,
}

#[test]
/// receive_cap stores a cap in a vault without checking dao_id match.
/// This enables cross-DAO capability transfers: a cap extracted from DAO A
/// can be received into DAO B's vault using B's ExecutionRequest.
fun receive_cap_cross_dao() {
    let mut scenario = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create a DAO — we'll receive a foreign cap into its vault
    let dao_id;
    scenario.next_tx(OWNER);
    {
        let init = governance::init_board(vector[OWNER]);
        dao_id =
            dao::create(
                &init,
                string::utf8(b"Receiving DAO"),
                string::utf8(b"Cross-DAO receive test"),
                string::utf8(b""),
                scenario.ctx(),
            );
    };

    // Submit a vehicle proposal to get an ExecutionRequest
    scenario.next_tx(OWNER);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        let config = proposal::new_config(5_000, 6_600, 0, 604_800_000, 0, 0);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            string::utf8(b"Vehicle for receive_cap"),
            enable_proposal_type::new(b"SomeType".to_ascii_string(), config),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(OWNER);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute: create a ForeignCap (simulating an asset from another DAO)
    // and store it via receive_cap (which doesn't check dao_id)
    scenario.next_tx(OWNER);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Create a cap that doesn't belong to this DAO
        let foreign = ForeignCap { id: object::new(scenario.ctx()) };
        let foreign_id = object::id(&foreign);

        // receive_cap accepts caps regardless of origin DAO — key difference
        // from store_cap which asserts dao_id == req.req_dao_id()
        vault.receive_cap(foreign, &request);

        // Verify cap is stored in the vault
        assert!(vault.contains(foreign_id));

        // Consume the request via the handler
        admin_ops::execute_enable_proposal_type(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
