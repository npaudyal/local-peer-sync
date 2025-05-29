//! Ultimate clipboard synchronization test - The world's best clipboard sync
use local_peer_sync_core::clipboard::{ClipboardConfig, ClipboardContent, ClipboardSyncEngine};
use local_peer_sync_core::{LocalPeerSync, SyncConfig};
use std::sync::Arc;
use tokio::time::{sleep, Duration};
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize premium logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .with_thread_ids(true)
        .init();
    println!("🏆 WORLD'S BEST CLIPBOARD SYNC - ULTIMATE TEST");
    println!("==============================================");
    println!("Features:");
    println!("✨ Advanced clipboard format detection");
    println!("🖼️  Multi-format image support (PNG, JPEG, GIF)");
    println!("📝 Rich text with HTML formatting");
    println!("🔗 URL detection and metadata");
    println!("🗜️  Smart compression for large content");
    println!("📊 Real-time statistics");
    println!("🛡️  Rate limiting and error recovery");
    println!("💾 Smart history with deduplication");
    println!("🔄 Bidirectional clipboard sync");
    println!();

    // Detect platform and show capabilities
    let platform = if cfg!(target_os = "windows") {
        "Windows 💻"
    } else if cfg!(target_os = "macos") {
        "macOS 🍎"
    } else if cfg!(target_os = "linux") {
        "Linux 🐧"
    } else {
        "Unknown ❓"
    };

    println!("🖥️  Platform: {}", platform);

    // Create advanced clipboard engine
    let device_id = uuid::Uuid::new_v4().to_string();
    let mut clipboard_engine = match ClipboardSyncEngine::new(device_id.clone(), 50) {
        Ok(engine) => engine,
        Err(e) => {
            eprintln!("❌ Failed to create clipboard engine: {}", e);
            return Err(e.into());
        }
    };

    // Configure for maximum features
    let mut config = ClipboardConfig::default();
    config.sync_images = true;
    config.sync_files = true;
    config.sync_rich_text = true;
    config.enable_compression = true;
    config.enable_history = true;
    clipboard_engine.update_config(config);

    // Start intelligent monitoring
    let mut clipboard_rx = clipboard_engine.start_monitoring().await?;

    // Create network sync with enhanced capabilities
    let device_name = format!(
        "Ultimate-{}-{}",
        platform.chars().take(3).collect::<String>(),
        rand::random::<u16>()
    );
    let sync_config = SyncConfig::with_device_name(device_name.clone());
    let sync = Arc::new(LocalPeerSync::new(sync_config).await?);

    println!("🚀 Device: {} ({})", device_name, &device_id[..8]);

    // Convert to Arc for sharing
    let clipboard_engine = Arc::new(clipboard_engine);

    // 🔥 CRITICAL: Connect clipboard engine to network service BEFORE starting
    println!("🔗 Connecting clipboard engine to network service...");
    sync.set_clipboard_engine(Arc::clone(&clipboard_engine))
        .await?;

    // Start sync service
    if let Err(e) = sync.start().await {
        eprintln!("❌ Failed to start sync service: {}", e);
        return Err(e.into());
    }

    println!("⚡ Service started! Advanced clipboard monitoring active...");
    println!("🔗 Network service connected to clipboard engine!");
    println!("🌐 Listening on port: {}", sync.get_config().port);
    println!("🆔 Device ID: {}", sync.get_config().device_id);
    println!();
    println!("🎯 TEST INSTRUCTIONS:");
    println!("1. Copy TEXT in any app → Watch instant sync");
    println!("2. Copy IMAGES → See multi-format conversion");
    println!("3. Copy URLS → Observe smart detection");
    println!("4. Copy HTML content → Rich text sync");
    println!("5. Run on multiple devices to see cross-platform magic!");
    println!();
    println!("📊 Statistics will be shown every 30 seconds");
    println!("🔄 Content copied on ANY device will appear on ALL devices!");
    println!("Press Ctrl+C to stop...");
    println!();

    let sync_clone = Arc::clone(&sync);
    let engine_clone = Arc::clone(&clipboard_engine);

    // Handle clipboard changes with advanced processing
    tokio::spawn(async move {
        while let Some(clipboard_item) = clipboard_rx.recv().await {
            println!("📋 LOCAL CLIPBOARD CHANGED: {}", clipboard_item.summary());
            println!(
                "   Size: {} bytes | Hash: {}... | Source: {}",
                clipboard_item.content_size(),
                &clipboard_item.content_hash[..8],
                clipboard_item.source_device
            );

            // Only broadcast if this change originated locally (not from network)
            if clipboard_item.source_device == "local" {
                // Convert to legacy format for network sync
                let legacy_content = match &clipboard_item.content {
                    ClipboardContent::Text { content, .. } => content.clone(),
                    ClipboardContent::RichText { plain_text, .. } => plain_text.clone(),
                    ClipboardContent::Url { url, .. } => url.clone(),
                    _ => clipboard_item.summary(),
                };

                // Get current peers
                match sync_clone.get_peers().await {
                    Ok(peers) => {
                        if peers.is_empty() {
                            println!("   📡 No peers connected - content ready for sync when peers connect");
                        } else {
                            println!("   📤 Broadcasting to {} peer(s): {:?}", peers.len(), peers);

                            // Send via network
                            match sync_clone.sync_clipboard(legacy_content).await {
                                Ok(()) => println!("   ✅ Broadcast successful!"),
                                Err(e) => eprintln!("   ❌ Broadcast failed: {}", e),
                            }
                        }
                    }
                    Err(e) => eprintln!("   ❌ Failed to get peers: {}", e),
                }
            } else {
                println!("   📨 Received from network - applied to local clipboard");
            }

            println!();
        }
    });

    // Statistics and status loop
    let mut stats_counter = 0;
    loop {
        sleep(Duration::from_secs(10)).await;
        stats_counter += 1;

        // Show peer status every 10 seconds
        match sync.get_peers().await {
            Ok(peers) => {
                if !peers.is_empty() {
                    println!("🌐 Connected peers: {}", peers.len());
                    for (i, peer) in peers.iter().enumerate() {
                        println!("   {}. {}", i + 1, peer);
                    }
                } else if stats_counter % 6 == 0 {
                    println!("🔍 No peers found. Troubleshooting:");
                    println!("   • Are both devices on the same WiFi network?");
                    println!(
                        "   • Is port {} open on both devices?",
                        sync.get_config().port
                    );
                    println!(
                        "   • Try running: telnet <other-device-ip> {}",
                        sync.get_config().port
                    );
                }
            }
            Err(e) => eprintln!("❌ Peer status error: {}", e),
        }

        // Show detailed statistics every 30 seconds
        if stats_counter % 3 == 0 {
            let stats = engine_clone.get_stats().await;
            println!();
            println!("📊 STATISTICS:");
            println!("   Items synced: {}", stats.items_synced);
            println!("   Bytes synced: {} KB", stats.bytes_synced / 1024);
            println!("   Images synced: {}", stats.images_synced);
            println!("   Files synced: {}", stats.files_synced);
            if let Some(last_sync) = stats.last_sync {
                println!("   Last sync: {}", last_sync.format("%H:%M:%S"));
            }

            let history = engine_clone.get_history().await;
            println!("   History items: {}", history.len());
            println!();
        }
    }
}
