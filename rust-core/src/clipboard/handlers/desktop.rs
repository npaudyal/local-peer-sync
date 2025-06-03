//! Desktop clipboard handler with advanced file transfer support
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::file_transfer::{FileTransferManager, TransferConfig};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::path::PathBuf;
use std::sync::Mutex as StdMutex; // Rename to avoid confusion
use tokio::sync::Mutex as TokioMutex; // Use tokio's async Mutex for FileTransferManager
use tracing::{error, warn};

/// Desktop clipboard handler with file transfer support
pub struct DesktopClipboardHandler {
    clipboard: StdMutex<Clipboard>, // Keep std::Mutex for sync operations
    device_id: String,
    last_text: Option<String>,
    file_transfer_manager: TokioMutex<FileTransferManager>, // Use tokio::Mutex for async operations
}

impl DesktopClipboardHandler {
    pub fn new() -> Result<Self> {
        let clipboard = Clipboard::new()
            .map_err(|e| SyncError::Unknown(format!("Failed to initialize clipboard: {}", e)))?;

        let transfer_config = TransferConfig::default();
        let file_transfer_manager = FileTransferManager::new(transfer_config)?;

        Ok(Self {
            clipboard: StdMutex::new(clipboard),
            device_id: "desktop_device".to_string(),
            last_text: None,
            file_transfer_manager: TokioMutex::new(file_transfer_manager),
        })
    }

    /// Extract file paths from clipboard text and verify they exist
    fn extract_existing_file_paths(&self, text: &str) -> Vec<PathBuf> {
        let lines: Vec<&str> = text.lines().collect();
        let mut file_paths = Vec::new();

        // Handle different clipboard formats
        for line in lines {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // Remove common prefixes from file managers
            let clean_path = trimmed
                .strip_prefix("file://")
                .unwrap_or(trimmed)
                .replace("%20", " "); // URL decode spaces

            let path = PathBuf::from(&clean_path);

            // Only include files that actually exist
            if path.exists() && path.is_file() {
                println!("📄 Found file: {}", path.display());
                file_paths.push(path);
            } else if path.exists() && path.is_dir() {
                println!("📁 Found directory: {}", path.display());
                file_paths.push(path);
            }
        }

        file_paths
    }

    /// Check if text looks like file paths
    fn looks_like_file_paths(&self, text: &str) -> bool {
        let lines: Vec<&str> = text.lines().collect();

        // If multiple lines, check if most look like paths
        if lines.len() > 1 {
            let path_like_count = lines
                .iter()
                .filter(|line| {
                    let trimmed = line.trim();
                    !trimmed.is_empty()
                        && (trimmed.contains('/')
                            || trimmed.contains('\\')
                            || trimmed.starts_with("file://")
                            || self.has_file_extension(trimmed))
                })
                .count();

            return path_like_count >= (lines.len() / 2);
        }

        // Single line - check if it looks like a file path
        let trimmed = text.trim();
        (trimmed.contains('/') || trimmed.contains('\\') || trimmed.starts_with("file://"))
            && (self.has_file_extension(trimmed) || PathBuf::from(trimmed).exists())
    }

    /// Check if string has a file extension
    fn has_file_extension(&self, text: &str) -> bool {
        let common_extensions = [
            ".txt", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".jpg", ".jpeg",
            ".png", ".gif", ".svg", ".bmp", ".tiff", ".webp", ".mp3", ".mp4", ".mov", ".avi",
            ".mkv", ".wav", ".flac", ".zip", ".7z", ".tar", ".gz", ".rar", ".json", ".xml", ".csv",
            ".yaml", ".toml", ".py", ".rs", ".js", ".ts", ".java", ".cpp", ".c", ".h", ".html",
            ".css", ".md", ".sql",
        ];

        common_extensions
            .iter()
            .any(|ext| text.to_lowercase().ends_with(ext))
    }

    /// Set file paths to clipboard in a platform-appropriate way
    async fn set_file_paths_to_clipboard(&self, paths: &[PathBuf]) -> Result<()> {
        if paths.is_empty() {
            return Ok(());
        }

        let file_list = paths
            .iter()
            .enumerate()
            .map(|(i, p)| {
                if p.is_file() {
                    format!(
                        "{}. 📄 {} ({})",
                        i + 1,
                        p.file_name().unwrap_or_default().to_string_lossy(),
                        p.display()
                    )
                } else {
                    format!(
                        "{}. 📁 {} ({})",
                        i + 1,
                        p.file_name().unwrap_or_default().to_string_lossy(),
                        p.display()
                    )
                }
            })
            .collect::<Vec<_>>()
            .join("\n");

        let message = format!(
            "📁 {} file(s) received and saved:\n\n{}\n\n💡 Files are saved to your system.\nYou can navigate to the paths above to access them.\n\n🎯 Next: We're working on making these directly pasteable in file explorer!",
            paths.len(),
            file_list
        );

        let mut clipboard = self.clipboard.lock().unwrap();
        clipboard.set_text(&message).map_err(|e| {
            SyncError::Unknown(format!("Failed to set file info to clipboard: {}", e))
        })?;

        println!("📋 File location info copied to clipboard");
        Ok(())
    }
}

#[async_trait::async_trait]
impl ClipboardHandler for DesktopClipboardHandler {
    async fn read_content(&mut self, _config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
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

        // Check if this is the same as last time
        if let Some(ref last) = self.last_text {
            if last == &clipboard_text {
                return Ok(None);
            }
        }
        self.last_text = Some(clipboard_text.clone());

        // Priority 1: Check if clipboard contains file paths
        if self.looks_like_file_paths(&clipboard_text) {
            let file_paths = self.extract_existing_file_paths(&clipboard_text);

            if !file_paths.is_empty() {
                println!(
                    "📁 Detected {} files/folders copied to clipboard",
                    file_paths.len()
                );

                // Use tokio::Mutex which is Send-safe across await points
                let manager = self.file_transfer_manager.lock().await;
                match manager.prepare_files_for_transfer(&file_paths).await {
                    Ok(package) => {
                        println!(
                            "📦 Prepared file package: {} files, {} bytes",
                            package.files.len(),
                            package.total_size
                        );

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
                        error!("Failed to prepare files for transfer: {}", e);
                        println!("⚠️  File transfer preparation failed, syncing as text instead");
                    }
                }
            }
        }

        // Priority 2: Regular text content
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
                if let Err(e) = clipboard.set_text(content) {
                    error!("Failed to set clipboard text: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }

                let preview = if content.len() > 100 {
                    format!("{}...", &content[..100])
                } else {
                    content.clone()
                };
                println!("📋 ← Received text: {}", preview);
                Ok(())
            }

            ClipboardContent::FileTransfer {
                files,
                transfer_id,
                total_size,
            } => {
                println!(
                    "📁 ← Receiving {} files ({} bytes, ID: {})",
                    files.len(),
                    total_size,
                    &transfer_id[..8]
                );

                // Create a transfer package for processing
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
                        priority: crate::file_transfer::types::TransferPriority::Normal,
                        estimated_duration: 60,
                        bandwidth_limit: None,
                        auto_cleanup: true,
                    },
                };

                // Use tokio::Mutex for async operations
                let mut manager = self.file_transfer_manager.lock().await;
                match manager.receive_files(package).await {
                    Ok(written_paths) => {
                        println!("✅ Successfully received {} files:", written_paths.len());
                        for (i, path) in written_paths.iter().enumerate() {
                            println!("   {}. 📄 {}", i + 1, path.display());
                        }

                        // Release the manager lock before the next async call
                        drop(manager);

                        // Set file information to clipboard
                        self.set_file_paths_to_clipboard(&written_paths).await?;

                        println!(
                            "🎉 File transfer completed! Check your clipboard for file locations."
                        );
                    }
                    Err(e) => {
                        error!("Failed to receive files: {}", e);

                        // Release the manager lock before using clipboard
                        drop(manager);

                        // Set error message to clipboard
                        let error_msg = format!(
                            "❌ File transfer failed: {}\n\nSource: {} files from {}",
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

            ClipboardContent::RichText { plain_text, .. } => {
                let mut clipboard = self.clipboard.lock().unwrap();
                if let Err(e) = clipboard.set_text(plain_text) {
                    error!("Failed to set clipboard rich text: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }
                println!("📋 ← Received rich text: {} chars", plain_text.len());
                Ok(())
            }

            ClipboardContent::Url { url, .. } => {
                let mut clipboard = self.clipboard.lock().unwrap();
                if let Err(e) = clipboard.set_text(url) {
                    error!("Failed to set clipboard URL: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }
                println!("📋 ← Received URL: {}", url);
                Ok(())
            }

            ClipboardContent::Files { paths, .. } => {
                let paths_text: String = paths
                    .iter()
                    .map(|f| f.path.clone())
                    .collect::<Vec<_>>()
                    .join("\n");

                let mut clipboard = self.clipboard.lock().unwrap();
                if let Err(e) = clipboard.set_text(&paths_text) {
                    error!("Failed to set clipboard file paths: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }
                println!("📋 ← Received file paths: {} files", paths.len());
                Ok(())
            }

            ClipboardContent::Image { .. } => {
                warn!("📸 Image clipboard content not yet supported");
                let msg = "📸 Image content received but not yet supported for display";
                let mut clipboard = self.clipboard.lock().unwrap();
                let _ = clipboard.set_text(msg);
                Ok(())
            }

            ClipboardContent::Binary { mime_type, .. } => {
                warn!(
                    "📦 Binary clipboard content not yet supported: {}",
                    mime_type
                );
                let msg = format!(
                    "📦 Binary content received ({}), but display not yet supported",
                    mime_type
                );
                let mut clipboard = self.clipboard.lock().unwrap();
                let _ = clipboard.set_text(&msg);
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
