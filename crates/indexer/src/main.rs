use anyhow::Context;
use clap::Parser;
use prometheus::Registry;
use std::net::SocketAddr;
use sui_indexer_alt_framework::ingestion::ingestion_client::IngestionClientArgs;
use sui_indexer_alt_framework::ingestion::ClientArgs;
use sui_indexer_alt_framework::postgres::{Db, DbArgs};
use sui_indexer_alt_framework::{Indexer, IndexerArgs};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use url::Url;

use armature_indexer::handlers::activity_handler::ActivityHandler;
use armature_indexer::handlers::dao_handler::DaoHandler;
use armature_indexer::handlers::proposal_handler::ProposalHandler;
use armature_indexer::handlers::treasury_handler::TreasuryHandler;
use armature_indexer::ArmatureEnv;
use armature_schema::MIGRATIONS;

mod api;

#[derive(Parser)]
#[clap(rename_all = "kebab-case", author, version)]
struct Args {
    /// PostgreSQL connection URL.
    #[arg(long, env = "DATABASE_URL")]
    database_url: Url,

    /// HTTP checkpoint archive URL (e.g. https://checkpoints.mainnet.sui.io).
    /// Use this for mainnet/testnet. Mutually exclusive with --rpc-api-url.
    #[arg(long, env = "REMOTE_STORE_URL")]
    remote_store_url: Option<Url>,

    /// gRPC fullnode URL for checkpoint ingestion (e.g. http://localhost:9000).
    /// Use this for localnet or when connecting directly to a fullnode.
    /// Mutually exclusive with --remote-store-url.
    #[arg(long, env = "RPC_API_URL")]
    rpc_api_url: Option<Url>,

    /// First checkpoint to index from.
    #[arg(long, env = "FIRST_CHECKPOINT", default_value = "0")]
    first_checkpoint: u64,

    /// Network environment (localnet | testnet | mainnet).
    #[arg(long, env = "ARMATURE_ENV", default_value = "testnet")]
    env: ArmatureEnv,

    /// Armature package ID(s) to filter events by.
    /// Comma-separated for multiple packages, or repeat the flag.
    /// Populated automatically by the deploy script via ARMATURE_PACKAGE_ID.
    #[arg(long, env = "ARMATURE_PACKAGE_ID", value_delimiter = ',')]
    package_ids: Vec<String>,

    /// Port for the REST API server.
    #[arg(long, env = "API_PORT", default_value = "3000")]
    api_port: u16,

    /// Health-check port.
    #[arg(long, env = "HEALTH_PORT", default_value = "9185")]
    health_port: u16,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _guard = telemetry_subscribers::TelemetryConfig::new()
        .with_env()
        .init();

    let args = Args::parse();

    // Determine checkpoint source — prefer explicit flags, fall back to env default
    let remote_store_url = args.remote_store_url;
    let rpc_api_url = args.rpc_api_url.or_else(|| {
        if remote_store_url.is_none() {
            // Default: use the network's public checkpoint archive
            Some(args.env.remote_store_url())
        } else {
            None
        }
    });

    // Metrics registry
    let registry = Registry::new();

    // Build indexer — runs migrations automatically
    let mut indexer = Indexer::<Db>::new_from_pg(
        args.database_url.clone(),
        DbArgs::default(),
        IndexerArgs {
            first_checkpoint: Some(args.first_checkpoint),
            ..Default::default()
        },
        ClientArgs {
            ingestion: IngestionClientArgs {
                remote_store_url,
                rpc_api_url,
                ..Default::default()
            },
            ..Default::default()
        },
        Default::default(),
        Some(&MIGRATIONS),
        None,
        &registry,
    )
    .await
    .context("Failed to start indexer")?;

    // Register pipelines — one per logical concern
    let ids = &args.package_ids;
    indexer
        .concurrent_pipeline(DaoHandler::new(ids), Default::default())
        .await?;
    indexer
        .concurrent_pipeline(ProposalHandler::new(ids), Default::default())
        .await?;
    indexer
        .concurrent_pipeline(TreasuryHandler::new(ids), Default::default())
        .await?;
    indexer
        .concurrent_pipeline(ActivityHandler::new(ids), Default::default())
        .await?;

    // REST API
    let api_addr: SocketAddr = ([0, 0, 0, 0], args.api_port).into();
    let db_url = args.database_url.to_string();
    tokio::spawn(api::serve(db_url, api_addr));

    // Health check server
    let health_addr: SocketAddr = ([0, 0, 0, 0], args.health_port).into();
    tokio::spawn(async move {
        let listener = TcpListener::bind(health_addr).await.unwrap();
        tracing::info!("Health check listening on {}", health_addr);
        loop {
            if let Ok((mut stream, _)) = listener.accept().await {
                let mut buf = [0u8; 1024];
                let _ = stream.read(&mut buf).await;
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
                let _ = stream.write_all(response.as_bytes()).await;
            }
        }
    });

    // Run — wait for the indexer service to complete or fail
    let mut service = indexer.run().await?;
    service.join().await?;

    Ok(())
}
