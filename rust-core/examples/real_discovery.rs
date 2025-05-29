//! Example showing real mDNS discovery

use local_peer_sync_core::{LocalPeerSync, SyncConfig};
use tokio::time::{sleep, Duration};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    println!("🚀 Local Peer Sync - Real mDNS Discovery Test");

    // Create configuration with a unique device name
    let device_name = format!("TestDevice-{}", rand::random::<u16>());
    let config = SyncConfig::with_device_name(device_name.clone());

    println!("Device ID: {}", config.device_id);
    println!("Device Name: {}", config.device_name);
    println!("Port: {}", config.port);

    // Create sync instance
    let sync = LocalPeerSync::new(config).await?;

    // Start the service
    println!("Starting sync service...");
    sync.start().await?;

    println!("Service started! Discovering peers for 30 seconds...");
    println!("Run this example on multiple devices to see peer discovery!");

    // Wait and periodically show discovered peers
    for i in 1..=6 {
        sleep(Duration::from_secs(5)).await;

        let peers = sync.get_peers().await?;
        println!("[{}s] Discovered {} peers: {:?}", i * 5, peers.len(), peers);

        if i == 3 {
            // Test clipboard sync after 15 seconds
            println!("Testing clipboard sync...");
            let timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            sync.sync_clipboard(format!("Hello from {}! Time: {}", device_name, timestamp))
                .await?;
        }
    }

    // Stop the service
    println!("Stopping sync service...");
    sync.stop().await?;

    println!("✅ Test completed!");
    Ok(())
}
