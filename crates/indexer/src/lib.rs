use url::Url;

pub mod handlers;
pub(crate) mod models;
pub mod traits;

pub const TESTNET_REMOTE_STORE_URL: &str = "https://checkpoints.testnet.sui.io";
pub const MAINNET_REMOTE_STORE_URL: &str = "https://checkpoints.mainnet.sui.io";

// Package addresses — update with your deployed package IDs
const TESTNET_PACKAGES: &[&str] = &[];
const MAINNET_PACKAGES: &[&str] = &[];

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum ArmatureEnv {
    Mainnet,
    Testnet,
}

impl ArmatureEnv {
    pub fn remote_store_url(&self) -> Url {
        match self {
            Self::Mainnet => Url::parse(MAINNET_REMOTE_STORE_URL).unwrap(),
            Self::Testnet => Url::parse(TESTNET_REMOTE_STORE_URL).unwrap(),
        }
    }

    pub fn packages(&self) -> Vec<String> {
        let builtin: &[&str] = match self {
            Self::Mainnet => MAINNET_PACKAGES,
            Self::Testnet => TESTNET_PACKAGES,
        };
        builtin.iter().map(|s| s.to_string()).collect()
    }
}

/// Core module names emitting events you want to index.
pub const CORE_MODULES: &[&str] = &[
    // Add your module names here, e.g.:
    // "pool",
    // "vault",
];
