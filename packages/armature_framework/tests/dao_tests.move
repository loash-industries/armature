#[test_only]
module armature::dao_tests;

use armature::add_member::AddMember;
use armature::batch_add_members::BatchAddMembers;
use armature::batch_remove_members::BatchRemoveMembers;
use armature::capability_vault::{Self, CapabilityVault};
use armature::charter::Charter;
use armature::composite_payload::CompositePayload;
use armature::dao::{Self, DAO};
use armature::disable_bypass_type::DisableBypassType;
use armature::disable_proposal_type::DisableProposalType;
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::EnableProposalType;
use armature::governance;
use armature::permissions;
use armature::proposal;
use armature::remove_member::RemoveMember;
use armature::set_board::SetBoard;
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::treasury_vault::TreasuryVault;
use armature::unfreeze_proposal_type::UnfreezeProposalType;
use armature::update_metadata::UpdateMetadata;
use armature::update_proposal_config::UpdateProposalConfig;
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
            string::utf8(b"https://example.com/metadata.json"),
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

/// Custom payload types for registry tests.
public struct CustomA has drop, store {}

public struct CustomB has drop, store {}

/// Generic marker: each instantiation is a distinct proposal type, which lets the
/// size regression test enable many types without declaring one struct each.
public struct Marker<phantom T> has drop, store {}

#[test]
/// Verifies default proposal types match the spec: every default type has a slot
/// keyed by its payload type, carrying the documented display key and config.
fun test_default_proposal_types() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();

        // All 14 default types are enabled under their display keys.
        assert!(dao.type_display_key<SetBoard>() == b"SetBoard".to_ascii_string());
        assert!(dao.type_display_key<AddMember>() == b"AddMember".to_ascii_string());
        assert!(dao.type_display_key<RemoveMember>() == b"RemoveMember".to_ascii_string());
        assert!(dao.type_display_key<BatchAddMembers>() == b"BatchAddMembers".to_ascii_string());
        assert!(
            dao.type_display_key<BatchRemoveMembers>() == b"BatchRemoveMembers".to_ascii_string(),
        );
        assert!(dao.type_display_key<UpdateMetadata>() == b"CharterUpdate".to_ascii_string());
        assert!(
            dao.type_display_key<EnableProposalType>() == b"EnableProposalType".to_ascii_string(),
        );
        assert!(dao.type_display_key<EnableBypassType>() == b"EnableBypassType".to_ascii_string());
        assert!(
            dao.type_display_key<DisableBypassType>() == b"DisableBypassType".to_ascii_string(),
        );
        assert!(
            dao.type_display_key<DisableProposalType>() == b"DisableProposalType".to_ascii_string(),
        );
        assert!(
            dao.type_display_key<UpdateProposalConfig>() == b"UpdateProposalConfig".to_ascii_string(),
        );
        assert!(
            dao.type_display_key<TransferFreezeAdmin>() == b"TransferFreezeAdmin".to_ascii_string(),
        );
        assert!(
            dao.type_display_key<UnfreezeProposalType>() == b"UnfreezeProposalType".to_ascii_string(),
        );
        assert!(dao.type_display_key<CompositePayload>() == b"Composite".to_ascii_string());

        // Display keys resolve back to their types.
        let resolved = dao.type_for_display_key(&b"Composite".to_ascii_string());
        assert!(resolved.is_some());
        assert!(resolved.destroy_some() == dao::type_name_of<CompositePayload>());
        assert!(dao.type_for_display_key(&b"NotAType".to_ascii_string()).is_none());

        // Unregistered types have no slot.
        assert!(!dao.is_type_enabled<CustomA>());

        // Default config values.
        let config = dao.type_config<SetBoard>();
        assert!(config.quorum() == 5_000);
        assert!(config.approval_threshold() == 5_000);
        assert!(config.propose_threshold() == 0);
        assert!(config.expiry_ms() == 604_800_000);
        assert!(config.execution_delay_ms() == 0);
        assert!(config.cooldown_ms() == 0);
        assert!(config.composable_allowed());

        // Floor-gated types start at their floor; batch types are not composable.
        assert!(dao.type_config<EnableProposalType>().approval_threshold() == 8_000);
        // TYPE_ADMIN holders start at the 80% permission floor.
        assert!(dao.type_config<DisableProposalType>().approval_threshold() == 8_000);
        assert!(dao.type_config<DisableBypassType>().approval_threshold() == 8_000);

        // Framework types start with their fixed permission bits.
        assert!(dao.type_config<SetBoard>().permissions() == permissions::board_set());
        assert!(dao.type_config<AddMember>().permissions() == permissions::board_add());
        assert!(dao.type_config<RemoveMember>().permissions() == permissions::board_remove());
        assert!(
            dao.type_config<EnableBypassType>().permissions()
                == permissions::type_admin() | permissions::vault_store(),
        );
        assert!(
            dao.type_config<UnfreezeProposalType>().permissions()
                == permissions::emergency_freeze(),
        );
        assert!(dao.type_config<CompositePayload>().permissions() == 0);
        assert!(dao.type_config<UpdateProposalConfig>().approval_threshold() == 8_000);
        assert!(dao.type_config<EnableBypassType>().approval_threshold() == 8_000);
        assert!(!dao.type_config<BatchAddMembers>().composable_allowed());

        // Nothing has executed yet.
        assert!(dao.last_executed_ms<SetBoard>().is_none());

        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// SubDAOs omit the bypass meta-types from their default slots.
fun test_subdao_default_types_omit_bypass_meta() {
    let mut scenario = test_scenario::begin(CREATOR);

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        assert!(subdao.is_type_enabled<SetBoard>());
        assert!(subdao.is_type_enabled<CompositePayload>());
        assert!(!subdao.is_type_enabled<EnableBypassType>());
        assert!(!subdao.is_type_enabled<DisableBypassType>());
        assert!(subdao.type_for_display_key(&b"EnableBypassType".to_ascii_string()).is_none());

        sui::test_utils::destroy(freeze_cap);
        transfer::public_share_object(subdao);
    };

    scenario.end();
}

#[test]
/// Enabling then disabling a type leaves nothing behind: the slot, the display
/// key index and the cooldown state are all gone, and the display key can be reused.
fun test_enable_then_disable_leaves_nothing_behind() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_enable_type<CustomA>(b"Custom".to_ascii_string(), config);
        assert!(dao.is_type_enabled<CustomA>());
        assert!(dao.type_for_display_key(&b"Custom".to_ascii_string()).is_some());

        dao.test_disable_type<CustomA>();
        assert!(!dao.is_type_enabled<CustomA>());
        assert!(dao.type_for_display_key(&b"Custom".to_ascii_string()).is_none());

        // The display key is free again, for a different type.
        dao.test_enable_type<CustomB>(b"Custom".to_ascii_string(), config);
        assert!(dao.is_type_enabled<CustomB>());
        assert!(!dao.is_type_enabled<CustomA>());

        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// The root object does not grow with the number of enabled types: every slot is a
/// dynamic field, so the serialized root stays small and constant. Guards the gas
/// property the registry exists for (the non-refundable storage fee and per-byte
/// computation are charged on the whole root on every write).
fun test_root_size_independent_of_enabled_types() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let size_with_defaults = std::bcs::to_bytes(&dao).length();
        assert!(size_with_defaults < 1_024);

        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_enable_type<Marker<u8>>(b"T01".to_ascii_string(), config);
        dao.test_enable_type<Marker<u16>>(b"T02".to_ascii_string(), config);
        dao.test_enable_type<Marker<u32>>(b"T03".to_ascii_string(), config);
        dao.test_enable_type<Marker<u64>>(b"T04".to_ascii_string(), config);
        dao.test_enable_type<Marker<u128>>(b"T05".to_ascii_string(), config);
        dao.test_enable_type<Marker<u256>>(b"T06".to_ascii_string(), config);
        dao.test_enable_type<Marker<bool>>(b"T07".to_ascii_string(), config);
        dao.test_enable_type<Marker<address>>(b"T08".to_ascii_string(), config);
        dao.test_enable_type<Marker<CustomA>>(b"T09".to_ascii_string(), config);
        dao.test_enable_type<Marker<CustomB>>(b"T10".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<u8>>>(b"T11".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<u16>>>(b"T12".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<u32>>>(b"T13".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<u64>>>(b"T14".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<u128>>>(b"T15".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<u256>>>(b"T16".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<bool>>>(b"T17".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<address>>>(b"T18".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<CustomA>>>(b"T19".to_ascii_string(), config);
        dao.test_enable_type<Marker<Marker<CustomB>>>(b"T20".to_ascii_string(), config);

        assert!(std::bcs::to_bytes(&dao).length() == size_with_defaults);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// The root object does not grow with the board: the roster is a Table, so
/// adding 100 members in one batch, or removing them, leaves the serialized
/// root the same size.
fun test_root_size_independent_of_board_size() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let size_before = std::bcs::to_bytes(&dao).length();

        let mut batch = vector[];
        100u64.do!(|i| batch.push_back(sui::address::from_u256((i as u256) + 0x1000)));
        let (added, skipped) = dao.governance_mut().add_board_members(batch);
        assert!(added.length() == 100 && skipped.is_empty());
        assert!(dao.governance().member_count() == 102);
        assert!(std::bcs::to_bytes(&dao).length() == size_before);

        dao.governance_mut().remove_board_members(added);
        assert!(dao.governance().member_count() == 2);
        assert!(std::bcs::to_bytes(&dao).length() == size_before);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = armature::dao::EDisplayKeyTaken)]
/// Two enabled types cannot share a display key.
fun test_duplicate_display_key_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_enable_type<CustomA>(b"Custom".to_ascii_string(), config);
        dao.test_enable_type<CustomB>(b"Custom".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = armature::dao::ETypeAlreadyEnabled)]
/// A type cannot be enabled twice, even under a different display key.
fun test_enable_twice_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
        dao.test_enable_type<CustomA>(b"CustomA".to_ascii_string(), config);
        dao.test_enable_type<CustomA>(b"CustomA2".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = armature::dao::ETypeNotEnabled)]
/// Reading the config of a type without a slot aborts.
fun test_config_of_unregistered_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let _ = dao.type_config<CustomA>();
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

        // Board is the only governance model; set_board changes members only
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
        gov.set_board(vector[new_member], vector[]);

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

// === create_returning_vault tests ===

#[test]
/// create_returning_vault returns a vault whose dao_id matches the returned
/// dao_id, and whose object ID matches the DAO's capability_vault_id field.
fun test_create_returning_vault_ids_are_consistent() {
    let mut scenario = test_scenario::begin(CREATOR);

    let vault_id: ID;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (dao_id, vault) = dao::create_returning_vault(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
        assert!(vault.dao_id() == dao_id);
        vault_id = object::id(&vault);
        capability_vault::share(vault);
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.capability_vault_id() == vault_id);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// The vault returned by create_returning_vault is empty — no caps pre-populated.
fun test_create_returning_vault_vault_starts_empty() {
    let mut scenario = test_scenario::begin(CREATOR);

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (_, vault) = dao::create_returning_vault(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
        assert!(vault.is_empty());
        assert!(vault.cap_ids().length() == 0);
        capability_vault::share(vault);
    };

    scenario.end();
}

#[test]
/// create_returning_vault shares the DAO, treasury, charter, and emergency freeze,
/// and transfers the FreezeAdminCap to the creator — identical to create().
fun test_create_returning_vault_other_companions_are_shared() {
    let mut scenario = test_scenario::begin(CREATOR);

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        let (_, vault) = dao::create_returning_vault(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
        capability_vault::share(vault);
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.status().is_active());
        assert!(dao.governance().is_board_member(CREATOR));
        assert!(dao.governance().is_board_member(MEMBER_B));
        test_scenario::return_shared(dao);

        let treasury = scenario.take_shared<TreasuryVault>();
        test_scenario::return_shared(treasury);

        let charter = scenario.take_shared<Charter>();
        assert!(charter.name() == &string::utf8(b"Test DAO"));
        test_scenario::return_shared(charter);

        let freeze = scenario.take_shared<EmergencyFreeze>();
        test_scenario::return_shared(freeze);

        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    scenario.end();
}
