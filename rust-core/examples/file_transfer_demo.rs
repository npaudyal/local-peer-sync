// examples/file_transfer_demo.rs
use local_peer_sync_core::file_transfer::{FileTransferManager, TransferConfig};
use local_peer_sync_core::*;
use tokio::time::{sleep, Duration};
use tracing::{error, info};

#[tokio::main]
async fn main() -> local_peer_sync_core::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    info!("🚀 Starting World-Class File Transfer Demo");

    // Create configuration
    let config = SyncConfig::with_device_name("Demo Device".to_string());

    // Initialize sync system
    let sync = LocalPeerSync::new(config).await?;

    // Create enhanced clipboard engine
    let device_id = uuid::Uuid::new_v4().to_string();
    let mut clipboard_engine = ClipboardSyncEngine::new(device_id, 50)?;

    // Set up progress monitoring
    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::unbounded_channel();

    // Create file transfer manager and set progress callback
    let transfer_config = TransferConfig::default();
    let mut file_manager = FileTransferManager::new(transfer_config)?;
    file_manager.set_progress_callback(progress_tx);

    // Start clipboard monitoring
    let _clipboard_rx = clipboard_engine.start_monitoring().await?;

    // Connect clipboard engine
    let engine_arc = std::sync::Arc::new(clipboard_engine);
    sync.set_clipboard_engine(engine_arc).await?;

    // Start the service
    sync.start().await?;
    info!("✅ File transfer system is running!");

    // Monitor progress updates
    tokio::spawn(async move {
        while let Some(progress) = progress_rx.recv().await {
            info!(
                "📊 Transfer Progress: {:.1}% ({}/{} files, {} MB/s)",
                if progress.bytes_total > 0 {
                    (progress.bytes_transferred as f64 / progress.bytes_total as f64) * 100.0
                } else {
                    0.0
                },
                progress.files_completed,
                progress.files_total,
                progress.speed_bps / (1024 * 1024)
            );
        }
    });

    info!("📋 Copy some files and watch them transfer between devices!");
    info!("🎯 System is now monitoring clipboard for file operations...");

    // Keep running
    loop {
        sleep(Duration::from_secs(10)).await;

        // Perform cleanup periodically
        if let Err(e) = file_manager.cleanup_expired_transfers().await {
            error!("Cleanup error: {}", e);
        }
    }
}
