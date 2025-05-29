//! Local Peer Sync - Core Library
//!
//! High-performance, secure clipboard synchronization across devices
//! on the same local network.

pub mod clipboard;
pub mod config;
pub mod crypto;
pub mod error;
pub mod ffi;
pub mod network;
pub mod storage;

// Re-export main types for easier usage
pub use config::SyncConfig;
pub use error::{Result, SyncError};
pub use network::SyncManager;

use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

/// Main synchronization manager
pub struct LocalPeerSync {
    config: SyncConfig,
    manager: Arc<RwLock<SyncManager>>,
    running: Arc<RwLock<bool>>,
}

impl LocalPeerSync {
    /// Create a new LocalPeerSync instance
    pub async fn new(config: SyncConfig) -> Result<Self> {
        info!(
            "Initializing Local Peer Sync v{}",
            env!("CARGO_PKG_VERSION")
        );

        let manager = Arc::new(RwLock::new(SyncManager::new(config.clone()).await?));

        Ok(Self {
            config,
            manager,
            running: Arc::new(RwLock::new(false)),
        })
    }

    /// Start the synchronization service
    pub async fn start(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        info!("Starting Local Peer Sync service");
        let mut manager = self.manager.write().await;
        manager.start_discovery().await?;

        *running = true;
        info!("Local Peer Sync service started successfully");
        Ok(())
    }

    /// Stop the synchronization service
    pub async fn stop(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        info!("Stopping Local Peer Sync service");
        let mut manager = self.manager.write().await;
        manager.stop_discovery().await?;

        *running = false;
        info!("Local Peer Sync service stopped");
        Ok(())
    }

    /// Sync clipboard content to peers
    pub async fn sync_clipboard(&self, content: String) -> Result<()> {
        let manager = self.manager.read().await;
        manager.broadcast_clipboard(content).await
    }

    /// Get discovered peers
    pub async fn get_peers(&self) -> Result<Vec<String>> {
        let manager = self.manager.read().await;
        Ok(manager.get_peer_names().await)
    }

    /// Get the current configuration
    pub fn get_config(&self) -> &SyncConfig {
        &self.config
    }

    /// Check if the service is currently running
    pub async fn is_running(&self) -> bool {
        let running = self.running.read().await;
        *running
    }

    /// Get device information
    pub fn get_device_info(&self) -> (&str, &str) {
        (&self.config.device_id, &self.config.device_name)
    }
}
