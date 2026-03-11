use anyhow::Context;
use clap::Parser;
use prometheus::Registry;
use std::net::SocketAddr;
use sui_indexer_alt_framework::ingestion::ClientArgs;
use sui_indexer_alt_framework::{Indexer, IndexerArgs};
use sui_indexer_alt_metrics::MetricsArgs;
use sui_pg_db::{Db, DbArgs};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use url::Url;

use armature_indexer::handlers::example_handler::ExampleHandler;
use armature_indexer::ArmatureEnv;
use armature_schema::MIGRATIONS;

#[derive(Parser)]
#[clap(rename_all = "kebab-case", author, version)]
struct Args {
    #[command(flatten)]
    db_args: DbArgs,

    /// Remote store URL for checkpoint ingestion.
    /// Defaults to testnet if not provided.
    #[arg(long, env = "REMOTE_STORE_URL")]
    remote_store_url: Option<Url>,

    /// First checkpoint to index from.
    #[arg(long, env = "FIRST_CHECKPOINT", default_value = "0")]
    first_checkpoint: u64,

    /// Network environment
    #[arg(long, env = "ARMATURE_ENV", default_value = "testnet")]
    env: ArmatureEnv,

    /// Health-check port
    #[arg(long, env = "HEALTH_PORT", default_value = "9185")]
    health_port: u16,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _guard = telemetry_subscribers::TelemetryConfig::new()
        .with_env()
        .init();

    let args = Args::parse();

    // Database setup & migrations
    let db = Db::new(args.db_args)
        .await
        .context("Failed to connect to database")?;
    let mut conn = db.connect().await.context("Failed to get DB connection")?;
    conn.run_pending_migrations(MIGRATIONS)
        .await
        .context("Failed to run migrations")?;

    // Determine remote store URL
    let remote_store_url = args
        .remote_store_url
        .unwrap_or_else(|| args.env.remote_store_url());

    // Metrics
    let registry = Registry::new();

    // Build indexer
    let mut indexer = Indexer::new(
        db,
        IndexerArgs {
            first_checkpoint: Some(args.first_checkpoint),
            ..Default::default()
        },
        ClientArgs {
            remote_store_url: Some(remote_store_url),
            ..Default::default()
        },
        Default::default(), // IngestionClientArgs
        &registry,
    )
    .await?;

    // Register pipelines
    indexer
        .concurrent_pipeline(ExampleHandler::new(args.env), Default::default())
        .await?;

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

    // Run
    indexer.run().await?;

    Ok(())
}
