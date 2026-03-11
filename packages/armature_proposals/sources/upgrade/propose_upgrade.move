module armature_proposals::propose_upgrade;

/// Authorize a package upgrade using a stored UpgradeCap.
public struct ProposeUpgrade has store {
    cap_id: ID,
    package_id: ID,
    digest: vector<u8>,
    policy: u8,
}

// === Constructor ===

public fun new(
    cap_id: ID,
    package_id: ID,
    digest: vector<u8>,
    policy: u8,
): ProposeUpgrade {
    ProposeUpgrade { cap_id, package_id, digest, policy }
}

// === Accessors ===

public fun cap_id(self: &ProposeUpgrade): ID { self.cap_id }
public fun package_id(self: &ProposeUpgrade): ID { self.package_id }
public fun digest(self: &ProposeUpgrade): &vector<u8> { &self.digest }
public fun policy(self: &ProposeUpgrade): u8 { self.policy }
