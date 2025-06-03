// clipboard/handlers/desktop.rs
//! Desktop clipboard handler with PROPER file transfer support
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::file_transfer::{FileTransferManager, TransferConfig};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::path::PathBuf;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex as TokioMutex;
use tracing::{error, info};

/// Desktop clipboard handler with REAL file transfer
pub struct DesktopClipboardHandler {
    clipboard: StdMutex<Clipboard>,
    device_id: String,
    last_text: Option<String>,
    file_transfer_manager: TokioMutex<FileTransferManager>,
    last_file_detection: Option<String>, // Track last file detection to avoid duplicates
}

impl DesktopClipboardHandler {
    pub fn new() -> Result<Self> {
        let clipboard = Clipboard::new()
            .map_err(|e| SyncError::Unknown(format!("Failed to initialize clipboard: {}", e)))?;

        let transfer_config = TransferConfig::default();
        let file_transfer_manager = FileTransferManager::new(transfer_config)?;

        Ok(Self {
            clipboard: StdMutex::new(clipboard),
            device_id: uuid::Uuid::new_v4().to_string(),
            last_text: None,
            file_transfer_manager: TokioMutex::new(file_transfer_manager),
            last_file_detection: None,
        })
    }

    /// FIXED: Detect files properly and verify they should be transferred
    fn detect_copied_files(&mut self) -> Result<Vec<PathBuf>> {
        let clipboard_text = {
            let mut clipboard = self.clipboard.lock().unwrap();
            match clipboard.get_text() {
                Ok(text) => text,
                Err(_) => return Ok(Vec::new()),
            }
        };

        // Check if this is the same detection as before
        if let Some(ref last) = self.last_file_detection {
            if last == &clipboard_text {
                return Ok(Vec::new()); // Already processed this
            }
        }

        // Look for file paths in clipboard text
        let potential_files = self.extract_and_validate_files(&clipboard_text);

        if !potential_files.is_empty() {
            // Update last detection
            self.last_file_detection = Some(clipboard_text);

            info!(
                "🔍 DETECTED {} potential file(s) to transfer:",
                potential_files.len()
            );
            for path in &potential_files {
                info!("  📄 {}", path.display());
            }

            Ok(potential_files)
        } else {
            Ok(Vec::new())
        }
    }

    /// Extract and validate files from clipboard text
    fn extract_and_validate_files(&self, text: &str) -> Vec<PathBuf> {
        let mut files = Vec::new();

        // Try different parsing methods
        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // Clean up the path
            let clean_path = self.clean_file_path(trimmed);
            let path = PathBuf::from(&clean_path);

            // Validate the file
            if self.is_valid_file_for_transfer(&path) {
                files.push(path);
            }
        }

        // If we only got one "file" and it's just a filename without path,
        // it's probably just text, not a real file copy
        if files.len() == 1 {
            let path = &files[0];
            if path
                .file_name()
                .map_or(false, |name| name == path.as_os_str())
            {
                // This is just a filename without path - probably not a file copy
                info!(
                    "⚠️ Detected filename without path, treating as text: {}",
                    path.display()
                );
                return Vec::new();
            }
        }

        files
    }

    /// Clean file path from clipboard
    fn clean_file_path(&self, raw_path: &str) -> String {
        raw_path
            .trim()
            .strip_prefix("file://")
            .unwrap_or(raw_path)
            .replace("%20", " ")
            .replace("\\", "/")
            .trim()
            .to_string()
    }

    /// Validate if this is a real file we should transfer
    fn is_valid_file_for_transfer(&self, path: &PathBuf) -> bool {
        // Must exist
        if !path.exists() {
            return false;
        }

        // Must be a file or directory
        if !path.is_file() && !path.is_dir() {
            return false;
        }

        // Must have a reasonable path structure
        if path.components().count() < 2 {
            // Paths like just "filename.txt" are probably not real file copies
            return false;
        }

        // Check if it's a reasonable file size (not empty, not too huge for demo)
        if path.is_file() {
            if let Ok(metadata) = std::fs::metadata(path) {
                let size = metadata.len();
                if size == 0 {
                    info!("⚠️ Skipping empty file: {}", path.display());
                    return false;
                }
                if size > 50 * 1024 * 1024 {
                    info!("⚠️ Skipping large file (>50MB): {}", path.display());
                    return false;
                }
            }
        }

        true
    }

    /// Format file size for display
    fn format_file_size(size: u64) -> String {
        const UNITS: &[&str] = &["B", "KB", "MB", "GB"];
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

    /// Set received files information to clipboard
    async fn set_received_files_info(&self, file_paths: &[PathBuf]) -> Result<()> {
        let mut info = String::new();
        info.push_str("🎉 FILE TRANSFER COMPLETE!\n\n");
        info.push_str(&format!("✅ Received {} file(s):\n\n", file_paths.len()));

        for (i, path) in file_paths.iter().enumerate() {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            let size = if path.is_file() {
                std::fs::metadata(path)
                    .map(|m| format!(" ({})", Self::format_file_size(m.len())))
                    .unwrap_or_default()
            } else {
                " (folder)".to_string()
            };

            info.push_str(&format!(
                "{}. 📄 {}{}\n   📍 {}\n\n",
                i + 1,
                name,
                size,
                path.display()
            ));
        }

        info.push_str("💡 Your files are ready to use!\n");
        info.push_str("Navigate to the paths above to access them.\n");

        let mut clipboard = self.clipboard.lock().unwrap();
        clipboard
            .set_text(&info)
            .map_err(|e| SyncError::Unknown(format!("Failed to set clipboard: {}", e)))?;

        Ok(())
    }
}

#[async_trait::async_trait]
impl ClipboardHandler for DesktopClipboardHandler {
    async fn read_content(&mut self, _config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
        // PRIORITY 1: Check for copied files
        let detected_files = self.detect_copied_files()?;

        if !detected_files.is_empty() {
            info!(
                "🚀 PROCESSING {} FILE(S) FOR TRANSFER:",
                detected_files.len()
            );

            // Prepare files for transfer
            let manager = self.file_transfer_manager.lock().await;
            match manager.prepare_files_for_transfer(&detected_files).await {
                Ok(package) => {
                    info!("✅ FILE PACKAGE PREPARED:");
                    info!("   📁 Files: {}", package.files.len());
                    info!(
                        "   💾 Total size: {}",
                        Self::format_file_size(package.total_size)
                    );
                    info!("   🆔 Transfer ID: {}", &package.transfer_id[..8]);

                    // Show what files are being transferred
                    for (i, file) in package.files.iter().enumerate().take(5) {
                        info!(
                            "   {}. 📄 {} ({})",
                            i + 1,
                            file.name,
                            Self::format_file_size(file.size)
                        );
                    }
                    if package.files.len() > 5 {
                        info!("   ... and {} more files", package.files.len() - 5);
                    }

                    let clipboard_content = ClipboardContent::FileTransfer {
                        files: package.files,
                        total_size: package.total_size,
                        transfer_id: package.transfer_id,
                    };

                    return Ok(Some(ClipboardItem::new(
                        clipboard_content,
                        self.device_id.clone(),
                    )));
                }
                Err(e) => {
                    error!("❌ Failed to prepare files: {}", e);
                }
            }
        }

        // PRIORITY 2: Check for text content
        let clipboard_text = {
            let mut clipboard = self.clipboard.lock().unwrap();
            match clipboard.get_text() {
                Ok(text) => text,
                Err(_) => return Ok(None),
            }
        };

        if clipboard_text.trim().is_empty() {
            return Ok(None);
        }

        // Check if this is the same text as before
        if let Some(ref last) = self.last_text {
            if last == &clipboard_text {
                return Ok(None);
            }
        }
        self.last_text = Some(clipboard_text.clone());

        // Only treat as text if it doesn't look like a file path
        if !self.extract_and_validate_files(&clipboard_text).is_empty() {
            // This looks like file paths, but we didn't process them as files
            // Probably means they're invalid - skip this clipboard change
            return Ok(None);
        }

        let clipboard_content = ClipboardContent::Text {
            content: clipboard_text,
            encoding: "UTF-8".to_string(),
        };

        Ok(Some(ClipboardItem::new(
            clipboard_content,
            self.device_id.clone(),
        )))
    }

    async fn write_content(&mut self, item: &ClipboardItem) -> Result<()> {
        match &item.content {
            ClipboardContent::Text { content, .. } => {
                let mut clipboard = self.clipboard.lock().unwrap();
                clipboard
                    .set_text(content)
                    .map_err(|e| SyncError::Unknown(format!("Failed to set text: {}", e)))?;

                let preview = if content.len() > 100 {
                    format!("{}...", &content[..100])
                } else {
                    content.clone()
                };
                info!("📋 ← Text received: {}", preview);
                Ok(())
            }

            ClipboardContent::FileTransfer {
                files,
                transfer_id,
                total_size,
            } => {
                info!("🚀 INCOMING FILE TRANSFER!");
                info!("📁 Files: {}", files.len());
                info!("💾 Size: {}", Self::format_file_size(*total_size));
                info!("🆔 ID: {}", &transfer_id[..8]);

                // Create transfer package
                let package = crate::file_transfer::types::FileTransferPackage {
                    transfer_id: transfer_id.clone(),
                    source_device_id: item.source_device.clone(),
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
                        + 86400,
                    metadata: crate::file_transfer::types::TransferMetadata {
                        title: Some(format!("{} files from {}", files.len(), item.source_device)),
                        description: None,
                        priority: crate::file_transfer::types::TransferPriority::High,
                        estimated_duration: 60,
                        bandwidth_limit: None,
                        auto_cleanup: true,
                    },
                };

                // Receive the files
                let mut manager = self.file_transfer_manager.lock().await;
                match manager.receive_files(package).await {
                    Ok(written_paths) => {
                        info!("🎉 FILE TRANSFER SUCCESSFUL!");
                        info!("✅ Files written to:");
                        for path in &written_paths {
                            info!("   📄 {}", path.display());
                        }

                        // Release manager lock
                        drop(manager);

                        // Set file info to clipboard
                        self.set_received_files_info(&written_paths).await?;

                        info!("📋 File transfer complete! Check clipboard for file locations.");
                    }
                    Err(e) => {
                        error!("💥 File transfer failed: {}", e);

                        drop(manager);

                        let error_msg = format!(
                            "❌ FILE TRANSFER FAILED\n\nError: {}\nSource: {} files from {}",
                            e,
                            files.len(),
                            item.source_device
                        );

                        let mut clipboard = self.clipboard.lock().unwrap();
                        let _ = clipboard.set_text(&error_msg);

                        return Err(e);
                    }
                }
                Ok(())
            }

            _ => {
                info!("📋 ← Received other content: {}", item.summary());
                Ok(())
            }
        }
    }

    async fn is_available(&self) -> bool {
        true
    }

    fn get_platform_name(&self) -> &'static str {
        if cfg!(target_os = "windows") {
            "Windows"
        } else if cfg!(target_os = "macos") {
            "macOS"
        } else if cfg!(target_os = "linux") {
            "Linux"
        } else {
            "Desktop"
        }
    }
}

impl Default for DesktopClipboardHandler {
    fn default() -> Self {
        Self::new().expect("Failed to create desktop clipboard handler")
    }
}
