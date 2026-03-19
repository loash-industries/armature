use move_core_types::account_address::AccountAddress;
use move_core_types::language_storage::StructTag;
use url::Url;

pub mod handlers;
pub(crate) mod models;
pub mod traits;

pub const TESTNET_REMOTE_STORE_URL: &str = "https://checkpoints.testnet.sui.io";
pub const MAINNET_REMOTE_STORE_URL: &str = "https://checkpoints.mainnet.sui.io";
pub const LOCALNET_REMOTE_STORE_URL: &str = "http://localhost:9000";

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum ArmatureEnv {
    Mainnet,
    Testnet,
    Localnet,
}

impl ArmatureEnv {
    pub fn remote_store_url(&self) -> Url {
        match self {
            Self::Mainnet => Url::parse(MAINNET_REMOTE_STORE_URL).unwrap(),
            Self::Testnet => Url::parse(TESTNET_REMOTE_STORE_URL).unwrap(),
            Self::Localnet => Url::parse(LOCALNET_REMOTE_STORE_URL).unwrap(),
        }
    }
}

/// Core module names emitting events you want to index.
pub const CORE_MODULES: &[&str] = &["dao", "proposals", "governance", "treasury"];

/// Parse a list of package ID strings (e.g. "0x1234...") into `AccountAddress` values.
/// Invalid entries are silently skipped.
pub fn parse_package_addresses(ids: &[String]) -> Vec<AccountAddress> {
    ids.iter()
        .filter_map(|id| AccountAddress::from_hex_literal(id).ok())
        .collect()
}

/// Returns true if the given struct tag's package address matches any of the
/// known Armature package addresses.
pub fn is_armature_event(tag: &StructTag, packages: &[AccountAddress]) -> bool {
    packages.iter().any(|pkg| &tag.address == pkg)
}
