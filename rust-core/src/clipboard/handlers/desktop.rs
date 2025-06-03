// clipboard/handlers/desktop.rs
//! Desktop clipboard handler with FIXED deduplication and proper message types
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::file_transfer::{FileTransferManager, TransferConfig};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::PathBuf;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex as TokioMutex;
use tracing::{error, info};

/// Desktop clipboard handler with PROPER file transfer
pub struct DesktopClipboardHandler {
    clipboard: StdMutex<Clipboard>,
    device_id: String,
    last_text: Option<String>,
    file_transfer_manager: TokioMutex<FileTransferManager>,
    last_processed_hash: Option<u64>, // Hash of last processed content
    processing_file_transfer: bool,   // Flag to prevent feedback loops
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
            last_processed_hash: None,
            processing_file_transfer: false,
        })
    }

    /// Calculate hash of clipboard state for deduplication
    fn calculate_clipboard_hash(&self, text: &str, files: &[PathBuf]) -> u64 {
        let mut hasher = DefaultHasher::new();
        text.hash(&mut hasher);
        for file in files {
            file.hash(&mut hasher);
        }
        hasher.finish()
    }

    /// Check if text is our own file transfer summary
    fn is_our_transfer_summary(&self, text: &str) -> bool {
        text.starts_with("🎉 FILES RECEIVED")
            || (text.starts_with("File Transfer:")
                && text.contains("files")
                && text.contains("bytes"))
    }

    /// Detect files using platform-specific methods
    fn detect_files_smart(&mut self) -> Result<Vec<PathBuf>> {
        // Don't detect files if we're in the middle of processing a transfer
        if self.processing_file_transfer {
            return Ok(Vec::new());
        }

        // Get current clipboard text
        let clipboard_text = {
            let mut clipboard = self.clipboard.lock().unwrap();
            match clipboard.get_text() {
                Ok(text) => text,
                Err(_) => return Ok(Vec::new()),
            }
        };

        // Skip if this is our own transfer summary
        if self.is_our_transfer_summary(&clipboard_text) {
            return Ok(Vec::new());
        }

        // Try platform-specific detection first
        let platform_files = self.detect_platform_files()?;

        // If no platform files, try text-based detection
        let detected_files = if platform_files.is_empty() {
            self.detect_files_from_text(&clipboard_text)?
        } else {
            platform_files
        };

        // Calculate hash of current state
        let current_hash = self.calculate_clipboard_hash(&clipboard_text, &detected_files);

        // Check if we've already processed this exact state
        if let Some(last_hash) = self.last_processed_hash {
            if last_hash == current_hash {
                return Ok(Vec::new()); // Already processed
            }
        }

        // Update hash if we found files
        if !detected_files.is_empty() {
            self.last_processed_hash = Some(current_hash);
            info!("🆕 NEW FILE DETECTION (hash: {})", current_hash);
        }

        Ok(detected_files)
    }

    /// Platform-specific file detection
    fn detect_platform_files(&mut self) -> Result<Vec<PathBuf>> {
        #[cfg(target_os = "macos")]
        {
            self.detect_macos_files_simple()
        }

        #[cfg(target_os = "windows")]
        {
            self.detect_windows_files_simple()
        }

        #[cfg(target_os = "linux")]
        {
            self.detect_linux_files_simple()
        }

        #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
        {
            Ok(Vec::new())
        }
    }

    #[cfg(target_os = "macos")]
    fn detect_macos_files_simple(&mut self) -> Result<Vec<PathBuf>> {
        use std::process::Command;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(
                r#"
                try
                    set theClipboard to the clipboard as «class fURL»
                    set theList to {}
                    repeat with i from 1 to count of theClipboard
                        set end of theList to POSIX path of (item i of theClipboard)
                    end repeat
                    set AppleScript's text item delimiters to "\n"
                    theList as string
                on error
                    ""
                end try
            "#,
            )
            .output();

        if let Ok(output) = output {
            if output.status.success() {
                let paths_text = String::from_utf8_lossy(&output.stdout);
                let trimmed = paths_text.trim();

                if !trimmed.is_empty() && trimmed != "missing value" {
                    let mut files = Vec::new();
                    for line in trimmed.lines() {
                        let path = PathBuf::from(line.trim());
                        if path.exists() {
                            files.push(path);
                        }
                    }
                    return Ok(files);
                }
            }
        }

        Ok(Vec::new())
    }

    #[cfg(target_os = "windows")]
    fn detect_windows_files_simple(&mut self) -> Result<Vec<PathBuf>> {
        use std::process::Command;

        let output = Command::new("powershell")
            .arg("-Command")
            .arg("Get-Clipboard -Format FileDropList | ForEach-Object { $_.FullName }")
            .output();

        if let Ok(output) = output {
            if output.status.success() {
                let paths_text = String::from_utf8_lossy(&output.stdout);
                let mut files = Vec::new();

                for line in paths_text.lines() {
                    let trimmed = line.trim();
                    if !trimmed.is_empty() {
                        let path = PathBuf::from(trimmed);
                        if path.exists() {
                            files.push(path);
                        }
                    }
                }

                return Ok(files);
            }
        }

        Ok(Vec::new())
    }

    #[cfg(target_os = "linux")]
    fn detect_linux_files_simple(&mut self) -> Result<Vec<PathBuf>> {
        use std::process::Command;

        let output = Command::new("xclip")
            .args(&["-selection", "clipboard", "-t", "text/uri-list", "-o"])
            .output();

        if let Ok(output) = output {
            if output.status.success() {
                let content = String::from_utf8_lossy(&output.stdout);
                let mut files = Vec::new();

                for line in content.lines() {
                    if line.starts_with("file://") {
                        let path_str = line.strip_prefix("file://").unwrap_or(line);
                        let path = PathBuf::from(path_str);
                        if path.exists() {
                            files.push(path);
                        }
                    }
                }

                return Ok(files);
            }
        }

        Ok(Vec::new())
    }

    /// Detect files from clipboard text analysis
    fn detect_files_from_text(&mut self, clipboard_text: &str) -> Result<Vec<PathBuf>> {
        // Check if text looks like a filename that we should search for
        if self.looks_like_filename(clipboard_text) {
            if let Some(found_file) = self.find_file_by_name(clipboard_text.trim()) {
                return Ok(vec![found_file]);
            }
        }

        Ok(Vec::new())
    }

    /// Check if text looks like just a filename
    fn looks_like_filename(&self, text: &str) -> bool {
        let trimmed = text.trim();

        // Basic checks
        if trimmed.len() < 3 || trimmed.len() > 100 {
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

        // Should not be our transfer summary
        if self.is_our_transfer_summary(trimmed) {
            return false;
        }

        // Should look like a real filename
        trimmed
            .chars()
            .all(|c| c.is_alphanumeric() || ".-_ ".contains(c))
    }

    /// Find file by searching common locations
    fn find_file_by_name(&self, filename: &str) -> Option<PathBuf> {
        let search_dirs = vec![
            std::env::current_dir().ok(),
            dirs::desktop_dir(),
            dirs::download_dir(),
            dirs::document_dir(),
            dirs::home_dir(),
        ];

        for dir_opt in search_dirs {
            if let Some(dir) = dir_opt {
                let potential_path = dir.join(filename);
                if potential_path.exists() {
                    return Some(potential_path);
                }
            }
        }

        None
    }

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
        let detected_files = self.detect_files_smart()?;

        if !detected_files.is_empty() {
            info!(
                "🚀 DETECTED {} NEW FILE(S) FOR TRANSFER!",
                detected_files.len()
            );

            // Set processing flag to prevent feedback loops
            self.processing_file_transfer = true;

            for file in &detected_files {
                info!("  📁 {}", file.display());
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

                    // Create FileTransfer content (NOT text)
                    let clipboard_content = ClipboardContent::FileTransfer {
                        files: package.files,
                        total_size: package.total_size,
                        transfer_id: package.transfer_id,
                    };

                    // Reset processing flag
                    self.processing_file_transfer = false;

                    return Ok(Some(ClipboardItem::new(
                        clipboard_content,
                        self.device_id.clone(),
                    )));
                }
                Err(e) => {
                    error!("❌ Failed to prepare files: {}", e);
                    self.processing_file_transfer = false;
                }
            }
        }

        // Handle text content (only if not processing files)
        if !self.processing_file_transfer {
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

            // Skip our own transfer summaries
            if self.is_our_transfer_summary(&clipboard_text) {
                return Ok(None);
            }

            // Check if this is the same text as before
            if let Some(ref last) = self.last_text {
                if last == &clipboard_text {
                    return Ok(None);
                }
            }
            self.last_text = Some(clipboard_text.clone());

            let clipboard_content = ClipboardContent::Text {
                content: clipboard_text,
                encoding: "UTF-8".to_string(),
            };

            return Ok(Some(ClipboardItem::new(
                clipboard_content,
                self.device_id.clone(),
            )));
        }

        Ok(None)
    }

    async fn write_content(&mut self, item: &ClipboardItem) -> Result<()> {
        match &item.content {
            ClipboardContent::Text { content, .. } => {
                // Scope the clipboard guard to avoid holding it across await
                {
                    let mut clipboard = self.clipboard.lock().unwrap();
                    clipboard
                        .set_text(content)
                        .map_err(|e| SyncError::Unknown(format!("Failed to set text: {}", e)))?;
                } // Guard is dropped here

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

                // Set processing flag to prevent interference
                self.processing_file_transfer = true;

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

                        drop(manager); // Drop manager before clipboard operations

                        // Create file info for clipboard (but mark it as ours)
                        let mut info = String::new();
                        info.push_str("🎉 FILES RECEIVED SUCCESSFULLY!\n\n");

                        for (i, path) in written_paths.iter().enumerate() {
                            let name = path.file_name().unwrap_or_default().to_string_lossy();
                            let size_info = if path.is_file() {
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
                                size_info,
                                path.display()
                            ));
                        }

                        info.push_str("💡 Your files are ready to use!\n");
                        info.push_str(&format!("🎊 Transfer from: {}", item.source_device));

                        // Set to clipboard (scoped to drop guard before await)
                        {
                            let mut clipboard = self.clipboard.lock().unwrap();
                            let _ = clipboard.set_text(&info);
                        } // Guard is dropped here

                        // Reset processing flag after a delay
                        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                        self.processing_file_transfer = false;

                        info!("📋 File transfer complete! File info copied to clipboard.");
                    }
                    Err(e) => {
                        error!("💥 Transfer failed: {}", e);
                        drop(manager); // Drop manager before clipboard operations

                        let error_msg = format!(
                            "❌ FILE TRANSFER FAILED\n\nError: {}\nSource: {} files from {}",
                            e,
                            files.len(),
                            item.source_device
                        );

                        // Set error to clipboard (scoped to drop guard)
                        {
                            let mut clipboard = self.clipboard.lock().unwrap();
                            let _ = clipboard.set_text(&error_msg);
                        } // Guard is dropped here

                        self.processing_file_transfer = false;
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
