//! World's most advanced clipboard synchronization engine - Platform Aware
use super::types::*;
use crate::Result;
use std::collections::VecDeque;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio::time::{interval, sleep};
use tracing::{debug, error, info, warn};

/// Clipboard check interval
const CLIPBOARD_CHECK_INTERVAL: Duration = Duration::from_millis(250);
/// Rate limiting: max changes per minute
const MAX_CHANGES_PER_MINUTE: usize = 30;

/// Platform-agnostic clipboard operations trait
#[async_trait::async_trait]
pub trait ClipboardHandler {
    async fn read_content(&mut self, config: &ClipboardConfig) -> Result<Option<ClipboardItem>>;
    async fn write_content(&mut self, item: &ClipboardItem) -> Result<()>;
    async fn is_available(&self) -> bool;
    fn get_platform_name(&self) -> &'static str;
}

/// World's most advanced clipboard synchronization engine
pub struct ClipboardSyncEngine {
    /// Platform-specific clipboard handler (wrapped in Mutex for interior mutability)
    clipboard_handler: Arc<Mutex<Box<dyn ClipboardHandler + Send + Sync>>>,

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

    /// Flag to ignore next clipboard change
    ignore_next_change: Arc<RwLock<bool>>,
}

impl ClipboardSyncEngine {
    /// Create new world-class clipboard sync engine
    pub fn new(device_id: String, max_history_size: usize) -> Result<Self> {
        let clipboard_handler = Arc::new(Mutex::new(Self::create_platform_handler()?));

        info!(
            "🎯 Initialized world-class clipboard engine for device: {} on platform",
            device_id
        );

        Ok(Self {
            clipboard_handler,
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

    /// Create platform-specific clipboard handler
    fn create_platform_handler() -> Result<Box<dyn ClipboardHandler + Send + Sync>> {
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        {
            // Import directly from the handlers module
            use super::handlers::DesktopClipboardHandler;
            Ok(Box::new(DesktopClipboardHandler::new()?))
        }

        #[cfg(target_os = "ios")]
        {
            // Import directly from the handlers module
            use super::handlers::IOSClipboardHandler;
            Ok(Box::new(IOSClipboardHandler::new()?))
        }

        #[cfg(target_os = "android")]
        {
            // TODO: Implement Android handler
            use super::handlers::AndroidClipboardHandler;
            Ok(Box::new(AndroidClipboardHandler::new()?))
        }

        #[cfg(not(any(
            target_os = "linux",
            target_os = "windows",
            target_os = "macos",
            target_os = "ios",
            target_os = "android"
        )))]
        {
            Err(SyncError::Unknown("Unsupported platform".to_string()))
        }
    }

    /// Start intelligent clipboard monitoring
    pub async fn start_monitoring(&mut self) -> Result<mpsc::UnboundedReceiver<ClipboardItem>> {
        let (tx, rx) = mpsc::unbounded_channel();
        self.change_sender = Some(tx.clone());

        // Clone the handler for the monitoring task
        let handler = Arc::clone(&self.clipboard_handler);
        let last_hash = Arc::clone(&self.last_content_hash);
        let rate_limiter = Arc::clone(&self.rate_limiter);
        let device_id = self.device_id.clone();
        let config = self.config.clone();
        let stats = Arc::clone(&self.stats);
        let ignore_flag = Arc::clone(&self.ignore_next_change);

        // Spawn intelligent monitoring task
        tokio::spawn(async move {
            Self::intelligent_clipboard_monitor(
                handler,
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
        handler: Arc<Mutex<Box<dyn ClipboardHandler + Send + Sync>>>,
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

            // Check if clipboard is available
            let is_available = {
                let handler_guard = handler.lock().await;
                handler_guard.is_available().await
            };

            if !is_available {
                debug!("📱 Clipboard not available, waiting...");
                sleep(Duration::from_secs(1)).await;
                continue;
            }

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

            // Try to read clipboard content
            let read_result = {
                let mut handler_guard = handler.lock().await;
                handler_guard.read_content(&config).await
            };

            match read_result {
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

            // Health check
            if last_successful_read.elapsed() > Duration::from_secs(300) {
                warn!("No successful clipboard read for 5 minutes, restarting monitoring");
                last_successful_read = Instant::now();
            }
        }

        warn!("🛑 Clipboard monitoring loop ended");
    }

    /// Set clipboard content with intelligent format selection
    pub async fn set_clipboard_content(&self, item: ClipboardItem) -> Result<()> {
        // Set flag to ignore the next change detection
        {
            let mut ignore = self.ignore_next_change.write().await;
            *ignore = true;
        }

        // Use the platform handler to set content
        {
            let mut handler_guard = self.clipboard_handler.lock().await;
            handler_guard.write_content(&item).await?;
        }

        info!(
            "📋 ✅ Set clipboard content from {}: {}",
            item.source_device,
            item.summary()
        );

        // Add to history
        if self.config.enable_history {
            self.add_to_history(item).await;
        }

        Ok(())
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
}
