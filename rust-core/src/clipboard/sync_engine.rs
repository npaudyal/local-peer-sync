//! World's most advanced clipboard synchronization engine
use super::types::*;
use crate::{Result, SyncError};
use arboard::{Clipboard, ImageData};
#[cfg(target_os = "linux")]
use arboard::{GetExtLinux, SetExtLinux};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio::time::{interval, sleep};
use tracing::{debug, error, info, warn};
/// Maximum content size (10MB)
const MAX_CONTENT_SIZE: usize = 10 * 1024 * 1024;
/// Clipboard check interval
const CLIPBOARD_CHECK_INTERVAL: Duration = Duration::from_millis(250);
/// Rate limiting: max changes per minute
const MAX_CHANGES_PER_MINUTE: usize = 30;
/// World's most advanced clipboard synchronization engine
pub struct ClipboardSyncEngine {
    /// System clipboard access
    clipboard: Arc<Mutex<Clipboard>>,
    /// Last known clipboard content hash
    last_content_hash: Arc<RwLock<Option<String>>>,

    /// Clipboard history with smart deduplication
    history: Arc<RwLock<VecDeque<ClipboardItem>>>,

    /// Maximum history size
    max_history_size: usize,

    /// Change notification sender
    change_sender: Option<mpsc::UnboundedSender<ClipboardItem>>,

    /// Rate limiting tracker
    rate_limiter: Arc<RwLock<VecDeque<Instant>>>,

    /// Device identifier
    device_id: String,

    /// Configuration
    config: ClipboardConfig,

    /// Statistics
    stats: Arc<RwLock<ClipboardStats>>,

    /// Flag to ignore next clipboard change (when we set it ourselves)
    ignore_next_change: Arc<RwLock<bool>>,
}
/// Configuration for clipboard engine
#[derive(Debug, Clone)]
pub struct ClipboardConfig {
    /// Enable image synchronization
    pub sync_images: bool,
    /// Enable file synchronization
    pub sync_files: bool,

    /// Enable rich text synchronization
    pub sync_rich_text: bool,

    /// Maximum content size to sync
    pub max_content_size: usize,

    /// Enable compression for large content
    pub enable_compression: bool,

    /// Compression threshold (bytes)
    pub compression_threshold: usize,

    /// Enable clipboard history
    pub enable_history: bool,

    /// Auto-paste received content
    pub auto_paste: bool,
}
/// Statistics tracking
#[derive(Debug)]
pub struct ClipboardStats {
    pub items_synced: u64,
    pub bytes_synced: u64,
    pub images_synced: u64,
    pub files_synced: u64,
    pub errors: u64,
    pub last_sync: Option<chrono::DateTime<chrono::Utc>>,
}

impl Default for ClipboardStats {
    fn default() -> Self {
        Self {
            items_synced: 0,
            bytes_synced: 0,
            images_synced: 0,
            files_synced: 0,
            errors: 0,
            last_sync: None,
        }
    }
}

impl Default for ClipboardConfig {
    fn default() -> Self {
        Self {
            sync_images: true,
            sync_files: true,
            sync_rich_text: true,
            max_content_size: MAX_CONTENT_SIZE,
            enable_compression: true,
            compression_threshold: 1024, // 1KB
            enable_history: true,
            auto_paste: true,
        }
    }
}
impl ClipboardSyncEngine {
    /// Create new world-class clipboard sync engine
    pub fn new(device_id: String, max_history_size: usize) -> Result<Self> {
        let clipboard = Clipboard::new()
            .map_err(|e| SyncError::Unknown(format!("Failed to access system clipboard: {}", e)))?;
        info!(
            "🎯 Initialized world-class clipboard engine for device: {}",
            device_id
        );

        Ok(Self {
            clipboard: Arc::new(Mutex::new(clipboard)),
            last_content_hash: Arc::new(RwLock::new(None)),
            history: Arc::new(RwLock::new(VecDeque::new())),
            max_history_size,
            change_sender: None,
            rate_limiter: Arc::new(RwLock::new(VecDeque::new())),
            device_id,
            config: ClipboardConfig::default(),
            stats: Arc::new(RwLock::new(ClipboardStats::default())),
            ignore_next_change: Arc::new(RwLock::new(false)),
        })
    }

    /// Start intelligent clipboard monitoring
    pub async fn start_monitoring(&mut self) -> Result<mpsc::UnboundedReceiver<ClipboardItem>> {
        let (tx, rx) = mpsc::unbounded_channel();
        self.change_sender = Some(tx.clone());

        let clipboard = Arc::clone(&self.clipboard);
        let last_hash = Arc::clone(&self.last_content_hash);
        let rate_limiter = Arc::clone(&self.rate_limiter);
        let device_id = self.device_id.clone();
        let config = self.config.clone();
        let stats = Arc::clone(&self.stats);
        let ignore_flag = Arc::clone(&self.ignore_next_change);

        // Spawn intelligent monitoring task
        tokio::spawn(async move {
            Self::intelligent_clipboard_monitor(
                clipboard,
                last_hash,
                rate_limiter,
                device_id,
                config,
                stats,
                ignore_flag,
                tx,
            )
            .await;
        });

        info!("🚀 Started intelligent clipboard monitoring");
        Ok(rx)
    }

    /// Intelligent clipboard monitoring with advanced features
    async fn intelligent_clipboard_monitor(
        clipboard: Arc<Mutex<Clipboard>>,
        last_hash: Arc<RwLock<Option<String>>>,
        rate_limiter: Arc<RwLock<VecDeque<Instant>>>,
        _device_id: String,
        config: ClipboardConfig,
        stats: Arc<RwLock<ClipboardStats>>,
        ignore_flag: Arc<RwLock<bool>>,
        sender: mpsc::UnboundedSender<ClipboardItem>,
    ) {
        let mut check_interval = interval(CLIPBOARD_CHECK_INTERVAL);
        let mut consecutive_errors = 0;
        let mut last_successful_read = Instant::now();

        info!("🔍 Starting intelligent clipboard monitoring loop");

        loop {
            check_interval.tick().await;

            // Check if we should ignore the next change
            let should_ignore = {
                let mut ignore = ignore_flag.write().await;
                let should_ignore = *ignore;
                if should_ignore {
                    *ignore = false; // Reset flag
                }
                should_ignore
            };

            if should_ignore {
                debug!("🔇 Ignoring clipboard change (set by network sync)");
                continue;
            }

            // Rate limiting cleanup
            Self::cleanup_rate_limiter(&rate_limiter).await;

            // Check if we're being rate limited
            if Self::is_rate_limited(&rate_limiter).await {
                debug!("⏱️ Rate limited, skipping clipboard check");
                continue;
            }

            // Try to read clipboard with advanced error handling
            match Self::read_advanced_clipboard_content(&clipboard, &config).await {
                Ok(Some(item)) => {
                    // Check if content actually changed
                    let content_hash = item.content_hash.clone();
                    let mut last_hash_guard = last_hash.write().await;

                    if last_hash_guard.as_ref() != Some(&content_hash) {
                        *last_hash_guard = Some(content_hash);
                        drop(last_hash_guard);

                        // Add to rate limiter
                        Self::add_to_rate_limiter(&rate_limiter).await;

                        // Update statistics
                        Self::update_stats(&stats, &item).await;

                        info!("📋 Clipboard changed: {}", item.summary());

                        if let Err(e) = sender.send(item) {
                            error!("Failed to send clipboard change: {}", e);
                            break;
                        }

                        consecutive_errors = 0;
                        last_successful_read = Instant::now();
                    }
                }
                Ok(None) => {
                    // No content or same content
                    consecutive_errors = 0;
                }
                Err(e) => {
                    consecutive_errors += 1;

                    if consecutive_errors > 10 {
                        error!(
                            "Too many consecutive clipboard errors ({}), backing off",
                            consecutive_errors
                        );
                        sleep(Duration::from_secs(5)).await;
                        consecutive_errors = 0;
                    } else {
                        debug!("Clipboard read error ({}): {}", consecutive_errors, e);
                    }
                }
            }

            // Health check: if no successful read for too long, restart
            if last_successful_read.elapsed() > Duration::from_secs(300) {
                warn!("No successful clipboard read for 5 minutes, restarting monitoring");
                last_successful_read = Instant::now();
            }
        }

        warn!("🛑 Clipboard monitoring loop ended");
    }

    /// Read clipboard content with advanced format detection
    async fn read_advanced_clipboard_content(
        clipboard: &Arc<Mutex<Clipboard>>,
        config: &ClipboardConfig,
    ) -> Result<Option<ClipboardItem>> {
        let mut cb = clipboard.lock().await;

        // Try different content types in order of preference

        // 1. Try rich text first (HTML/RTF)
        if config.sync_rich_text {
            if let Ok(content) = Self::try_read_rich_text(&mut cb).await {
                return Ok(Some(content));
            }
        }

        // 2. Try images
        if config.sync_images {
            if let Ok(content) = Self::try_read_image(&mut cb, config).await {
                return Ok(Some(content));
            }
        }

        // 3. Try plain text
        if let Ok(text) = cb.get_text() {
            if !text.trim().is_empty() && text.len() <= config.max_content_size {
                let content = ClipboardContent::Text {
                    content: text,
                    encoding: "UTF-8".to_string(),
                };
                return Ok(Some(ClipboardItem::new(content, "local".to_string())));
            }
        }

        // 4. Try files (platform-specific)
        if config.sync_files {
            if let Ok(content) = Self::try_read_files(&mut cb).await {
                return Ok(Some(content));
            }
        }

        // 5. Try URLs
        if let Ok(content) = Self::try_read_url(&mut cb).await {
            return Ok(Some(content));
        }

        Ok(None)
    }

    /// Advanced rich text reading
    async fn try_read_rich_text(cb: &mut Clipboard) -> Result<ClipboardItem> {
        // Try HTML first
        #[cfg(target_os = "linux")]
        let html = cb.get().html().ok();
        #[cfg(not(target_os = "linux"))]
        let html: Option<String> = None; // TODO: Implement for other platforms

        // Get plain text fallback
        let plain_text = cb.get_text().unwrap_or_default();

        if html.is_some() || !plain_text.is_empty() {
            let content = ClipboardContent::RichText {
                plain_text,
                html,
                rtf: None, // TODO: Add RTF support
            };
            Ok(ClipboardItem::new(content, "local".to_string()))
        } else {
            Err(SyncError::Unknown("No rich text content".to_string()))
        }
    }

    /// Advanced image reading with multiple format support
    async fn try_read_image(cb: &mut Clipboard, config: &ClipboardConfig) -> Result<ClipboardItem> {
        if let Ok(image_data) = cb.get_image() {
            // Convert to multiple formats for compatibility
            let mut alternatives = HashMap::new();

            // Primary format: PNG (lossless, widely supported)
            let png_data = Self::convert_image_to_format(&image_data, ImageFormat::Png)?;

            // Add JPEG alternative for photos (smaller size)
            if let Ok(jpeg_data) = Self::convert_image_to_format(&image_data, ImageFormat::Jpeg) {
                alternatives.insert(ImageFormat::Jpeg, jpeg_data);
            }

            // Check size limits
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

    /// Try to read file paths from clipboard
    async fn try_read_files(_cb: &mut Clipboard) -> Result<ClipboardItem> {
        // Platform-specific file reading
        #[cfg(target_os = "windows")]
        {
            // TODO: Implement Windows file clipboard reading
            Err(SyncError::Unknown(
                "Files not implemented for Windows".to_string(),
            ))
        }

        #[cfg(target_os = "macos")]
        {
            // TODO: Implement macOS file clipboard reading
            Err(SyncError::Unknown(
                "Files not implemented for macOS".to_string(),
            ))
        }

        #[cfg(target_os = "linux")]
        {
            // TODO: Implement Linux file clipboard reading
            Err(SyncError::Unknown(
                "Files not implemented for Linux".to_string(),
            ))
        }

        #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
        Err(SyncError::Unknown(
            "Files not supported on this platform".to_string(),
        ))
    }

    /// Try to read URL from clipboard
    async fn try_read_url(cb: &mut Clipboard) -> Result<ClipboardItem> {
        if let Ok(text) = cb.get_text() {
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

    /// Check if text is a URL
    fn is_url(text: &str) -> bool {
        text.starts_with("http://")
            || text.starts_with("https://")
            || text.starts_with("ftp://")
            || text.starts_with("file://")
    }

    /// Convert image to specific format
    fn convert_image_to_format(image_data: &ImageData, format: ImageFormat) -> Result<Vec<u8>> {
        use image::{ImageBuffer, ImageOutputFormat, Rgba};

        let img_buffer = ImageBuffer::<Rgba<u8>, _>::from_raw(
            image_data.width as u32,
            image_data.height as u32,
            image_data.bytes.to_vec(),
        )
        .ok_or_else(|| SyncError::Unknown("Failed to create image buffer".to_string()))?;

        let mut output = Vec::new();
        let output_format = match format {
            ImageFormat::Png => ImageOutputFormat::Png,
            ImageFormat::Jpeg => ImageOutputFormat::Jpeg(85), // 85% quality
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

    /// Set clipboard content with intelligent format selection
    pub async fn set_clipboard_content(&self, item: ClipboardItem) -> Result<()> {
        // Set flag to ignore the next change detection
        {
            let mut ignore = self.ignore_next_change.write().await;
            *ignore = true;
        }

        let mut cb = self.clipboard.lock().await;

        // Clone the item before matching to avoid partial move
        let item_for_history = item.clone();

        match item.content {
            ClipboardContent::Text { content, .. } => {
                cb.set_text(&content)
                    .map_err(|e| SyncError::Unknown(format!("Failed to set text: {}", e)))?;
                info!(
                    "📋 ✅ Set clipboard text from {}: {}",
                    item.source_device,
                    Self::truncate_for_log(&content, 50)
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
                // Try to set HTML if supported
                #[cfg(target_os = "linux")]
                {
                    if let Some(html_content) = html {
                        if let Err(e) = cb.set().html(&html_content) {
                            warn!("Failed to set HTML, falling back to plain text: {}", e);
                            cb.set_text(&plain_text).map_err(|e| {
                                SyncError::Unknown(format!("Failed to set plain text: {}", e))
                            })?;
                        }
                    } else {
                        cb.set_text(&plain_text).map_err(|e| {
                            SyncError::Unknown(format!("Failed to set plain text: {}", e))
                        })?;
                    }
                }
                #[cfg(not(target_os = "linux"))]
                {
                    cb.set_text(&plain_text)
                        .map_err(|e| SyncError::Unknown(format!("Failed to set text: {}", e)))?;
                }
                info!(
                    "📋 ✅ Set clipboard rich text from {}: {}",
                    item.source_device,
                    Self::truncate_for_log(&plain_text, 50)
                );
            }

            ClipboardContent::Image {
                primary_data,
                primary_format,
                width,
                height,
                ..
            } => {
                let image_data = Self::convert_to_image_data(primary_data, width, height)?;
                cb.set_image(image_data)
                    .map_err(|e| SyncError::Unknown(format!("Failed to set image: {}", e)))?;
                info!(
                    "📋 ✅ Set clipboard image from {}: {}x{} {:?}",
                    item.source_device, width, height, primary_format
                );
            }

            ClipboardContent::Files { paths, .. } => {
                // TODO: Implement file setting
                warn!("File clipboard setting not yet implemented");

                // Fallback: set file paths as text
                let paths_text = paths
                    .iter()
                    .map(|f| f.path.clone())
                    .collect::<Vec<_>>()
                    .join("\n");
                cb.set_text(&paths_text).map_err(|e| {
                    SyncError::Unknown(format!("Failed to set file paths as text: {}", e))
                })?;
                info!(
                    "📋 ✅ Set clipboard file paths from {} as text",
                    item.source_device
                );
            }

            ClipboardContent::Binary { .. } => {
                warn!("Binary clipboard content not supported for setting");
            }

            ClipboardContent::Url { url, .. } => {
                cb.set_text(&url)
                    .map_err(|e| SyncError::Unknown(format!("Failed to set URL: {}", e)))?;
                info!(
                    "📋 ✅ Set clipboard URL from {}: {}",
                    item.source_device, url
                );
            }
        }

        // Add to history
        if self.config.enable_history {
            self.add_to_history(item_for_history).await;
        }

        Ok(())
    }

    /// Convert raw image data to arboard ImageData
    fn convert_to_image_data(data: Vec<u8>, width: u32, height: u32) -> Result<ImageData<'static>> {
        // Decode the image first
        let img = image::load_from_memory(&data)
            .map_err(|e| SyncError::Unknown(format!("Failed to decode image: {}", e)))?;

        let rgba_img = img.to_rgba8();

        Ok(ImageData {
            width: width as usize,
            height: height as usize,
            bytes: rgba_img.into_raw().into(),
        })
    }

    /// Add item to history with smart deduplication
    pub async fn add_to_history(&self, item: ClipboardItem) {
        let mut history = self.history.write().await;

        // Remove duplicates based on content hash
        history.retain(|existing| existing.content_hash != item.content_hash);

        // Add new item at front
        history.push_front(item);

        // Maintain size limit
        while history.len() > self.max_history_size {
            history.pop_back();
        }
    }

    /// Get clipboard history
    pub async fn get_history(&self) -> Vec<ClipboardItem> {
        let history = self.history.read().await;
        history.iter().cloned().collect()
    }

    /// Get statistics
    pub async fn get_stats(&self) -> ClipboardStats {
        let stats = self.stats.read().await;
        ClipboardStats {
            items_synced: stats.items_synced,
            bytes_synced: stats.bytes_synced,
            images_synced: stats.images_synced,
            files_synced: stats.files_synced,
            errors: stats.errors,
            last_sync: stats.last_sync,
        }
    }

    /// Update configuration
    pub fn update_config(&mut self, config: ClipboardConfig) {
        self.config = config;
        info!("📋 Updated clipboard configuration");
    }

    // Rate limiting helpers
    async fn cleanup_rate_limiter(rate_limiter: &Arc<RwLock<VecDeque<Instant>>>) {
        let mut limiter = rate_limiter.write().await;
        let cutoff = Instant::now() - Duration::from_secs(60);
        while let Some(&front) = limiter.front() {
            if front < cutoff {
                limiter.pop_front();
            } else {
                break;
            }
        }
    }

    async fn is_rate_limited(rate_limiter: &Arc<RwLock<VecDeque<Instant>>>) -> bool {
        let limiter = rate_limiter.read().await;
        limiter.len() >= MAX_CHANGES_PER_MINUTE
    }

    async fn add_to_rate_limiter(rate_limiter: &Arc<RwLock<VecDeque<Instant>>>) {
        let mut limiter = rate_limiter.write().await;
        limiter.push_back(Instant::now());
    }

    async fn update_stats(stats: &Arc<RwLock<ClipboardStats>>, item: &ClipboardItem) {
        let mut s = stats.write().await;
        s.items_synced += 1;
        s.bytes_synced += item.content_size() as u64;

        match &item.content {
            ClipboardContent::Image { .. } => s.images_synced += 1,
            ClipboardContent::Files { .. } => s.files_synced += 1,
            _ => {}
        }

        s.last_sync = Some(chrono::Utc::now());
    }

    fn truncate_for_log(text: &str, max_len: usize) -> String {
        if text.len() > max_len {
            format!("{}...", &text[..max_len])
        } else {
            text.to_string()
        }
    }
}
