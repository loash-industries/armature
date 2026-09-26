#[test_only]
module armature_proposals::capability_vault_tests;

use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::governance;
use armature::permissions;
use armature::proposal;
use std::string;
use sui::test_scenario;

const OWNER: address = @0xA1;

/// Payload type of the sending DAO's request.
public struct SomeType has drop, store {}

public struct ForeignCap has key, store {
    id: UID,
}

fun create_dao(scenario: &mut test_scenario::Scenario): ID {
    scenario.next_tx(OWNER);
    let init = governance::init_board(vector[OWNER]);
    dao::create(&init, string::utf8(b"Receiving DAO"), string::utf8(b""), scenario.ctx())
}

#[test]
/// receive_cap stores a cap in a vault without checking dao_id match: a cap
/// extracted from DAO A is received into DAO B's vault on A's request. The
/// sending request must carry VAULT_EXTRACT.
fun receive_cap_cross_dao() {
    let mut scenario = test_scenario::begin(OWNER);
    let dao_id = create_dao(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());

        // A request from another DAO that may move caps out of its vault.
        let sender_dao = object::id_from_address(@0x5E);
        let req = proposal::new_permitted_request_for_testing<SomeType>(
            sender_dao,
            object::id_from_address(@0x1),
            permissions::vault_extract(),
        );

        let foreign = ForeignCap { id: object::new(scenario.ctx()) };
        let foreign_id = object::id(&foreign);
        vault.receive_cap(foreign, &req);
        assert!(vault.contains(foreign_id));

        proposal::consume_execution_request_for_testing(req);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
/// A sending request without VAULT_EXTRACT cannot push a cap into a vault.
fun receive_cap_without_vault_extract_aborts() {
    let mut scenario = test_scenario::begin(OWNER);
    let dao_id = create_dao(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());
        let req = proposal::new_permitted_request_for_testing<SomeType>(
            object::id_from_address(@0x5E),
            object::id_from_address(@0x1),
            permissions::vault_store(),
        );
        vault.receive_cap(ForeignCap { id: object::new(scenario.ctx()) }, &req);
        abort 0
    }
}
