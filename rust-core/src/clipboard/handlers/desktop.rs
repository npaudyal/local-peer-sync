// clipboard/handlers/desktop.rs
//! Desktop clipboard handler with IMPROVED file detection
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::file_transfer::{FileTransferManager, TransferConfig};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::path::PathBuf;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex as TokioMutex;
use tracing::{error, info};

/// Desktop clipboard handler with SMART file detection
pub struct DesktopClipboardHandler {
    clipboard: StdMutex<Clipboard>,
    device_id: String,
    last_text: Option<String>,
    file_transfer_manager: TokioMutex<FileTransferManager>,
    last_clipboard_hash: Option<String>, // Track clipboard state
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
            last_clipboard_hash: None,
        })
    }

    /// IMPROVED: Try multiple methods to detect files
    fn detect_files_from_clipboard(&mut self) -> Result<Vec<PathBuf>> {
        // Method 1: Try to get clipboard text
        let clipboard_text = {
            let mut clipboard = self.clipboard.lock().unwrap();
            match clipboard.get_text() {
                Ok(text) => text,
                Err(_) => return Ok(Vec::new()),
            }
        };

        // Create hash of current clipboard state
        let current_hash = format!("{:x}", md5::compute(&clipboard_text));

        // Check if this is the same as before
        if let Some(ref last_hash) = self.last_clipboard_hash {
            if last_hash == &current_hash {
                return Ok(Vec::new()); // No change
            }
        }
        self.last_clipboard_hash = Some(current_hash);

        info!("🔍 ANALYZING CLIPBOARD: '{}'", clipboard_text);

        // Method 2: Check if it looks like a file copy operation
        let potential_files = self.find_files_from_text(&clipboard_text);

        if !potential_files.is_empty() {
            info!(
                "✅ FOUND {} file(s) from clipboard analysis",
                potential_files.len()
            );
            return Ok(potential_files);
        }

        // Method 3: If text looks like just a filename, search for it
        if self.looks_like_filename(&clipboard_text) {
            info!(
                "🔍 Text looks like filename, searching for file: '{}'",
                clipboard_text
            );
            if let Some(found_file) = self.search_for_file(&clipboard_text) {
                info!("✅ FOUND file by searching: {}", found_file.display());
                return Ok(vec![found_file]);
            }
        }

        Ok(Vec::new())
    }

    /// Find files from clipboard text using various methods
    fn find_files_from_text(&self, text: &str) -> Vec<PathBuf> {
        let mut files = Vec::new();

        // Split by various delimiters
        for line in text.lines() {
            for part in line.split('\0') {
                // Null-separated paths
                let trimmed = part.trim();
                if trimmed.is_empty() {
                    continue;
                }

                let cleaned = self.clean_path(trimmed);
                let path = PathBuf::from(&cleaned);

                if self.is_valid_file(&path) {
                    info!("📁 Found valid file: {}", path.display());
                    files.push(path);
                }
            }
        }

        files
    }

    /// Clean up path string
    fn clean_path(&self, raw: &str) -> String {
        raw.trim()
            .strip_prefix("file://")
            .unwrap_or(raw)
            .replace("%20", " ")
            .replace("\\", "/")
            .to_string()
    }

    /// Check if text looks like just a filename
    fn looks_like_filename(&self, text: &str) -> bool {
        let trimmed = text.trim();

        // Should be short and look like a filename
        if trimmed.len() > 100 || trimmed.len() < 3 {
            return false;
        }

        // Should not contain path separators (just filename)
        if trimmed.contains('/') || trimmed.contains('\\') {
            return false;
        }

        // Should have an extension
        if !trimmed.contains('.') {
            return false;
        }

        // Common file extensions
        let extensions = [
            ".txt", ".pdf", ".doc", ".docx", ".jpg", ".png", ".gif", ".mp4", ".mp3", ".zip",
            ".json", ".xml", ".csv", ".py", ".rs", ".js", ".html", ".css",
        ];

        extensions
            .iter()
            .any(|ext| trimmed.to_lowercase().ends_with(ext))
    }

    /// Search for a file by filename in common locations
    fn search_for_file(&self, filename: &str) -> Option<PathBuf> {
        let search_locations = self.get_search_locations();

        for location in search_locations {
            let potential_path = location.join(filename);
            if self.is_valid_file(&potential_path) {
                return Some(potential_path);
            }
        }

        None
    }

    /// Get common locations to search for files
    fn get_search_locations(&self) -> Vec<PathBuf> {
        let mut locations = Vec::new();

        // Add common desktop/download locations
        if let Some(home) = dirs::home_dir() {
            locations.push(home.join("Desktop"));
            locations.push(home.join("Downloads"));
            locations.push(home.join("Documents"));

            // Platform-specific locations
            #[cfg(target_os = "macos")]
            {
                locations.push(home.join("Downloads"));
                locations.push(PathBuf::from("/Users/Shared"));
            }

            #[cfg(target_os = "windows")]
            {
                locations.push(home.join("Downloads"));
                locations.push(home.join("Documents"));
            }
        }

        // Current directory
        if let Ok(current_dir) = std::env::current_dir() {
            locations.push(current_dir);
        }

        locations
    }

    /// Validate if path is a real file we can transfer
    fn is_valid_file(&self, path: &PathBuf) -> bool {
        if !path.exists() {
            return false;
        }

        if path.is_file() {
            // Check file size
            if let Ok(metadata) = std::fs::metadata(path) {
                let size = metadata.len();
                if size == 0 || size > 100 * 1024 * 1024 {
                    // 0 bytes or > 100MB
                    return false;
                }
            }
            return true;
        }

        if path.is_dir() {
            return true;
        }

        false
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
}

#[async_trait::async_trait]
impl ClipboardHandler for DesktopClipboardHandler {
    async fn read_content(&mut self, _config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
        // Try to detect files first
        let detected_files = self.detect_files_from_clipboard()?;

        if !detected_files.is_empty() {
            info!("🚀 DETECTED {} FILE(S) FOR TRANSFER!", detected_files.len());

            for file in &detected_files {
                info!("  📄 {}", file.display());
            }

            // Prepare files for transfer
            let manager = self.file_transfer_manager.lock().await;
            match manager.prepare_files_for_transfer(&detected_files).await {
                Ok(package) => {
                    info!("✅ FILE PACKAGE READY:");
                    info!("   📁 Files: {}", package.files.len());
                    info!(
                        "   💾 Total: {}",
                        Self::format_file_size(package.total_size)
                    );
                    info!("   🆔 Transfer ID: {}", &package.transfer_id[..8]);

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

        // Fall back to text handling
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

        info!(
            "📋 Text clipboard change: {}",
            if clipboard_text.len() > 50 {
                format!("{}...", &clipboard_text[..50])
            } else {
                clipboard_text.clone()
            }
        );

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
                info!("📋 ← Received text: {}", preview);
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

                // Show what files are coming
                for (i, file) in files.iter().enumerate().take(3) {
                    info!(
                        "   {}. 📄 {} ({})",
                        i + 1,
                        file.name,
                        Self::format_file_size(file.size)
                    );
                }
                if files.len() > 3 {
                    info!("   ... and {} more", files.len() - 3);
                }

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
                        info!("🎉 FILE TRANSFER SUCCESS!");
                        for path in &written_paths {
                            info!("   ✅ {}", path.display());
                        }

                        drop(manager);

                        // Create file info for clipboard
                        let mut info = String::new();
                        info.push_str("🎉 FILES RECEIVED!\n\n");
                        for (i, path) in written_paths.iter().enumerate() {
                            let name = path.file_name().unwrap_or_default().to_string_lossy();
                            info.push_str(&format!(
                                "{}. 📄 {}\n   📍 {}\n\n",
                                i + 1,
                                name,
                                path.display()
                            ));
                        }
                        info.push_str("💡 Files are ready to use!");

                        let mut clipboard = self.clipboard.lock().unwrap();
                        let _ = clipboard.set_text(&info);

                        info!("📋 File transfer complete!");
                    }
                    Err(e) => {
                        error!("💥 Transfer failed: {}", e);
                        drop(manager);

                        let error_msg = format!("❌ File transfer failed: {}", e);
                        let mut clipboard = self.clipboard.lock().unwrap();
                        let _ = clipboard.set_text(&error_msg);

                        return Err(e);
                    }
                }
                Ok(())
            }

            _ => {
                info!("📋 ← Received: {}", item.summary());
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
