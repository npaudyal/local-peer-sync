//! Basic example showing Local Peer Sync usage

use local_peer_sync_core::{LocalPeerSync, SyncConfig};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    println!("🚀 Local Peer Sync - Basic Example");

    // Create configuration
    let config = SyncConfig::with_device_name("Example Device".to_string());
    println!("Device ID: {}", config.device_id);
    println!("Device Name: {}", config.device_name);

    // Create sync instance
    let sync = LocalPeerSync::new(config).await?;

    // Start the service
    println!("Starting sync service...");
    sync.start().await?;

    // Simulate clipboard sync
    println!("Syncing clipboard content...");
    sync.sync_clipboard("Hello, World! 🌍".to_string()).await?;

    // Keep running for a bit
    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;

    // Stop the service
    println!("Stopping sync service...");
    sync.stop().await?;

    println!("✅ Example completed successfully!");
    Ok(())
}
