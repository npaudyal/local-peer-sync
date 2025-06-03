//! Desktop clipboard handler - cross-platform implementation
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::sync::Mutex;
use tracing::{debug, error, info, warn};

/// Desktop clipboard handler using arboard
pub struct DesktopClipboardHandler {
    clipboard: Mutex<Clipboard>,
    device_id: String,
}

impl DesktopClipboardHandler {
    pub fn new() -> Result<Self> {
        let clipboard = Clipboard::new()
            .map_err(|e| SyncError::Unknown(format!("Failed to initialize clipboard: {}", e)))?;

        Ok(Self {
            clipboard: Mutex::new(clipboard),
            device_id: "desktop_device".to_string(),
        })
    }
}

#[async_trait::async_trait]
impl ClipboardHandler for DesktopClipboardHandler {
    async fn read_content(&mut self, _config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
        let clipboard_text = {
            let mut clipboard = self.clipboard.lock().unwrap();
            match clipboard.get_text() {
                Ok(text) => text,
                Err(_) => return Ok(None), // No text content or clipboard empty
            }
        };

        if clipboard_text.trim().is_empty() {
            return Ok(None);
        }

        debug!("Read clipboard text: {} chars", clipboard_text.len());

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
                info!("📋 Set clipboard text: {} chars", content.len());
                Ok(())
            }
            ClipboardContent::RichText { plain_text, .. } => {
                // For now, just set the plain text part
                let mut clipboard = self.clipboard.lock().unwrap();
                if let Err(e) = clipboard.set_text(plain_text) {
                    error!("Failed to set clipboard rich text: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }
                info!("📋 Set clipboard rich text: {} chars", plain_text.len());
                Ok(())
            }
            ClipboardContent::Files { paths, .. } => {
                // Convert file paths to clipboard-compatible format
                let path_strings: Vec<String> = paths.iter().map(|f| f.path.clone()).collect();
                let paths_text = path_strings.join("\n");

                let mut clipboard = self.clipboard.lock().unwrap();
                if let Err(e) = clipboard.set_text(&paths_text) {
                    error!("Failed to set clipboard file paths: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }
                info!("📋 Set clipboard file paths: {} files", paths.len());
                Ok(())
            }
            ClipboardContent::FileTransfer {
                files, transfer_id, ..
            } => {
                info!(
                    "📁 Receiving file transfer: {} files (ID: {})",
                    files.len(),
                    transfer_id
                );

                // Create a minimal file transfer manager for this operation
                let transfer_config = crate::file_transfer::types::TransferConfig::default();
                let mut file_manager =
                    crate::file_transfer::manager::FileTransferManager::new(transfer_config)?;

                // Create a transfer package
                let package = crate::file_transfer::types::FileTransferPackage {
                    transfer_id: transfer_id.clone(),
                    source_device_id: item.source_device.clone(),
                    files: files.clone(),
                    total_size: files.iter().map(|f| f.size).sum(),
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
                    metadata: crate::file_transfer::types::TransferMetadata {
                        title: Some(format!("{} files from {}", files.len(), item.source_device)),
                        description: None,
                        priority: crate::file_transfer::types::TransferPriority::Normal,
                        estimated_duration: 60,
                        bandwidth_limit: None,
                        auto_cleanup: true,
                    },
                };

                // Receive and reconstruct files
                match file_manager.receive_files(package).await {
                    Ok(written_paths) => {
                        info!(
                            "✅ Files received successfully: {} files",
                            written_paths.len()
                        );

                        // Set the file paths as text for now (could be enhanced to set as actual file references)
                        let paths_text: String = written_paths
                            .iter()
                            .map(|p| p.to_string_lossy().to_string())
                            .collect::<Vec<_>>()
                            .join("\n");

                        let mut clipboard = self.clipboard.lock().unwrap();
                        if let Err(e) = clipboard.set_text(&paths_text) {
                            error!("Failed to set received file paths to clipboard: {}", e);
                        } else {
                            info!("📋 File paths set to clipboard for pasting");
                        }
                    }
                    Err(e) => {
                        error!("Failed to receive files: {}", e);
                        return Err(e);
                    }
                }
                Ok(())
            }
            ClipboardContent::Url { url, .. } => {
                let mut clipboard = self.clipboard.lock().unwrap();
                if let Err(e) = clipboard.set_text(url) {
                    error!("Failed to set clipboard URL: {}", e);
                    return Err(SyncError::Unknown(format!("Clipboard error: {}", e)));
                }
                info!("📋 Set clipboard URL: {}", url);
                Ok(())
            }
            ClipboardContent::Image { .. } => {
                warn!("Image clipboard content not yet supported on desktop");
                Err(SyncError::Unknown(
                    "Image content not supported".to_string(),
                ))
            }
            ClipboardContent::Binary { .. } => {
                warn!("Binary clipboard content not yet supported on desktop");
                Err(SyncError::Unknown(
                    "Binary content not supported".to_string(),
                ))
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
