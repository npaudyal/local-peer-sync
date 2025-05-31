//! Desktop clipboard handler using arboard
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::{Result, SyncError};
use std::collections::HashMap;
use tracing::{info, warn};

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
use arboard::{Clipboard, ImageData};

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
use image::{ImageBuffer, ImageOutputFormat, Rgba};

#[cfg(target_os = "linux")]
use arboard::{GetExtLinux, SetExtLinux};

pub struct DesktopClipboardHandler {
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    clipboard: Clipboard,
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    _phantom: std::marker::PhantomData<()>,
}

impl DesktopClipboardHandler {
    pub fn new() -> Result<Self> {
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        {
            let clipboard = Clipboard::new().map_err(|e| {
                SyncError::Unknown(format!("Failed to access system clipboard: {}", e))
            })?;

            Ok(Self { clipboard })
        }

        #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
        {
            Err(SyncError::Unknown(
                "Desktop clipboard not supported on this platform".to_string(),
            ))
        }
    }

    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    async fn try_read_rich_text(&mut self) -> Result<ClipboardItem> {
        // Try HTML first
        #[cfg(target_os = "linux")]
        let html = self.clipboard.get().html().ok();
        #[cfg(not(target_os = "linux"))]
        let html: Option<String> = None;

        // Get plain text fallback
        let plain_text = self.clipboard.get_text().unwrap_or_default();

        if html.is_some() || !plain_text.is_empty() {
            let content = ClipboardContent::RichText {
                plain_text,
                html,
                rtf: None,
            };
            Ok(ClipboardItem::new(content, "local".to_string()))
        } else {
            Err(SyncError::Unknown("No rich text content".to_string()))
        }
    }

    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    async fn try_read_image(&mut self, config: &ClipboardConfig) -> Result<ClipboardItem> {
        if let Ok(image_data) = self.clipboard.get_image() {
            let mut alternatives = HashMap::new();
            let png_data = Self::convert_image_to_format(&image_data, ImageFormat::Png)?;

            if let Ok(jpeg_data) = Self::convert_image_to_format(&image_data, ImageFormat::Jpeg) {
                alternatives.insert(ImageFormat::Jpeg, jpeg_data);
            }

            if png_data.len() > config.max_content_size {
                return Err(SyncError::Unknown("Image too large".to_string()));
            }

            let content = ClipboardContent::Image {
                primary_data: png_data,
                primary_format: ImageFormat::Png,
                alternatives,
                width: image_data.width as u32,
                height: image_data.height as u32,
            };

            Ok(ClipboardItem::new(content, "local".to_string()))
        } else {
            Err(SyncError::Unknown("No image content".to_string()))
        }
    }

    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    async fn try_read_url(&mut self) -> Result<ClipboardItem> {
        if let Ok(text) = self.clipboard.get_text() {
            if Self::is_url(&text) {
                let content = ClipboardContent::Url {
                    url: text,
                    title: None,
                    description: None,
                };
                return Ok(ClipboardItem::new(content, "local".to_string()));
            }
        }
        Err(SyncError::Unknown("No URL content".to_string()))
    }

    fn is_url(text: &str) -> bool {
        text.starts_with("http://")
            || text.starts_with("https://")
            || text.starts_with("ftp://")
            || text.starts_with("file://")
    }

    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    fn convert_image_to_format(image_data: &ImageData, format: ImageFormat) -> Result<Vec<u8>> {
        let img_buffer = ImageBuffer::<Rgba<u8>, _>::from_raw(
            image_data.width as u32,
            image_data.height as u32,
            image_data.bytes.to_vec(),
        )
        .ok_or_else(|| SyncError::Unknown("Failed to create image buffer".to_string()))?;

        let mut output = Vec::new();
        let output_format = match format {
            ImageFormat::Png => ImageOutputFormat::Png,
            ImageFormat::Jpeg => ImageOutputFormat::Jpeg(85),
            ImageFormat::Gif => ImageOutputFormat::Gif,
            ImageFormat::Webp => {
                return Err(SyncError::Unknown("WebP not supported yet".to_string()))
            }
            ImageFormat::Bmp => ImageOutputFormat::Bmp,
            ImageFormat::Tiff => ImageOutputFormat::Tiff,
        };

        img_buffer
            .write_to(&mut std::io::Cursor::new(&mut output), output_format)
            .map_err(|e| SyncError::Unknown(format!("Failed to encode image: {}", e)))?;

        Ok(output)
    }

    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    fn convert_to_image_data(data: Vec<u8>, width: u32, height: u32) -> Result<ImageData<'static>> {
        let img = image::load_from_memory(&data)
            .map_err(|e| SyncError::Unknown(format!("Failed to decode image: {}", e)))?;

        let rgba_img = img.to_rgba8();

        Ok(ImageData {
            width: width as usize,
            height: height as usize,
            bytes: rgba_img.into_raw().into(),
        })
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
impl ClipboardHandler for DesktopClipboardHandler {
    async fn read_content(&mut self, config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        {
            if config.sync_rich_text {
                if let Ok(content) = self.try_read_rich_text().await {
                    return Ok(Some(content));
                }
            }

            if config.sync_images {
                if let Ok(content) = self.try_read_image(config).await {
                    return Ok(Some(content));
                }
            }

            if let Ok(text) = self.clipboard.get_text() {
                if !text.trim().is_empty() && text.len() <= config.max_content_size {
                    let content = ClipboardContent::Text {
                        content: text,
                        encoding: "UTF-8".to_string(),
                    };
                    return Ok(Some(ClipboardItem::new(content, "local".to_string())));
                }
            }

            if let Ok(content) = self.try_read_url().await {
                return Ok(Some(content));
            }

            Ok(None)
        }

        #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
        {
            Err(SyncError::Unknown(
                "Desktop clipboard not supported".to_string(),
            ))
        }
    }

    async fn write_content(&mut self, item: &ClipboardItem) -> Result<()> {
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        {
            match &item.content {
                ClipboardContent::Text { content, .. } => {
                    self.clipboard
                        .set_text(content)
                        .map_err(|e| SyncError::Unknown(format!("Failed to set text: {}", e)))?;
                    info!(
                        "📋 ✅ Set desktop clipboard text from {}: {}",
                        item.source_device,
                        Self::truncate_for_log(content, 50)
                    );
                }

                ClipboardContent::RichText {
                    plain_text,
                    #[cfg(target_os = "linux")]
                    html,
                    #[cfg(not(target_os = "linux"))]
                        html: _,
                    ..
                } => {
                    #[cfg(target_os = "linux")]
                    {
                        if let Some(html_content) = html {
                            if let Err(e) = self.clipboard.set().html(html_content) {
                                warn!("Failed to set HTML, falling back to plain text: {}", e);
                                self.clipboard.set_text(plain_text).map_err(|e| {
                                    SyncError::Unknown(format!("Failed to set plain text: {}", e))
                                })?;
                            }
                        } else {
                            self.clipboard.set_text(plain_text).map_err(|e| {
                                SyncError::Unknown(format!("Failed to set plain text: {}", e))
                            })?;
                        }
                    }
                    #[cfg(not(target_os = "linux"))]
                    {
                        self.clipboard.set_text(plain_text).map_err(|e| {
                            SyncError::Unknown(format!("Failed to set text: {}", e))
                        })?;
                    }
                }

                ClipboardContent::Image {
                    primary_data,
                    width,
                    height,
                    ..
                } => {
                    let image_data =
                        Self::convert_to_image_data(primary_data.clone(), *width, *height)?;
                    self.clipboard
                        .set_image(image_data)
                        .map_err(|e| SyncError::Unknown(format!("Failed to set image: {}", e)))?;
                }

                ClipboardContent::Files { paths, .. } => {
                    let paths_text = paths
                        .iter()
                        .map(|f| f.path.clone())
                        .collect::<Vec<_>>()
                        .join("\n");
                    self.clipboard.set_text(&paths_text).map_err(|e| {
                        SyncError::Unknown(format!("Failed to set file paths as text: {}", e))
                    })?;
                }

                ClipboardContent::Binary { .. } => {
                    warn!("Binary clipboard content not supported for desktop setting");
                }

                ClipboardContent::Url { url, .. } => {
                    self.clipboard
                        .set_text(url)
                        .map_err(|e| SyncError::Unknown(format!("Failed to set URL: {}", e)))?;
                }
            }

            Ok(())
        }

        #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
        {
            Err(SyncError::Unknown(
                "Desktop clipboard not supported".to_string(),
            ))
        }
    }

    async fn is_available(&self) -> bool {
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        {
            true
        }

        #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
        {
            false
        }
    }

    fn get_platform_name(&self) -> &'static str {
        "Desktop"
    }
}
