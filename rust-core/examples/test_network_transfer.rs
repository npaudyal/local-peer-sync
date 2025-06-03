// examples/test_network_transfer.rs
use local_peer_sync_core::file_transfer::{FileTransferManager, TransferConfig};
use local_peer_sync_core::*;
use std::fs;
use std::path::PathBuf;
use tokio::time::{sleep, Duration};
use tracing::info;

#[tokio::main]
async fn main() -> local_peer_sync_core::Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    info!("🌐 Testing Full Network File Transfer");

    // Create test file
    let test_file = PathBuf::from("network_test.txt");
    fs::write(
        &test_file,
        "This file will be transferred over the network! 🚀",
    )?;

    // Device 1 Setup (Sender)
    info!("📱 Setting up sender device...");
    let sender_config = SyncConfig::with_device_name("Sender Device".to_string());
    let sender_sync = LocalPeerSync::new(sender_config).await?;

    let sender_device_id = uuid::Uuid::new_v4().to_string();
    let mut sender_clipboard = ClipboardSyncEngine::new(sender_device_id, 50)?;
    let _sender_rx = sender_clipboard.start_monitoring().await?;

    sender_sync
        .set_clipboard_engine(std::sync::Arc::new(sender_clipboard))
        .await?;
    sender_sync.start().await?;

    // Give some time for setup
    sleep(Duration::from_secs(2)).await;

    info!("✅ Sender device ready");

    // Device 2 Setup (Receiver)
    info!("📱 Setting up receiver device...");
    let receiver_config = SyncConfig::with_device_name("Receiver Device".to_string());
    let receiver_sync = LocalPeerSync::new(receiver_config).await?;

    let receiver_device_id = uuid::Uuid::new_v4().to_string();
    let mut receiver_clipboard = ClipboardSyncEngine::new(receiver_device_id, 50)?;
    let _receiver_rx = receiver_clipboard.start_monitoring().await?;

    receiver_sync
        .set_clipboard_engine(std::sync::Arc::new(receiver_clipboard))
        .await?;
    receiver_sync.start().await?;

    info!("✅ Receiver device ready");

    // Wait for devices to discover each other
    info!("🔍 Waiting for device discovery...");
    sleep(Duration::from_secs(5)).await;

    // Check peer discovery
    let sender_peers = sender_sync.get_peers().await?;
    let receiver_peers = receiver_sync.get_peers().await?;

    info!("📊 Discovery results:");
    info!(
        "   Sender sees {} peers: {:?}",
        sender_peers.len(),
        sender_peers
    );
    info!(
        "   Receiver sees {} peers: {:?}",
        receiver_peers.len(),
        receiver_peers
    );

    // Test file transfer
    info!("📁 Testing file transfer...");
    let transfer_config = TransferConfig::default();
    let mut file_manager = FileTransferManager::new(transfer_config)?;

    let package = file_manager
        .prepare_files_for_transfer(&[test_file.clone()])
        .await?;
    info!("📦 Prepared file package: {} bytes", package.total_size);

    // Simulate sending through network
    let received_paths = file_manager.receive_files(package).await?;
    info!("📥 Received {} files", received_paths.len());

    for path in received_paths {
        let content = fs::read_to_string(&path)?;
        info!("✅ Received file content: {}", content);
    }

    // Cleanup
    info!("🧹 Cleaning up...");
    sender_sync.stop().await?;
    receiver_sync.stop().await?;
    fs::remove_file(&test_file)?;

    info!("🎉 Network transfer test completed!");

    Ok(())
}
