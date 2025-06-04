// clipboard/handlers/desktop.rs
//! Desktop clipboard handler with FIXED Windows file detection
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::file_transfer::{FileTransferManager, TransferConfig};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::PathBuf;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex as TokioMutex;
use tracing::{debug, error, info, warn};

/// Desktop clipboard handler with ENHANCED Windows file detection
pub struct DesktopClipboardHandler {
    clipboard: StdMutex<Clipboard>,
    device_id: String,
    last_text: Option<String>,
    file_transfer_manager: TokioMutex<FileTransferManager>,
    last_processed_hash: Option<u64>,
    processing_file_transfer: bool,
    // 🆕 Add Windows-specific state
    last_windows_file_check: Option<std::time::Instant>,
    last_windows_files: Vec<PathBuf>,
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
            // 🆕 Initialize Windows-specific state
            last_windows_file_check: None,
            last_windows_files: Vec::new(),
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

    /// 🔧 ENHANCED: Detect files using platform-specific methods with better Windows support
    fn detect_files_smart(&mut self) -> Result<Vec<PathBuf>> {
        // Don't detect files if we're in the middle of processing a transfer
        if self.processing_file_transfer {
            return Ok(Vec::new());
        }

        debug!("🔍 Starting smart file detection...");

        // Get current clipboard text
        let clipboard_text = {
            let mut clipboard = self.clipboard.lock().unwrap();
            match clipboard.get_text() {
                Ok(text) => text,
                Err(_) => {
                    debug!("No text content in clipboard");
                    String::new()
                }
            }
        };

        // Skip if this is our own transfer summary
        if self.is_our_transfer_summary(&clipboard_text) {
            debug!("Skipping our own transfer summary");
            return Ok(Vec::new());
        }

        // 🆕 ENHANCED: Try multiple detection methods for Windows
        let platform_files = self.detect_platform_files_enhanced()?;

        // If no platform files, try text-based detection
        let detected_files = if platform_files.is_empty() {
            debug!("No platform files found, trying text-based detection");
            self.detect_files_from_text(&clipboard_text)?
        } else {
            platform_files
        };

        // 🔧 ENHANCED: More lenient deduplication for Windows
        if !detected_files.is_empty() {
            let current_hash = self.calculate_clipboard_hash(&clipboard_text, &detected_files);
            
            // Check if we've already processed this exact state recently (within 2 seconds)
            let should_skip = if let Some(last_hash) = self.last_processed_hash {
                if last_hash == current_hash {
                    // Check if enough time has passed to allow re-detection
                    if let Some(last_check) = self.last_windows_file_check {
                        last_check.elapsed() < std::time::Duration::from_secs(2)
                    } else {
                        true
                    }
                } else {
                    false
                }
            } else {
                false
            };

            if should_skip {
                debug!("Skipping duplicate detection (hash: {})", current_hash);
                return Ok(Vec::new());
            }

            // Update state
            self.last_processed_hash = Some(current_hash);
            self.last_windows_file_check = Some(std::time::Instant::now());
            self.last_windows_files = detected_files.clone();
            
            info!("🆕 NEW FILE DETECTION (hash: {}, files: {})", current_hash, detected_files.len());
            for file in &detected_files {
                info!("  📁 {}", file.display());
            }
        }

        Ok(detected_files)
    }

    /// 🆕 ENHANCED: Platform-specific file detection with multiple fallbacks
    fn detect_platform_files_enhanced(&mut self) -> Result<Vec<PathBuf>> {
        #[cfg(target_os = "windows")]
        {
            info!("🪟 Trying Windows file detection...");
            
            // Method 1: PowerShell FileDropList
            let files1 = self.detect_windows_powershell_filedrop()?;
            if !files1.is_empty() {
                info!("✅ Windows PowerShell FileDropList found {} files", files1.len());
                return Ok(files1);
            }

            // Method 2: PowerShell with different approach
            let files2 = self.detect_windows_powershell_alternative()?;
            if !files2.is_empty() {
                info!("✅ Windows PowerShell alternative found {} files", files2.len());
                return Ok(files2);
            }

            // Method 3: CMD approach
            let files3 = self.detect_windows_cmd_approach()?;
            if !files3.is_empty() {
                info!("✅ Windows CMD approach found {} files", files3.len());
                return Ok(files3);
            }

            info!("ℹ️ No Windows files detected through any method");
            Ok(Vec::new())
        }

        #[cfg(target_os = "macos")]
        {
            self.detect_macos_files_simple()
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

    /// 🆕 Method 1: PowerShell FileDropList (original approach, enhanced)
    #[cfg(target_os = "windows")]
    fn detect_windows_powershell_filedrop(&mut self) -> Result<Vec<PathBuf>> {
        use std::process::Command;

        info!("🔍 Trying PowerShell FileDropList detection...");

        let powershell_script = r#"
        try {
            $files = Get-Clipboard -Format FileDropList -ErrorAction SilentlyContinue
            if ($files) {
                $files | ForEach-Object { $_.FullName }
            }
        } catch {
            # Silent fail
        }
        "#;

        let output = Command::new("powershell")
            .arg("-NoProfile")
            .arg("-NonInteractive")
            .arg("-WindowStyle")
            .arg("Hidden")
            .arg("-Command")
            .arg(powershell_script)
            .output();

        match output {
            Ok(output) => {
                if output.status.success() {
                    let stdout_text = String::from_utf8_lossy(&output.stdout);
                    let stderr_text = String::from_utf8_lossy(&output.stderr);
                    
                    info!("PowerShell FileDropList stdout: '{}'", stdout_text.trim());
                    if !stderr_text.trim().is_empty() {
                        warn!("PowerShell FileDropList stderr: '{}'", stderr_text.trim());
                    }

                    let mut files = Vec::new();
                    for line in stdout_text.lines() {
                        let trimmed = line.trim();
                        if !trimmed.is_empty() && trimmed != "null" {
                            let path = PathBuf::from(trimmed);
                            if path.exists() {
                                files.push(path);
                                info!("  ✅ Found file: {}", trimmed);
                            } else {
                                warn!("  ❌ File does not exist: {}", trimmed);
                            }
                        }
                    }

                    return Ok(files);
                } else {
                    warn!("PowerShell FileDropList failed with status: {}", output.status);
                    let stderr_text = String::from_utf8_lossy(&output.stderr);
                    if !stderr_text.trim().is_empty() {
                        warn!("PowerShell error: {}", stderr_text.trim());
                    }
                }
            }
            Err(e) => {
                warn!("Failed to execute PowerShell FileDropList: {}", e);
            }
        }

        Ok(Vec::new())
    }

    /// 🆕 Method 2: PowerShell alternative approach
    #[cfg(target_os = "windows")]
    fn detect_windows_powershell_alternative(&mut self) -> Result<Vec<PathBuf>> {
        use std::process::Command;

        info!("🔍 Trying PowerShell alternative detection...");

        let powershell_script = r#"
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $clipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
            if ($clipboard.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
                $files = $clipboard.GetData([System.Windows.Forms.DataFormats]::FileDrop)
                $files | ForEach-Object { $_ }
            }
        } catch {
            # Silent fail
        }
        "#;

        let output = Command::new("powershell")
            .arg("-NoProfile")
            .arg("-NonInteractive")
            .arg("-WindowStyle")
            .arg("Hidden")
            .arg("-Command")
            .arg(powershell_script)
            .output();

        match output {
            Ok(output) => {
                if output.status.success() {
                    let stdout_text = String::from_utf8_lossy(&output.stdout);
                    info!("PowerShell alternative stdout: '{}'", stdout_text.trim());

                    let mut files = Vec::new();
                    for line in stdout_text.lines() {
                        let trimmed = line.trim();
                        if !trimmed.is_empty() && trimmed != "null" {
                            let path = PathBuf::from(trimmed);
                            if path.exists() {
                                files.push(path);
                                info!("  ✅ Found file (alt): {}", trimmed);
                            }
                        }
                    }

                    return Ok(files);
                }
            }
            Err(e) => {
                warn!("Failed to execute PowerShell alternative: {}", e);
            }
        }

        Ok(Vec::new())
    }

    /// 🆕 Method 3: CMD-based approach as last resort
    #[cfg(target_os = "windows")]
    fn detect_windows_cmd_approach(&mut self) -> Result<Vec<PathBuf>> {
        // This is a fallback - try to use a simple PowerShell one-liner
        use std::process::Command;

        info!("🔍 Trying CMD/PowerShell one-liner...");

        let output = Command::new("cmd")
            .arg("/c")
            .arg("powershell -Command \"Get-Clipboard -Format FileDropList 2>$null | Select-Object -ExpandProperty FullName\"")
            .output();

        match output {
            Ok(output) => {
                if output.status.success() {
                    let stdout_text = String::from_utf8_lossy(&output.stdout);
                    info!("CMD PowerShell stdout: '{}'", stdout_text.trim());

                    let mut files = Vec::new();
                    for line in stdout_text.lines() {
                        let trimmed = line.trim();
                        if !trimmed.is_empty() && !trimmed.contains("Exception") && trimmed != "null" {
                            let path = PathBuf::from(trimmed);
                            if path.exists() {
                                files.push(path);
                                info!("  ✅ Found file (cmd): {}", trimmed);
                            }
                        }
                    }

                    return Ok(files);
                }
            }
            Err(e) => {
                warn!("Failed to execute CMD approach: {}", e);
            }
        }

        Ok(Vec::new())
    }

    // Keep existing macOS and Linux detection methods unchanged
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

    /// 🔧 ENHANCED: Detect files from clipboard text analysis  
    fn detect_files_from_text(&mut self, clipboard_text: &str) -> Result<Vec<PathBuf>> {
        // Check if text looks like a filename that we should search for
        if self.looks_like_filename(clipboard_text) {
            if let Some(found_file) = self.find_file_by_name(clipboard_text.trim()) {
                info!("📝 Found file from text analysis: {}", found_file.display());
                return Ok(vec![found_file]);
            }
        }

        // 🆕 Check if text looks like a Windows file path
        if self.looks_like_windows_path(clipboard_text) {
            let path = PathBuf::from(clipboard_text.trim());
            if path.exists() {
                info!("📝 Found file from Windows path: {}", path.display());
                return Ok(vec![path]);
            }
        }

        Ok(Vec::new())
    }

    /// 🆕 Check if text looks like a Windows file path
    fn looks_like_windows_path(&self, text: &str) -> bool {
        let trimmed = text.trim();
        
        // Basic Windows path patterns
        (trimmed.len() > 3) && 
        (trimmed.contains('\\') || 
         (trimmed.len() > 2 && trimmed.chars().nth(1) == Some(':')) || // C:
         trimmed.starts_with("\\\\")) && // UNC path
        !self.is_our_transfer_summary(trimmed)
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