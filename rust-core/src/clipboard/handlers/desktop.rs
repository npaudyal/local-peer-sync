// src/clipboard/handlers/desktop.rs - Add file detection
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::{Result, SyncError};
use arboard::Clipboard;
use std::path::PathBuf;
use std::sync::Mutex;
use tracing::{error, info, warn};

/// Desktop clipboard handler using arboard
pub struct DesktopClipboardHandler {
    clipboard: Mutex<Clipboard>,
    device_id: String,
    last_text: Option<String>, // Track last text to detect changes
}

impl DesktopClipboardHandler {
    pub fn new() -> Result<Self> {
        let clipboard = Clipboard::new()
            .map_err(|e| SyncError::Unknown(format!("Failed to initialize clipboard: {}", e)))?;

        Ok(Self {
            clipboard: Mutex::new(clipboard),
            device_id: "desktop_device".to_string(),
            last_text: None,
        })
    }

    /// Check if clipboard contains file paths (simple heuristic)
    fn looks_like_file_paths(&self, text: &str) -> bool {
        // Check for common file path patterns
        let lines: Vec<&str> = text.lines().collect();

        // If multiple lines, check if they look like file paths
        if lines.len() > 1 {
            return lines.iter().all(|line| {
                line.contains('/')
                    || line.contains('\\')
                    || line.ends_with(".txt")
                    || line.ends_with(".pdf")
                    || line.ends_with(".jpg")
                    || line.ends_with(".png")
                    || line.ends_with(".doc")
                    || line.ends_with(".docx")
            });
        }

        // Single line - check if it looks like a file path
        text.contains('/')
            && (text.ends_with(".txt")
                || text.ends_with(".pdf")
                || text.ends_with(".jpg")
                || text.ends_with(".png")
                || text.ends_with(".doc")
                || text.ends_with(".docx")
                || text.ends_with(".mp4")
                || text.ends_with(".zip"))
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
                return Ok(None); // No change
            }
        }
        self.last_text = Some(clipboard_text.clone());

        // Check if it looks like file paths
        if self.looks_like_file_paths(&clipboard_text) {
            info!("📁 Detected potential file paths in clipboard");

            // Parse file paths
            let file_paths: Vec<PathBuf> = clipboard_text
                .lines()
                .filter_map(|line| {
                    let path = PathBuf::from(line.trim());
                    if path.exists() {
                        Some(path)
                    } else {
                        None
                    }
                })
                .collect();

            if !file_paths.is_empty() {
                info!("📂 Found {} existing files", file_paths.len());

                // For now, just return as text with a note
                let file_summary = format!(
                    "Files detected: {}",
                    file_paths
                        .iter()
                        .map(|p| p.file_name().unwrap_or_default().to_string_lossy())
                        .collect::<Vec<_>>()
                        .join(", ")
                );

                let clipboard_content = ClipboardContent::Text {
                    content: format!("📁 {}", file_summary),
                    encoding: "UTF-8".to_string(),
                };

                return Ok(Some(ClipboardItem::new(
                    clipboard_content,
                    self.device_id.clone(),
                )));
            }
        }

        // Regular text content
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
                println!(
                    "📋 ← Received: {}",
                    if content.len() > 50 {
                        format!("{}...", &content[..50])
                    } else {
                        content.clone()
                    }
                );
                Ok(())
            }
            _ => {
                warn!("Unsupported content type");
                Ok(())
            }
        }
    }

    async fn is_available(&self) -> bool {
        true
    }

    fn get_platform_name(&self) -> &'static str {
        std::env::consts::OS
    }
}
