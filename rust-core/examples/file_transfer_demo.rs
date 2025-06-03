// examples/file_transfer_demo.rs
use local_peer_sync_core::{
    clipboard::{ClipboardConfig, ClipboardContent, ClipboardSyncEngine},
    LocalPeerSync, SyncConfig,
};
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use tracing::{error, info};

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
    info!("1. 📁 Copy any file(s) on this device");
    info!("2. 🖥️  Go to another device running this demo");
    info!("3. 📋 Paste (Ctrl+V/Cmd+V) to receive the files");
    info!("4. 🎉 Files will be transferred and ready to use!");
    info!("");
    info!("👀 Watching for clipboard changes...");

    // Handle clipboard changes
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

                    // Sync to network
                    if let Err(e) = sync_clone.sync_clipboard(item.summary()).await {
                        error!("❌ Failed to sync file transfer: {}", e);
                    } else {
                        info!("📤 File transfer synced to network!");
                    }
                }
                ClipboardContent::Text { content, .. } => {
                    let preview = if content.len() > 50 {
                        format!("{}...", &content[..50])
                    } else {
                        content.clone()
                    };
                    info!("📋 Text copied: {}", preview);

                    // Sync to network
                    if let Err(e) = sync_clone.sync_clipboard(content.clone()).await {
                        error!("❌ Failed to sync text: {}", e);
                    } else {
                        info!("📤 Text synced to network!");
                    }
                }
                _ => {
                    info!("📋 Clipboard changed: {}", item.summary());
                    if let Err(e) = sync_clone.sync_clipboard(item.summary()).await {
                        error!("❌ Failed to sync clipboard: {}", e);
                    }
                }
            }
        }
    });

    // Monitor peer connections
    tokio::spawn(async move {
        let mut last_peer_count = 0;
        loop {
            match sync.get_peers().await {
                Ok(peers) => {
                    if peers.len() != last_peer_count {
                        if peers.is_empty() {
                            info!("👥 No connected devices (start this demo on other devices to connect)");
                        } else {
                            info!("👥 Connected devices: {}", peers.join(", "));
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

    // Keep running
    loop {
        sleep(Duration::from_secs(1)).await;
    }
}

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
