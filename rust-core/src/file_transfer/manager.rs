// src/file_transfer/manager.rs
use super::compression::CompressionEngine;
use super::progress::ProgressTracker;
use super::security::SecurityScanner;
use super::types::*;
use crate::{Result, SyncError};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::fs;
use tokio::sync::{mpsc, Mutex, RwLock};
use tracing::{error, info, warn};
use uuid::Uuid;

/// World-class file transfer manager
pub struct FileTransferManager {
    temp_dir: PathBuf,
    active_transfers: Arc<RwLock<HashMap<String, Arc<Mutex<TransferState>>>>>,
    progress_sender: Option<mpsc::UnboundedSender<TransferProgress>>,
    config: TransferConfig,
    security_scanner: SecurityScanner,
    compression_engine: CompressionEngine,
    #[allow(dead_code)] // 🔧 Fixed: Will be used in Phase 2
    progress_tracker: ProgressTracker,
}

/// Internal transfer state
#[derive(Debug)]
struct TransferState {
    package: FileTransferPackage,
    progress: TransferProgress,
    #[allow(dead_code)] // 🔧 Fixed: Will be used for bandwidth calculations
    start_time: Instant,
    #[allow(dead_code)] // 🔧 Fixed: Will be used for progress updates
    last_update: Instant,
    temp_files: Vec<PathBuf>,
    #[allow(dead_code)] // 🔧 Fixed: Will be used for resumable transfers
    completed_chunks: HashMap<String, Vec<bool>>, // file_id -> chunks completed
    #[allow(dead_code)] // 🔧 Fixed: Will be used for error recovery
    retry_counts: HashMap<String, u32>,
}

impl FileTransferManager {
    pub fn new(config: TransferConfig) -> Result<Self> {
        let temp_dir = std::env::temp_dir().join("local_peer_sync_v2");
        std::fs::create_dir_all(&temp_dir)?;

        Ok(Self {
            temp_dir,
            active_transfers: Arc::new(RwLock::new(HashMap::new())),
            progress_sender: None,
            config,
            security_scanner: SecurityScanner::new(),
            compression_engine: CompressionEngine::new(),
            progress_tracker: ProgressTracker::new(),
        })
    }

    /// Set progress callback for UI updates
    pub fn set_progress_callback(&mut self, sender: mpsc::UnboundedSender<TransferProgress>) {
        self.progress_sender = Some(sender);
    }

    /// Prepare files from clipboard for transfer
    pub async fn prepare_files_for_transfer(
        &self,
        file_paths: &[PathBuf],
    ) -> Result<FileTransferPackage> {
        info!("📁 Preparing {} files for transfer", file_paths.len());

        // Validate limits
        if file_paths.len() > self.config.max_files_per_transfer {
            return Err(SyncError::Config(format!(
                "Too many files: {} (max: {})",
                file_paths.len(),
                self.config.max_files_per_transfer
            )));
        }

        let transfer_id = Uuid::new_v4().to_string();
        let mut files = Vec::new();
        let mut total_size = 0u64;

        // Process each file/directory
        for path in file_paths {
            if path.is_file() {
                let file = self
                    .process_single_file(path, path.parent().unwrap_or(path))
                    .await?;
                total_size += file.size;
                files.push(file);
            } else if path.is_dir() {
                let dir_files = self.process_directory(path, path).await?;
                for file in dir_files {
                    total_size += file.size;
                    files.push(file);
                }
            }
        }

        // Validate total size
        if total_size > self.config.max_total_size {
            return Err(SyncError::Config(format!(
                "Total size too large: {} bytes (max: {} bytes)",
                total_size, self.config.max_total_size
            )));
        }

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let estimated_duration = self.estimate_transfer_duration(total_size);

        let package = FileTransferPackage {
            transfer_id,
            source_device_id: "local".to_string(), // Will be set by caller
            files,
            total_size,
            compression_ratio: 1.0, // Will be updated during transfer
            created_at: now,
            expires_at: now + (self.config.auto_cleanup_hours * 3600),
            metadata: TransferMetadata {
                title: Some(format!("{} files", file_paths.len())),
                description: None,
                priority: TransferPriority::Normal,
                estimated_duration,
                bandwidth_limit: self.config.bandwidth_limit,
                auto_cleanup: true,
            },
        };

        info!(
            "✅ Prepared transfer package: {} files, {} bytes",
            package.files.len(),
            package.total_size
        );
        Ok(package)
    }

    async fn process_single_file(
        &self,
        file_path: &Path,
        base_path: &Path,
    ) -> Result<TransferableFile> {
        let metadata = fs::metadata(file_path).await?;

        // Check file size limit
        if metadata.len() > self.config.max_file_size {
            return Err(SyncError::Config(format!(
                "File too large: {} bytes (max: {} bytes)",
                metadata.len(),
                self.config.max_file_size
            )));
        }

        let mut file = TransferableFile::new(&file_path.to_path_buf(), &base_path.to_path_buf())?;

        // Security scan
        if self.config.scan_files {
            file.permissions.scan_result = self.security_scanner.scan_file(file_path).await?;

            // Block unsafe files
            if matches!(file.permissions.scan_result, ScanResult::Blocked { .. }) {
                return Err(SyncError::Unknown(format!(
                    "File blocked by security scan: {:?}",
                    file.permissions.scan_result
                )));
            }
        }

        // Read and chunk file content
        let content = fs::read(file_path).await?;
        file.checksum = format!("{:x}", Sha256::digest(&content));

        // Create chunks
        if content.len() > self.config.chunk_size {
            file.chunks = self.create_chunks(&content, &file.mime_type).await?;
        } else {
            // Small file - single chunk
            let should_compress = self
                .compression_engine
                .should_compress(content.len() as u64, &file.mime_type);
            let (chunk_data, is_compressed) = if should_compress {
                (self.compression_engine.compress_data(&content).await?, true)
            } else {
                (content, false)
            };

            file.chunks.push(FileChunk {
                chunk_id: 0,
                offset: 0,
                size: chunk_data.len() as u32,
                checksum: format!("{:x}", Sha256::digest(&chunk_data)),
                data: chunk_data,
                is_compressed,
            });
        }

        Ok(file)
    }

    async fn process_directory(
        &self,
        dir_path: &Path,
        base_path: &Path,
    ) -> Result<Vec<TransferableFile>> {
        let mut files = Vec::new();
        let mut entries = fs::read_dir(dir_path).await?;

        while let Some(entry) = entries.next_entry().await? {
            let entry_path = entry.path();

            if entry_path.is_file() {
                match self.process_single_file(&entry_path, base_path).await {
                    Ok(file) => files.push(file),
                    Err(e) => {
                        warn!("Failed to process file {:?}: {}", entry_path, e);
                        continue;
                    }
                }
            } else if entry_path.is_dir() {
                // Use Box::pin for async recursion to avoid infinite future size
                let sub_files = Box::pin(self.process_directory(&entry_path, base_path)).await?;
                files.extend(sub_files);
            }
        }

        Ok(files)
    }

    async fn create_chunks(&self, content: &[u8], mime_type: &str) -> Result<Vec<FileChunk>> {
        let mut chunks = Vec::new();
        let chunk_size = self.config.chunk_size;
        let should_compress = self
            .compression_engine
            .should_compress(content.len() as u64, mime_type);

        for (i, chunk_data) in content.chunks(chunk_size).enumerate() {
            let (final_data, is_compressed) = if should_compress {
                match self.compression_engine.compress_data(chunk_data).await {
                    Ok(compressed) => {
                        // Only use compression if it actually reduces size
                        if compressed.len() < chunk_data.len() {
                            (compressed, true)
                        } else {
                            (chunk_data.to_vec(), false)
                        }
                    }
                    Err(_) => (chunk_data.to_vec(), false),
                }
            } else {
                (chunk_data.to_vec(), false)
            };

            chunks.push(FileChunk {
                chunk_id: i as u32,
                offset: (i * chunk_size) as u64,
                size: final_data.len() as u32,
                checksum: format!("{:x}", Sha256::digest(&final_data)),
                data: final_data,
                is_compressed,
            });
        }

        Ok(chunks)
    }

    /// Receive and reconstruct files from transfer package
    pub async fn receive_files(&mut self, package: FileTransferPackage) -> Result<Vec<PathBuf>> {
        info!(
            "📥 Receiving transfer: {} files, {} bytes",
            package.files.len(),
            package.total_size
        );

        let transfer_id = package.transfer_id.clone();
        let transfer_dir = self.temp_dir.join(&transfer_id);
        fs::create_dir_all(&transfer_dir).await?;

        // Create transfer state for progress tracking
        let transfer_state = Arc::new(Mutex::new(TransferState {
            package: package.clone(),
            progress: TransferProgress {
                transfer_id: transfer_id.clone(),
                files_completed: 0,
                files_total: package.files.len(),
                bytes_transferred: 0,
                bytes_total: package.total_size,
                current_file: None,
                current_file_progress: 0.0,
                speed_bps: 0,
                eta_seconds: 0,
                status: TransferStatus::Preparing,
                errors: Vec::new(),
            },
            start_time: Instant::now(),
            last_update: Instant::now(),
            temp_files: Vec::new(),
            completed_chunks: HashMap::new(),
            retry_counts: HashMap::new(),
        }));

        // Add to active transfers
        {
            let mut active = self.active_transfers.write().await;
            active.insert(transfer_id.clone(), Arc::clone(&transfer_state));
        }

        // Send initial progress
        self.send_progress_update(&transfer_state).await;

        let mut written_paths = Vec::new();

        // Process each file
        for (file_index, file) in package.files.iter().enumerate() {
            // Update progress
            {
                let mut state = transfer_state.lock().await;
                state.progress.current_file = Some(file.name.clone());
                state.progress.status = TransferStatus::Transferring;
            }
            self.send_progress_update(&transfer_state).await;

            let file_path = transfer_dir.join(&file.relative_path);

            // Create parent directories
            if let Some(parent) = file_path.parent() {
                fs::create_dir_all(parent).await?;
            }

            // Reconstruct file from chunks
            match self.reconstruct_file(file, &file_path).await {
                Ok(()) => {
                    written_paths.push(file_path.clone());
                    info!("✅ Reconstructed file: {}", file.name);

                    // Update progress
                    {
                        let mut state = transfer_state.lock().await;
                        state.progress.files_completed = file_index + 1;
                        state.progress.bytes_transferred += file.size;
                        state.temp_files.push(file_path);
                    }
                    self.send_progress_update(&transfer_state).await;
                }
                Err(e) => {
                    error!("Failed to reconstruct file {}: {}", file.name, e);

                    // Add error to progress
                    {
                        let mut state = transfer_state.lock().await;
                        state.progress.errors.push(TransferError {
                            error_type: "reconstruction_failed".to_string(),
                            message: e.to_string(),
                            file_path: Some(file.relative_path.clone()),
                            is_recoverable: false,
                            retry_count: 0,
                            timestamp: SystemTime::now()
                                .duration_since(UNIX_EPOCH)
                                .unwrap()
                                .as_secs(),
                        });
                    }
                    self.send_progress_update(&transfer_state).await;
                }
            }
        }

        // Mark transfer as completed
        {
            let mut state = transfer_state.lock().await;
            state.progress.status = if state.progress.errors.is_empty() {
                TransferStatus::Completed
            } else {
                TransferStatus::Failed
            };
            state.progress.current_file = None;
        }
        self.send_progress_update(&transfer_state).await;

        info!(
            "✅ Transfer completed: {} files written",
            written_paths.len()
        );
        Ok(written_paths)
    }

    async fn reconstruct_file(&self, file: &TransferableFile, output_path: &Path) -> Result<()> {
        let mut reconstructed_data = Vec::new();

        // Sort chunks by chunk_id to ensure correct order
        let mut sorted_chunks = file.chunks.clone();
        sorted_chunks.sort_by_key(|chunk| chunk.chunk_id);

        for chunk in &sorted_chunks {
            // Verify chunk checksum
            let calculated_checksum = format!("{:x}", Sha256::digest(&chunk.data));
            if calculated_checksum != chunk.checksum {
                return Err(SyncError::Unknown(format!(
                    "Chunk checksum mismatch for file {}, chunk {}",
                    file.name, chunk.chunk_id
                )));
            }

            // Decompress if needed
            let chunk_data = if chunk.is_compressed {
                self.compression_engine.decompress_data(&chunk.data).await?
            } else {
                chunk.data.clone()
            };

            reconstructed_data.extend_from_slice(&chunk_data);
        }

        // Verify file checksum
        let file_checksum = format!("{:x}", Sha256::digest(&reconstructed_data));
        if file_checksum != file.checksum {
            return Err(SyncError::Unknown(format!(
                "File checksum mismatch for file {}",
                file.name
            )));
        }

        // Write file
        fs::write(output_path, reconstructed_data).await?;

        info!(
            "✅ Reconstructed file: {} ({} chunks)",
            file.name,
            file.chunks.len()
        );
        Ok(())
    }

    /// Send progress update to callback
    async fn send_progress_update(&self, transfer_state: &Arc<Mutex<TransferState>>) {
        if let Some(ref sender) = self.progress_sender {
            let progress = {
                let state = transfer_state.lock().await;
                state.progress.clone()
            };
            let _ = sender.send(progress);
        }
    }

    fn estimate_transfer_duration(&self, total_size: u64) -> u64 {
        // Estimate based on typical network speeds
        let typical_speed = 10 * 1024 * 1024; // 10 MB/s
        if total_size == 0 {
            return 0;
        }
        (total_size / typical_speed) + 10 // Add 10 seconds overhead
    }

    /// Get current transfer progress
    pub async fn get_transfer_progress(&self, transfer_id: &str) -> Option<TransferProgress> {
        let active = self.active_transfers.read().await;
        if let Some(transfer_state) = active.get(transfer_id) {
            let state = transfer_state.lock().await;
            Some(state.progress.clone())
        } else {
            None
        }
    }

    /// Cancel an active transfer
    pub async fn cancel_transfer(&self, transfer_id: &str) -> Result<()> {
        let mut active = self.active_transfers.write().await;
        if let Some(transfer_state) = active.remove(transfer_id) {
            let mut state = transfer_state.lock().await;
            state.progress.status = TransferStatus::Cancelled;

            // Clean up temp files
            for temp_file in &state.temp_files {
                let _ = fs::remove_file(temp_file).await;
            }

            info!("🚫 Transfer cancelled: {}", transfer_id);
            Ok(())
        } else {
            Err(SyncError::Unknown(format!(
                "Transfer not found: {}",
                transfer_id
            )))
        }
    }

    /// Clean up expired transfers
    pub async fn cleanup_expired_transfers(&self) -> Result<()> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let mut to_remove = Vec::new();

        // Check active transfers for expiration
        {
            let active = self.active_transfers.read().await;
            for (transfer_id, transfer_state) in active.iter() {
                let state = transfer_state.lock().await;
                if state.package.expires_at < now {
                    to_remove.push(transfer_id.clone());
                }
            }
        }

        // Remove expired transfers
        for transfer_id in to_remove {
            self.cancel_transfer(&transfer_id).await?;
        }

        // Clean up old temp directories
        if let Ok(mut entries) = fs::read_dir(&self.temp_dir).await {
            while let Some(entry) = entries.next_entry().await? {
                if entry.path().is_dir() {
                    if let Ok(metadata) = entry.metadata().await {
                        if let Ok(created) = metadata.created() {
                            let age = SystemTime::now()
                                .duration_since(created)
                                .unwrap_or_default();
                            if age > Duration::from_secs(self.config.auto_cleanup_hours * 3600) {
                                let _ = fs::remove_dir_all(entry.path()).await;
                                info!("🗑️ Cleaned up old transfer directory: {:?}", entry.path());
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }
}
