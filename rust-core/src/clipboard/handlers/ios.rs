//! iOS clipboard handler - delegates to Swift through FFI
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::{Result, SyncError};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use tracing::{info, warn};

/// iOS clipboard handler that delegates to Swift/UIKit
pub struct IOSClipboardHandler {
    device_id: String,
}

impl IOSClipboardHandler {
    pub fn new() -> Result<Self> {
        Ok(Self {
            device_id: "ios_device".to_string(),
        })
    }

    fn content_to_text(&self, item: &ClipboardItem) -> String {
        match &item.content {
            ClipboardContent::Text { content, .. } => content.clone(),
            ClipboardContent::RichText { plain_text, .. } => plain_text.clone(),
            ClipboardContent::Url { url, .. } => url.clone(),
            ClipboardContent::Files { paths, .. } => paths
                .iter()
                .map(|f| f.path.clone())
                .collect::<Vec<_>>()
                .join("\n"),
            ClipboardContent::FileTransfer {
                files, transfer_id, ..
            } => {
                format!(
                    "File Transfer: {} files (ID: {})",
                    files.len(),
                    &transfer_id[..8]
                )
            }
            ClipboardContent::Image { width, height, .. } => {
                format!("Image ({}x{})", width, height)
            }
            ClipboardContent::Binary { mime_type, .. } => {
                format!("Binary content ({})", mime_type)
            }
        }
    }

    fn truncate_for_log(text: &str, max_len: usize) -> String {
        if text.len() > max_len {
            format!("{}...", &text[..max_len])
        } else {
            text.to_string()
        }
    }
}

#[async_trait::async_trait]
impl ClipboardHandler for IOSClipboardHandler {
    async fn read_content(&mut self, _config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
        #[cfg(target_os = "ios")]
        {
            let content = unsafe { ios_get_clipboard_text() };

            if content.is_null() {
                return Ok(None);
            }

            let text = unsafe {
                let c_str = CStr::from_ptr(content);
                let rust_string = c_str.to_string_lossy().to_string();
                ios_free_string(content);
                rust_string
            };

            if text.is_empty() {
                return Ok(None);
            }

            let clipboard_content = ClipboardContent::Text {
                content: text,
                encoding: "UTF-8".to_string(),
            };

            Ok(Some(ClipboardItem::new(
                clipboard_content,
                self.device_id.clone(),
            )))
        }

        #[cfg(not(target_os = "ios"))]
        {
            Ok(None)
        }
    }

    async fn write_content(&mut self, item: &ClipboardItem) -> Result<()> {
        #[cfg(target_os = "ios")]
        {
            match &item.content {
                ClipboardContent::Text { content, .. } => {
                    let c_content = CString::new(content.as_str())
                        .map_err(|e| SyncError::Unknown(format!("Invalid text content: {}", e)))?;

                    let success = unsafe { ios_set_clipboard_text(c_content.as_ptr()) };

                    if success == 1 {
                        info!(
                            "📱 Set iOS clipboard text: {}",
                            Self::truncate_for_log(content, 50)
                        );
                        Ok(())
                    } else {
                        Err(SyncError::Unknown(
                            "Failed to set iOS clipboard text".to_string(),
                        ))
                    }
                }
                ClipboardContent::FileTransfer {
                    files, transfer_id, ..
                } => {
                    warn!("📱 iOS file transfer received but not yet fully implemented");

                    // For now, just set a summary as text
                    let summary = format!(
                        "Received {} files (Transfer: {})",
                        files.len(),
                        &transfer_id[..8]
                    );
                    let c_content = CString::new(summary.as_str()).map_err(|e| {
                        SyncError::Unknown(format!("Invalid summary content: {}", e))
                    })?;

                    let success = unsafe { ios_set_clipboard_text(c_content.as_ptr()) };

                    if success == 1 {
                        info!("📱 Set iOS clipboard file transfer summary");
                        Ok(())
                    } else {
                        Err(SyncError::Unknown(
                            "Failed to set iOS clipboard file transfer summary".to_string(),
                        ))
                    }
                }
                _ => {
                    warn!("📱 iOS clipboard: Unsupported content type, converting to text");
                    let text_content = self.content_to_text(item);
                    let c_content = CString::new(text_content.as_str()).map_err(|e| {
                        SyncError::Unknown(format!("Invalid fallback content: {}", e))
                    })?;

                    let success = unsafe { ios_set_clipboard_text(c_content.as_ptr()) };

                    if success == 1 {
                        Ok(())
                    } else {
                        Err(SyncError::Unknown(
                            "Failed to set iOS clipboard fallback text".to_string(),
                        ))
                    }
                }
            }
        }

        #[cfg(not(target_os = "ios"))]
        {
            Err(SyncError::Unknown(
                "iOS clipboard not supported on this platform".to_string(),
            ))
        }
    }

    async fn is_available(&self) -> bool {
        true
    }

    fn get_platform_name(&self) -> &'static str {
        "iOS"
    }
}

extern "C" {
    /// Get clipboard text from iOS (implemented in Swift)
    fn ios_get_clipboard_text() -> *mut c_char;

    /// Set clipboard text on iOS (implemented in Swift)
    fn ios_set_clipboard_text(text: *const c_char) -> c_int;

    /// Free string allocated by iOS (implemented in Swift)
    fn ios_free_string(ptr: *mut c_char);
}
