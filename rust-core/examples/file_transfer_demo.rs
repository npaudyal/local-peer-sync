// examples/file_transfer_demo.rs
use local_peer_sync_core::clipboard::ClipboardContent;
use local_peer_sync_core::*;
use std::sync::Arc;
use tokio::time::{sleep, Duration};

#[tokio::main]
async fn main() -> local_peer_sync_core::Result<()> {
    // Set logging to only show important info
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::WARN) // Only warnings and errors
        .with_target(false)
        .init();

    println!("🚀 Starting File Transfer Demo");
    println!("📋 This demo will sync text between devices");
    println!("📁 File transfer is being developed...");

    // Create config
    let device_name = format!(
        "Device-{}",
        whoami::fallible::hostname().unwrap_or_else(|_| "Unknown".to_string())
    );
    let config = SyncConfig::with_device_name(device_name.clone());

    println!("📱 Device: {}", device_name);
    println!("🔌 Port: {}", config.port);

    // Initialize sync system
    let sync = LocalPeerSync::new(config).await?;
    let sync_arc = Arc::new(sync);

    // Create clipboard engine
    let device_id = uuid::Uuid::new_v4().to_string();
    let mut clipboard_engine = ClipboardSyncEngine::new(device_id, 50)?;

    // Start monitoring
    let mut clipboard_rx = clipboard_engine.start_monitoring().await?;

    // Connect to sync system
    let engine_arc = Arc::new(clipboard_engine);
    sync_arc.set_clipboard_engine(engine_arc).await?;

    // Start the service
    sync_arc.start().await?;

    println!("✅ Service started!");
    println!("🔍 Looking for other devices...");

    // Monitor for peer connections
    let sync_clone = Arc::clone(&sync_arc);
    tokio::spawn(async move {
        loop {
            sleep(Duration::from_secs(3)).await;

            match sync_clone.get_peers().await {
                Ok(peers) => {
                    if !peers.is_empty() {
                        println!("👥 Connected devices: {}", peers.join(", "));
                    }
                }
                Err(_) => {}
            }
        }
    });

    // Monitor clipboard changes
    let sync_for_clipboard = Arc::clone(&sync_arc);
    tokio::spawn(async move {
        while let Some(item) = clipboard_rx.recv().await {
            println!("📋 Clipboard changed: {}", item.summary());

            // Try to broadcast to peers
            let content_to_sync = match &item.content {
                ClipboardContent::Text { content, .. } => content.clone(),
                _ => item.summary(),
            };

            match sync_for_clipboard.sync_clipboard(content_to_sync).await {
                Ok(()) => {
                    println!("📤 Synced to connected devices");
                }
                Err(e) => {
                    println!("❌ Failed to sync: {}", e);
                }
            }
        }
    });

    println!("\n🎯 Instructions:");
    println!("1. Run this on multiple devices on the same WiFi");
    println!("2. Copy text on one device");
    println!("3. Watch it appear on other devices");
    println!("4. Press Ctrl+C to stop");

    // Keep running
    loop {
        sleep(Duration::from_secs(10)).await;
    }
}
