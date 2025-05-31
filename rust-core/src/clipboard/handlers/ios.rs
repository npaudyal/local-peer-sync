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
            let content = { ios_get_clipboard_text() };

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

                    let success = { ios_set_clipboard_text(c_content.as_ptr()) };

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

                ClipboardContent::Image {
                    primary_data,
                    width,
                    height,
                    ..
                } => {
                    let success = {
                        ios_set_clipboard_image(
                            primary_data.as_ptr(),
                            primary_data.len(),
                            *width,
                            *height,
                        )
                    };

                    if success == 1 {
                        info!("📱 Set iOS clipboard image: {}x{}", width, height);
                        Ok(())
                    } else {
                        Err(SyncError::Unknown(
                            "Failed to set iOS clipboard image".to_string(),
                        ))
                    }
                }

                ClipboardContent::Url { url, .. } => {
                    let c_url = CString::new(url.as_str())
                        .map_err(|e| SyncError::Unknown(format!("Invalid URL content: {}", e)))?;

                    let success = { ios_set_clipboard_url(c_url.as_ptr()) };

                    if success == 1 {
                        info!("📱 Set iOS clipboard URL: {}", url);
                        Ok(())
                    } else {
                        Err(SyncError::Unknown(
                            "Failed to set iOS clipboard URL".to_string(),
                        ))
                    }
                }

                _ => {
                    warn!("📱 iOS clipboard: Unsupported content type, converting to text");
                    let text_content = self.content_to_text(item);
                    let c_content = CString::new(text_content.as_str()).map_err(|e| {
                        SyncError::Unknown(format!("Invalid fallback content: {}", e))
                    })?;

                    let success = { ios_set_clipboard_text(c_content.as_ptr()) };

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

// STUB IMPLEMENTATIONS - These will be overridden by Swift when linking with iOS app
// These are weak symbols that allow Swift to override them

#[no_mangle]
pub extern "C" fn ios_get_clipboard_text() -> *mut c_char {
    // Stub implementation - returns null
    // Will be overridden by Swift implementation
    ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn ios_set_clipboard_text(_text: *const c_char) -> c_int {
    // Stub implementation - returns failure
    // Will be overridden by Swift implementation
    0
}

#[no_mangle]
pub extern "C" fn ios_set_clipboard_image(
    _data: *const u8,
    _len: usize,
    _width: u32,
    _height: u32,
) -> c_int {
    // Stub implementation - returns failure
    // Will be overridden by Swift implementation
    0
}

#[no_mangle]
pub extern "C" fn ios_set_clipboard_url(_url: *const c_char) -> c_int {
    // Stub implementation - returns failure
    // Will be overridden by Swift implementation
    0
}

#[no_mangle]
pub extern "C" fn ios_free_string(_ptr: *mut c_char) {
    // Stub implementation - does nothing
    // Will be overridden by Swift implementation
}

// External declarations for iOS functions
// These will be resolved by the Swift implementations when linking
extern "C" {
    // These declarations are for internal use and will be resolved by Swift
    // The actual implementations are provided as stubs above
}
