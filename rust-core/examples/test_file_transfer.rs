// examples/test_file_transfer.rs
use local_peer_sync_core::file_transfer::{FileTransferManager, TransferConfig};
use std::fs;
use std::path::PathBuf;
use tracing::info;

#[tokio::main]
async fn main() -> local_peer_sync_core::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    info!("🧪 Testing File Transfer System");

    // Create test files
    let test_dir = PathBuf::from("test_output");
    fs::create_dir_all(&test_dir)?;

    let test_files = vec![
        test_dir.join("test1.txt"),
        test_dir.join("test2.json"),
        test_dir.join("test3.md"),
    ];

    // Create test content
    fs::write(&test_files[0], "Hello from file 1!")?;
    fs::write(&test_files[1], r#"{"message": "Hello from JSON!"}"#)?;
    fs::write(&test_files[2], "# Hello from Markdown!")?;

    info!("📁 Created test files: {:?}", test_files);

    // Test file transfer
    let config = TransferConfig::default();
    let mut manager = FileTransferManager::new(config)?;

    // Set up progress monitoring
    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::unbounded_channel();
    manager.set_progress_callback(progress_tx);

    // Monitor progress in background
    tokio::spawn(async move {
        while let Some(progress) = progress_rx.recv().await {
            info!(
                "📊 Progress: {:.1}% - {}/{} files - Status: {:?}",
                if progress.bytes_total > 0 {
                    (progress.bytes_transferred as f64 / progress.bytes_total as f64) * 100.0
                } else {
                    0.0
                },
                progress.files_completed,
                progress.files_total,
                progress.status
            );
        }
    });

    // Step 1: Prepare files for transfer
    info!("📦 Preparing files for transfer...");
    let package = manager.prepare_files_for_transfer(&test_files).await?;

    info!("✅ Package prepared:");
    info!("   📁 Files: {}", package.files.len());
    info!("   📏 Total size: {} bytes", package.total_size);
    info!("   🆔 Transfer ID: {}", package.transfer_id);

    // Step 2: Simulate network transfer (receive files)
    info!("📥 Receiving files...");
    let received_paths = manager.receive_files(package).await?;

    info!("✅ Files received:");
    for path in &received_paths {
        let content = fs::read_to_string(path)?;
        info!(
            "   📄 {}: {} chars",
            path.file_name().unwrap().to_string_lossy(),
            content.len()
        );
        info!(
            "      Content preview: {}",
            if content.len() > 50 {
                format!("{}...", &content[..50])
            } else {
                content
            }
        );
    }

    // Step 3: Test cleanup
    info!("🧹 Testing cleanup...");
    manager.cleanup_expired_transfers().await?;

    info!("🎉 File transfer test completed successfully!");

    // Clean up test files
    fs::remove_dir_all(&test_dir)?;
    info!("🗑️ Cleaned up test files");

    Ok(())
}
