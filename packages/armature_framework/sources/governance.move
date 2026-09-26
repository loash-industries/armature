module armature::governance;

use sui::table::{Self, Table};
use sui::vec_set;

// === Errors ===

const EEmptyBoard: u64 = 0;
const EDuplicateBoardMember: u64 = 1;
const ENotBoardMember: u64 = 2;
/// set_board called with nothing to add and nothing to remove.
const ENoBoardChange: u64 = 3;

// === Constants ===

/// Vote weight of each board member. Every Board vote path reads it from here.
const BOARD_MEMBER_VOTE_WEIGHT: u64 = 1;

/// Board governance: one member, one vote. The roster may be mutated by
/// authorized proposal handlers.
///
/// The roster lives in a `Table`, not inline, so the DAO root's size does not
/// grow with the board: Sui charges the non-refundable storage fee and per-byte
/// computation on the whole object on every write.
///
/// The roster is versioned. `roster_version` increments once per membership
/// change (a single add or remove, or a whole batch), and every member records
/// the versions at which they joined and left. A proposal stores the version
/// current at its creation instead of copying the roster, and eligibility to
/// vote on it is "was a member at that version" (see `was_member_at`).
/// Members who leave therefore keep their entry: deleting it would make
/// proposals created while they were a member unverifiable.
///
/// Board is the only governance model. A weighted model would need each
/// member's weight at every past version, which this layout does not keep.
public struct GovernanceConfig has store {
    members: Table<address, Member>,
    member_count: u64,
    roster_version: u64,
}

/// Membership history of one address. One tenure per stint on the board, in
/// order; only the last may be open. Kept after the address leaves.
public struct Member has drop, store {
    tenures: vector<Tenure>,
}

/// One stint on the board: a member from roster version `joined` until
/// version `left` (exclusive), or still a member if `left` is none.
public struct Tenure has copy, drop, store {
    joined: u64,
    left: Option<u64>,
}

/// Initialization payload for creating a DAO with a specific governance model.
/// Consumed once during DAO creation.
public enum GovernanceTypeInit has copy, drop, store {
    InitBoard { initial_members: vector<address> },
}

// === GovernanceTypeInit constructors ===

/// Create an InitBoard payload for DAO creation.
public fun init_board(initial_members: vector<address>): GovernanceTypeInit {
    GovernanceTypeInit::InitBoard { initial_members }
}

/// The initial board members listed in an init payload.
public fun init_members(self: &GovernanceTypeInit): vector<address> {
    match (self) {
        GovernanceTypeInit::InitBoard { initial_members } => *initial_members,
    }
}

// === GovernanceConfig constructors ===

/// Create a Board governance config from an InitBoard payload. Initial members
/// join at roster version 0.
public(package) fun new_board(init: &GovernanceTypeInit, ctx: &mut TxContext): GovernanceConfig {
    let initial_members = init.init_members();
    assert!(initial_members.length() > 0, EEmptyBoard);
    assert_no_duplicates(&initial_members);
    let mut members = table::new<address, Member>(ctx);
    initial_members.do!(|addr| join(&mut members, addr, 0));
    GovernanceConfig {
        members,
        member_count: initial_members.length(),
        roster_version: 0,
    }
}

/// Destroy the config. The roster's entries are dropped with the table and
/// their storage deposits are not returned: a Table cannot be enumerated.
public(package) fun destroy(self: GovernanceConfig) {
    let GovernanceConfig { members, .. } = self;
    members.drop();
}

// === GovernanceConfig accessors ===

/// Returns true if addr is a current board member.
public fun is_board_member(self: &GovernanceConfig, addr: address): bool {
    if (!self.members.contains(addr)) return false;
    let tenures = &self.members[addr].tenures;
    tenures[tenures.length() - 1].left.is_none()
}

/// Returns true if addr was a board member at roster version `version`. A
/// member who joined at `version` counts; one who left at `version` does not.
public fun was_member_at(self: &GovernanceConfig, addr: address, version: u64): bool {
    if (!self.members.contains(addr)) return false;
    self
        .members[addr]
        .tenures
        .any!(|t| t.joined <= version && (t.left.is_none() || *t.left.borrow() > version))
}

/// Number of current board members.
public fun member_count(self: &GovernanceConfig): u64 { self.member_count }

/// Current roster version. Increments once per membership change.
public fun roster_version(self: &GovernanceConfig): u64 { self.roster_version }

/// Vote weight of every board member.
public fun member_vote_weight(): u64 { BOARD_MEMBER_VOTE_WEIGHT }

/// Assert that addr is a current board member.
public(package) fun assert_board_member(self: &GovernanceConfig, addr: address) {
    assert!(self.is_board_member(addr), ENotBoardMember);
}

/// Weight `addr` votes with. Aborts with ENotBoardMember if `addr` is not a
/// current board member.
public(package) fun board_vote_weight(self: &GovernanceConfig, addr: address): u64 {
    self.assert_board_member(addr);
    BOARD_MEMBER_VOTE_WEIGHT
}

/// Total vote weight of the current board.
public(package) fun board_vote_total_weight(self: &GovernanceConfig): u64 {
    self.member_count() * BOARD_MEMBER_VOTE_WEIGHT
}

/// Returns the voting weight of addr in this governance config. Aborts with
/// ENotBoardMember if addr is not a current board member.
public(package) fun proposer_weight(self: &GovernanceConfig, addr: address): u64 {
    self.board_vote_weight(addr)
}

// === GovernanceConfig mutators ===

/// Add `to_add` to and remove `to_remove` from the board as one roster change.
/// Aborts if both lists are empty, if an address appears twice across the two
/// lists, if an address to add is already a member, if an address to remove is
/// not a member, or if the board would be left empty. All checks run before
/// any mutation.
public(package) fun set_board(
    self: &mut GovernanceConfig,
    to_add: vector<address>,
    to_remove: vector<address>,
) {
    assert!(!to_add.is_empty() || !to_remove.is_empty(), ENoBoardChange);
    let mut all = to_add;
    all.append(to_remove);
    assert_no_duplicates(&all);
    to_add.do_ref!(|addr| assert!(!self.is_board_member(*addr), EDuplicateBoardMember));
    to_remove.do_ref!(|addr| self.assert_board_member(*addr));
    assert!(self.member_count() + to_add.length() > to_remove.length(), EEmptyBoard);

    let GovernanceConfig { members, member_count, roster_version } = self;
    let version = *roster_version + 1;
    to_remove.do!(|addr| leave(members, addr, version));
    to_add.do!(|addr| join(members, addr, version));
    *member_count = *member_count + to_add.length() - to_remove.length();
    *roster_version = version;
}

/// Add a single member to the board. Aborts if already present.
public(package) fun add_board_member(self: &mut GovernanceConfig, member: address) {
    assert!(!self.is_board_member(member), EDuplicateBoardMember);
    let GovernanceConfig { members, member_count, roster_version } = self;
    *roster_version = *roster_version + 1;
    join(members, member, *roster_version);
    *member_count = *member_count + 1;
}

/// Add multiple members to the board, skipping any address that is already
/// present. Aborts only on **internal duplicates** within `new_members`
/// (the same address listed twice in the input vector) — that case is
/// treated as proposer error, not benign overlap with current membership.
///
/// Returns (added, skipped): the addresses actually inserted and the
/// addresses that were already on the board, both in input order. The
/// caller is expected to surface `skipped` in its event so the on-chain
/// record reflects what actually happened, not just proposer intent.
/// The roster version advances once for the batch, and only if anything
/// was added.
public(package) fun add_board_members(
    self: &mut GovernanceConfig,
    new_members: vector<address>,
): (vector<address>, vector<address>) {
    assert_no_duplicates(&new_members);
    let (skipped, added) = new_members.partition!(|addr| self.is_board_member(*addr));
    if (!added.is_empty()) {
        let GovernanceConfig { members, member_count, roster_version } = self;
        let version = *roster_version + 1;
        added.do_ref!(|addr| join(members, *addr, version));
        *member_count = *member_count + added.length();
        *roster_version = version;
    };
    (added, skipped)
}

/// Remove multiple members from the board atomically. Aborts if the input
/// contains duplicates, if any address is not on the board, or if removal
/// would leave the board empty. All checks run before any mutation.
public(package) fun remove_board_members(
    self: &mut GovernanceConfig,
    members_to_remove: vector<address>,
): vector<address> {
    assert_no_duplicates(&members_to_remove);
    members_to_remove.do_ref!(|addr| self.assert_board_member(*addr));
    assert!(self.member_count() > members_to_remove.length(), EEmptyBoard);

    let GovernanceConfig { members, member_count, roster_version } = self;
    let version = *roster_version + 1;
    members_to_remove.do_ref!(|addr| leave(members, *addr, version));
    *member_count = *member_count - members_to_remove.length();
    *roster_version = version;
    members_to_remove
}

/// Remove a single member from the board. Aborts if not present or if
/// removal would leave the board empty.
public(package) fun remove_board_member(self: &mut GovernanceConfig, member: address) {
    self.assert_board_member(member);
    assert!(self.member_count() > 1, EEmptyBoard);
    let GovernanceConfig { members, member_count, roster_version } = self;
    *roster_version = *roster_version + 1;
    leave(members, member, *roster_version);
    *member_count = *member_count - 1;
}

// === Internal ===

/// Open a tenure for `addr` at `version`. The caller has checked that `addr`
/// is not a current member.
fun join(members: &mut Table<address, Member>, addr: address, version: u64) {
    let tenure = Tenure { joined: version, left: option::none() };
    if (members.contains(addr)) {
        members[addr].tenures.push_back(tenure);
    } else {
        members.add(addr, Member { tenures: vector[tenure] });
    };
}

/// Close `addr`'s open tenure at `version`. The caller has checked that
/// `addr` is a current member.
fun leave(members: &mut Table<address, Member>, addr: address, version: u64) {
    let tenures = &mut members[addr].tenures;
    let last = tenures.length() - 1;
    tenures[last].left = option::some(version);
}

fun assert_no_duplicates(addrs: &vector<address>) {
    let mut seen = vec_set::empty<address>();
    addrs.do_ref!(|addr| {
        assert!(!seen.contains(addr), EDuplicateBoardMember);
        seen.insert(*addr);
    });
}
