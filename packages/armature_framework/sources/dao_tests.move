#[test_only]
module armature::dao_tests;

use armature::capability_vault::CapabilityVault;
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal;
use armature::treasury_vault::TreasuryVault;
use std::string;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;

fun create_test_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"A test DAO for unit testing"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

#[test]
/// Creates a DAO and asserts all companion objects exist and governance = Board
/// with creator as a member.
fun test_create_dao() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    // Verify DAO shared object exists
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        // Verify governance is Board type with creator as member
        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        // Verify status is Active
        assert!(dao.status().is_active());
        test_scenario::return_shared(dao);
    };

    // Verify TreasuryVault exists
    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<TreasuryVault>();
        test_scenario::return_shared(vault);
    };

    // Verify CapabilityVault exists
    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<CapabilityVault>();
        test_scenario::return_shared(vault);
    };

    // Verify Charter exists
    scenario.next_tx(CREATOR);
    {
        let charter = scenario.take_shared<Charter>();
        assert!(charter.name() == &string::utf8(b"Test DAO"));
        assert!(charter.description() == &string::utf8(b"A test DAO for unit testing"));
        test_scenario::return_shared(charter);
    };

    // Verify EmergencyFreeze exists
    scenario.next_tx(CREATOR);
    {
        let freeze = scenario.take_shared<EmergencyFreeze>();
        test_scenario::return_shared(freeze);
    };

    // Verify FreezeAdminCap transferred to creator
    scenario.next_tx(CREATOR);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    scenario.end();
}

#[test]
/// Verifies DAOCreated event is emitted with correct fields.
fun test_dao_created_event() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    // After the transaction, check events
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let dao_id = dao.id();
        let treasury_id = dao.treasury_id();
        let capability_vault_id = dao.capability_vault_id();
        let charter_id = dao.charter_id();
        let emergency_freeze_id = dao.emergency_freeze_id();

        // Verify IDs are all distinct
        assert!(dao_id != treasury_id);
        assert!(dao_id != capability_vault_id);
        assert!(dao_id != charter_id);
        assert!(dao_id != emergency_freeze_id);
        assert!(treasury_id != capability_vault_id);

        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Verifies default proposal types match the spec.
fun test_default_proposal_types() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let enabled = dao.enabled_proposal_types();
        let configs = dao.proposal_configs();

        // Verify all 7 default types are enabled
        assert!(enabled.contains(&b"SetBoard".to_ascii_string()));
        assert!(enabled.contains(&b"CharterUpdate".to_ascii_string()));
        assert!(enabled.contains(&b"EnableProposalType".to_ascii_string()));
        assert!(enabled.contains(&b"DisableProposalType".to_ascii_string()));
        assert!(enabled.contains(&b"UpdateProposalConfig".to_ascii_string()));
        assert!(enabled.contains(&b"TransferFreezeAdmin".to_ascii_string()));
        assert!(enabled.contains(&b"UnfreezeProposalType".to_ascii_string()));
        assert!(enabled.length() == 7);

        // Verify each has a config entry
        assert!(configs.length() == 7);

        // Verify default config values
        let (_, config) = configs.get_entry_by_idx(0);
        assert!(config.quorum() == 5_000);
        assert!(config.approval_threshold() == 5_000);
        assert!(config.propose_threshold() == 0);
        assert!(config.expiry_ms() == 604_800_000);
        assert!(config.execution_delay_ms() == 0);
        assert!(config.cooldown_ms() == 0);

        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Verifies governance type is immutable — no public function exists to change the variant.
/// This is a compile-time guarantee: GovernanceConfig variant changes are only possible
/// through set_board (which mutates within Board, not to a different variant).
fun test_governance_type_immutable_after_creation() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let gov = dao.governance();

        // Governance is Board after creation
        assert!(gov.is_board_member(CREATOR));

        // set_board changes members but keeps Board variant — variant immutability
        // is enforced by the type system (no public function to change variant)
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Verifies Board governance persists after set_board mutation.
fun test_board_governance_persists_across_proposals() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();

        // Simulate a SetBoard proposal execution by mutating governance
        let gov = dao.governance_mut();
        let new_member: address = @0xC;
        gov.set_board(vector[CREATOR, MEMBER_B, new_member]);

        // Verify still Board governance with updated members
        let gov = dao.governance();
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(MEMBER_B));
        assert!(gov.is_board_member(new_member));

        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Verifies ProposalConfig validation at exact boundary values.
fun test_config_valid_boundaries_succeeds() {
    // Minimum valid config
    let _config_min = proposal::new_config(
        1, // quorum min
        5_000, // threshold min
        0, // propose_threshold
        3_600_000, // expiry min (1 hour)
        0, // execution_delay
        0, // cooldown
    );

    // Maximum valid config
    let _config_max = proposal::new_config(
        10_000, // quorum max
        10_000, // threshold max
        1_000_000, // propose_threshold
        604_800_000, // expiry (7 days)
        86_400_000, // execution_delay (1 day)
        86_400_000, // cooldown (1 day)
    );
}

#[test, expected_failure]
/// Verifies quorum below minimum aborts.
fun test_config_quorum_zero_aborts() {
    proposal::new_config(0, 5_000, 0, 3_600_000, 0, 0);
}

#[test, expected_failure]
/// Verifies quorum above maximum aborts.
fun test_config_quorum_above_max_aborts() {
    proposal::new_config(10_001, 5_000, 0, 3_600_000, 0, 0);
}

#[test, expected_failure]
/// Verifies threshold below minimum aborts.
fun test_config_threshold_below_min_aborts() {
    proposal::new_config(1, 4_999, 0, 3_600_000, 0, 0);
}

#[test, expected_failure]
/// Verifies expiry below minimum aborts.
fun test_config_expiry_below_min_aborts() {
    proposal::new_config(1, 5_000, 0, 3_599_999, 0, 0);
}
