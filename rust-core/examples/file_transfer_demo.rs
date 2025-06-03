// examples/file_transfer_demo.rs
use local_peer_sync_core::{
    clipboard::{ClipboardConfig, ClipboardContent, ClipboardSyncEngine},
    LocalPeerSync, SyncConfig,
};
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use tracing::{error, info, warn};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize enhanced logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .init();

    info!("🚀 WORLD-CLASS FILE TRANSFER DEMO 🚀");
    info!("📁 Copy files on one device, paste on another!");
    info!("🌍 Cross-platform: Mac ↔ Windows ↔ Linux");
    info!("");

    // Create configuration
    let config = SyncConfig::default();
    info!(
        "🔧 Device: {} ({})",
        config.device_name,
        &config.device_id[..8]
    );

    // Initialize the sync service
    let sync = LocalPeerSync::new(config.clone()).await?;

    // Create enhanced clipboard engine
    let clipboard_config = ClipboardConfig {
        sync_files: true,                    // ✅ Enable file sync
        sync_images: true,                   // ✅ Enable image sync
        sync_rich_text: true,                // ✅ Enable rich text
        max_content_size: 100 * 1024 * 1024, // 100MB max
        enable_compression: true,            // ✅ Enable compression
        compression_threshold: 1024,         // Compress > 1KB
        enable_history: true,                // ✅ Keep history
        auto_paste: true,                    // ✅ Auto-paste received content
    };

    let mut clipboard_engine = ClipboardSyncEngine::new(
        config.device_id.clone(),
        50, // history size
    )?;

    clipboard_engine.update_config(clipboard_config);

    // Start clipboard monitoring
    let mut clipboard_rx = clipboard_engine.start_monitoring().await?;
    let clipboard_engine = Arc::new(clipboard_engine);

    // Connect clipboard to sync service
    sync.set_clipboard_engine(clipboard_engine.clone()).await?;

    // Start the service
    sync.start().await?;

    info!("✅ File transfer system is READY!");
    info!("");
    info!("🎯 HOW TO TEST:");
    info!("1. 📁 Copy any file(s) on this device (right-click → Copy)");
    info!("2. 🖥️  Go to another device running this demo");
    info!("3. 📋 Files will be automatically transferred!");
    info!("4. 🎉 Check the receiving device for file locations");
    info!("");
    info!("👀 Watching for clipboard changes...");

    // Handle clipboard changes with PROPER FileTransfer support
    let sync_clone = sync.clone();
    tokio::spawn(async move {
        while let Some(item) = clipboard_rx.recv().await {
            match &item.content {
                ClipboardContent::FileTransfer {
                    files,
                    total_size,
                    transfer_id,
                } => {
                    info!("🚀 FILE TRANSFER DETECTED!");
                    info!("📁 Files: {}", files.len());
                    info!("💾 Size: {}", format_file_size(*total_size));
                    info!("🆔 ID: {}", &transfer_id[..8]);

                    // Show file details
                    for (i, file) in files.iter().enumerate().take(5) {
                        info!(
                            "   {}. 📄 {} ({})",
                            i + 1,
                            file.name,
                            format_file_size(file.size)
                        );
                    }
                    if files.len() > 5 {
                        info!("   ... and {} more files", files.len() - 5);
                    }

                    // Create a proper FileTransfer package for network transmission
                    let transfer_package = local_peer_sync_core::file_transfer::types::FileTransferPackage {
                        transfer_id: transfer_id.clone(),
                        source_device_id: sync_clone.get_config().device_id.clone(),
                        files: files.clone(),
                        total_size: *total_size,
                        compression_ratio: 1.0,
                        created_at: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap()
                            .as_secs(),
                        expires_at: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap()
                            .as_secs()
                            + 86400, // 24 hours
                        metadata: local_peer_sync_core::file_transfer::types::TransferMetadata {
                            title: Some(format!("{} files", files.len())),
                            description: None,
                            priority: local_peer_sync_core::file_transfer::types::TransferPriority::High,
                            estimated_duration: 60,
                            bandwidth_limit: None,
                            auto_cleanup: true,
                        },
                    };

                    // Create proper FileTransfer message
                    let message =
                        local_peer_sync_core::network::protocol::SyncMessage::new_file_transfer(
                            sync_clone.get_config().device_id.clone(),
                            transfer_package,
                        );

                    // Send via network manager directly
                    let manager = sync_clone.get_manager().await;
                    let manager_guard = manager.read().await;
                    let peer_manager = manager_guard.get_peer_manager().await;

                    match peer_manager.broadcast_message(message).await {
                        Ok(()) => {
                            info!("📤 File transfer broadcast successful!");
                            info!("✅ {} files sent to network peers", files.len());
                        }
                        Err(e) => {
                            error!("❌ Failed to broadcast file transfer: {}", e);
                        }
                    }
                }

                ClipboardContent::Text { content, .. } => {
                    let preview = if content.len() > 50 {
                        format!("{}...", &content[..50])
                    } else {
                        content.clone()
                    };

                    // Skip our own file transfer summaries
                    if content.starts_with("🎉 FILES RECEIVED")
                        || content.starts_with("File Transfer:")
                    {
                        return; // Don't sync our own transfer summaries
                    }

                    info!("📋 Text copied: {}", preview);

                    // Sync text normally using the existing method
                    match sync_clone.sync_clipboard(content.clone()).await {
                        Ok(()) => {
                            info!("📤 Text synced to network!");
                        }
                        Err(e) => {
                            error!("❌ Failed to sync text: {}", e);
                        }
                    }
                }

                ClipboardContent::RichText { plain_text, .. } => {
                    let preview = if plain_text.len() > 50 {
                        format!("{}...", &plain_text[..50])
                    } else {
                        plain_text.clone()
                    };
                    info!("📋 Rich text copied: {}", preview);

                    match sync_clone.sync_clipboard(plain_text.clone()).await {
                        Ok(()) => {
                            info!("📤 Rich text synced to network!");
                        }
                        Err(e) => {
                            error!("❌ Failed to sync rich text: {}", e);
                        }
                    }
                }

                ClipboardContent::Url { url, .. } => {
                    info!("📋 URL copied: {}", url);

                    match sync_clone.sync_clipboard(url.clone()).await {
                        Ok(()) => {
                            info!("📤 URL synced to network!");
                        }
                        Err(e) => {
                            error!("❌ Failed to sync URL: {}", e);
                        }
                    }
                }

                _ => {
                    info!("📋 Other clipboard content: {}", item.summary());
                    // For other content types, sync the summary
                    match sync_clone.sync_clipboard(item.summary()).await {
                        Ok(()) => {
                            info!("📤 Content summary synced to network!");
                        }
                        Err(e) => {
                            error!("❌ Failed to sync content: {}", e);
                        }
                    }
                }
            }
        }
    });

    // Monitor peer connections and show status
    let sync_monitor = sync.clone();
    tokio::spawn(async move {
        let mut last_peer_count = 0;
        let mut no_peers_warning_shown = false;

        loop {
            match sync_monitor.get_peers().await {
                Ok(peers) => {
                    if peers.len() != last_peer_count {
                        if peers.is_empty() {
                            if !no_peers_warning_shown {
                                warn!("👥 No connected devices");
                                info!("   💡 Start this demo on other devices to connect");
                                info!("   💡 Make sure devices are on the same network");
                                no_peers_warning_shown = true;
                            }
                        } else {
                            info!("👥 Connected devices: {}", peers.join(", "));
                            info!("   ✅ Ready for file transfers!");
                            no_peers_warning_shown = false;
                        }
                        last_peer_count = peers.len();
                    }
                }
                Err(e) => {
                    error!("❌ Failed to get peers: {}", e);
                }
            }
            sleep(Duration::from_secs(5)).await;
        }
    });

    // Show periodic status updates
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(30));
        loop {
            interval.tick().await;
            info!("📊 File transfer system running...");
            info!("   🔍 Monitoring clipboard for file copies");
            info!("   📡 Listening for incoming transfers");
            info!("   💡 Copy files to test the system!");
        }
    });

    // Keep the demo running
    info!("🎮 Demo is running! Press Ctrl+C to stop.");
    loop {
        sleep(Duration::from_secs(1)).await;
    }
}

/// Format file size in human-readable format
fn format_file_size(size: u64) -> String {
    const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
    let mut size = size as f64;
    let mut unit_index = 0;

    while size >= 1024.0 && unit_index < UNITS.len() - 1 {
        size /= 1024.0;
        unit_index += 1;
    }

    if unit_index == 0 {
        format!("{} {}", size as u64, UNITS[unit_index])
    } else {
        format!("{:.1} {}", size, UNITS[unit_index])
    }
}
