#[test_only]
module armature::composite_tests;

use armature::composite::{Self, CompositeFrame};
use armature::composite_payload;
use armature::dao::{Self, DAO};
use armature::governance;
use std::string;
use sui::test_scenario;

const CREATOR: address = @0xA;

fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

#[test, expected_failure(abort_code = composite::ECompositeNesting)]
/// add_step aborts when the step payload is itself a CompositePayload: self-nesting
/// is detected from the Move type, not from a caller-supplied key. Lives in the
/// framework because `composite_payload::new` is package-private.
fun add_step_rejects_composite_nesting() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        let nested = composite_payload::new(
            object::id_from_address(@0xC0FFEE),
            vector[],
            vector[],
        );
        composite::add_step(&mut frame, &dao, nested);
        transfer::public_share_object(frame);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// The CompositeFrame records each step's display key from the DAO's slot.
fun add_step_records_slot_display_key() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step(&mut frame, &dao, armature::add_member::new(@0xB));
        let keys = frame.step_type_keys();
        assert!(keys.length() == 1);
        assert!(keys[0] == b"AddMember".to_ascii_string());
        assert!(frame.step_types()[0] == dao::type_name_of<armature::add_member::AddMember>());
        transfer::public_share_object(frame);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}
