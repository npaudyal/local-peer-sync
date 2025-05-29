//! Configuration for Local Peer Sync

use serde::{Deserialize, Serialize};
use std::time::Duration;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)] // Make sure this is public
pub struct SyncConfig {
    /// Unique device identifier
    pub device_id: String,

    /// Human-readable device name
    pub device_name: String,

    /// Port for peer communication
    pub port: u16,

    /// mDNS service type
    pub service_type: String,

    /// Encryption enabled
    pub encryption_enabled: bool,

    /// Auto-sync clipboard changes
    pub auto_sync: bool,

    /// Maximum clipboard content size (bytes)
    pub max_content_size: usize,

    /// Peer discovery timeout
    pub discovery_timeout: Duration,

    /// Connection timeout
    pub connection_timeout: Duration,

    /// Clipboard history size
    pub history_size: usize,
}

impl Default for SyncConfig {
    fn default() -> Self {
        Self {
            device_id: Uuid::new_v4().to_string(),
            device_name: Self::default_device_name(),
            port: 8421, // "SYNC" on phone keypad
            service_type: "_localpeersync._tcp".to_string(),
            encryption_enabled: true,
            auto_sync: true,
            max_content_size: 10 * 1024 * 1024, // 10MB
            discovery_timeout: Duration::from_secs(30),
            connection_timeout: Duration::from_secs(10),
            history_size: 50,
        }
    }
}

impl SyncConfig {
    /// Create config with custom device name
    pub fn with_device_name(device_name: String) -> Self {
        Self {
            device_name,
            ..Default::default()
        }
    }

    /// Generate default device name based on system info
    fn default_device_name() -> String {
        let hostname = hostname::get()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();

        if hostname.is_empty() {
            format!("Device-{}", &Uuid::new_v4().to_string()[..8])
        } else {
            hostname
        }
    }

    /// Validate configuration
    pub fn validate(&self) -> crate::Result<()> {
        if self.device_name.is_empty() {
            return Err(crate::SyncError::Config(
                "Device name cannot be empty".to_string(),
            ));
        }

        if self.port < 1024 {
            return Err(crate::SyncError::Config("Port must be >= 1024".to_string()));
        }

        if self.max_content_size == 0 {
            return Err(crate::SyncError::Config(
                "Max content size must be > 0".to_string(),
            ));
        }

        Ok(())
    }
}
