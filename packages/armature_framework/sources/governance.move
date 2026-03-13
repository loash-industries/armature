module armature::governance;

use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EEmptyBoard: u64 = 0;
const EDuplicateBoardMember: u64 = 1;
const ENotBoardMember: u64 = 2;

/// Sealed governance model enum. The governance type is immutable at creation.
/// Governance state within a variant may be mutated by authorized proposal handlers.
public enum GovernanceConfig has drop, store {
    Board { members: VecSet<address> },
    Direct { voters: VecMap<address, u64>, total_shares: u64 },
    Weighted { delegates: VecMap<address, u64>, total_delegated: u64 },
}

/// Initialization payload for creating a DAO with a specific governance model.
/// Consumed once during DAO creation.
public enum GovernanceTypeInit has copy, drop, store {
    InitBoard { initial_members: vector<address> },
    InitDirect { initial_voters: vector<address>, initial_weights: vector<u64> },
    InitWeighted { initial_delegates: vector<address>, initial_weights: vector<u64> },
}

// === GovernanceTypeInit constructors ===

/// Create an InitBoard payload for DAO creation.
public fun init_board(initial_members: vector<address>): GovernanceTypeInit {
    GovernanceTypeInit::InitBoard { initial_members }
}

// === GovernanceConfig constructors ===

/// Create a Board governance config from an InitBoard payload.
public(package) fun new_board(init: &GovernanceTypeInit): GovernanceConfig {
    match (init) {
        GovernanceTypeInit::InitBoard { initial_members } => {
            let len = initial_members.length();
            assert!(len > 0, EEmptyBoard);
            let mut members = vec_set::empty<address>();
            let mut i = 0;
            while (i < len) {
                let addr = initial_members[i];
                assert!(!members.contains(&addr), EDuplicateBoardMember);
                members.insert(addr);
                i = i + 1;
            };
            GovernanceConfig::Board { members }
        },
        _ => abort 0,
    }
}

// === GovernanceConfig accessors ===

/// Returns true if addr is a board member. Aborts if not Board governance.
public fun is_board_member(self: &GovernanceConfig, addr: address): bool {
    match (self) {
        GovernanceConfig::Board { members, .. } => members.contains(&addr),
        _ => abort 0,
    }
}

/// Assert that addr is a current board member.
public(package) fun assert_board_member(self: &GovernanceConfig, addr: address) {
    assert!(self.is_board_member(addr), ENotBoardMember);
}

/// Build a vote snapshot for Board governance. Each member gets weight 1.
/// Returns (snapshot, total_weight).
public(package) fun board_vote_snapshot(self: &GovernanceConfig): (VecMap<address, u64>, u64) {
    match (self) {
        GovernanceConfig::Board { members, .. } => {
            let keys = members.keys();
            let len = keys.length();
            let mut snapshot = vec_map::empty<address, u64>();
            let mut i = 0;
            while (i < len) {
                snapshot.insert(keys[i], 1u64);
                i = i + 1;
            };
            (snapshot, len)
        },
        _ => abort 0,
    }
}

/// Atomically replace board members and seat count.
public(package) fun set_board(self: &mut GovernanceConfig, new_members: vector<address>) {
    assert!(new_members.length() > 0, EEmptyBoard);
    let mut members = vec_set::empty<address>();
    let mut i = 0;
    while (i < new_members.length()) {
        let addr = new_members[i];
        assert!(!members.contains(&addr), EDuplicateBoardMember);
        members.insert(addr);
        i = i + 1;
    };
    match (self) {
        GovernanceConfig::Board { members: m } => {
            *m = members;
        },
        _ => abort 0,
    }
}
