//! Network protocol for peer communication - Enhanced for clipboard sync

use crate::clipboard::ClipboardItem;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Types of messages that can be sent between peers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    /// Advanced clipboard synchronization message
    ClipboardSync,
    /// Device discovery/announcement
    Discovery,
    /// Pairing request
    PairingRequest,
    /// Pairing response
    PairingResponse,
    /// Heartbeat/keep-alive
    Heartbeat,
    /// Clipboard history request
    HistoryRequest,
    /// Clipboard history response
    HistoryResponse,
    /// Statistics sharing
    Statistics,
}

/// Enhanced message structure for peer communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncMessage {
    /// Unique message ID
    pub id: String,

    /// Message type
    pub message_type: MessageType,

    /// Source device ID
    pub source_device_id: String,

    /// Target device ID (None for broadcast)
    pub target_device_id: Option<String>,

    /// Message payload
    pub payload: SyncPayload,

    /// Timestamp when message was created
    pub timestamp: u64,

    /// Message version for protocol compatibility
    pub version: u8,

    /// Message priority (0-100)
    pub priority: u8,
}

/// Enhanced payload supporting different data types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncPayload {
    /// Raw text payload (legacy)
    Text(String),

    /// Advanced clipboard item
    ClipboardItem(ClipboardItem),

    /// Multiple clipboard items (history)
    ClipboardHistory(Vec<ClipboardItem>),

    /// Device information
    DeviceInfo {
        name: String,
        platform: String,
        version: String,
        capabilities: Vec<String>,
    },

    /// Statistics data
    Statistics {
        items_synced: u64,
        bytes_synced: u64,
        uptime: u64,
    },
}

impl SyncPayload {
    /// Get approximate size of payload for size checks
    pub fn size(&self) -> usize {
        match self {
            SyncPayload::Text(s) => s.len(),
            SyncPayload::ClipboardItem(item) => item.content_size(),
            SyncPayload::ClipboardHistory(items) => {
                items.iter().map(|item| item.content_size()).sum()
            }
            SyncPayload::DeviceInfo {
                name,
                platform,
                version,
                capabilities,
            } => {
                name.len()
                    + platform.len()
                    + version.len()
                    + capabilities.iter().map(|c| c.len()).sum::<usize>()
            }
            SyncPayload::Statistics { .. } => 24, // Approximate size of 3 u64s
        }
    }
}

impl SyncMessage {
    /// Create a new advanced clipboard sync message
    pub fn new_clipboard_item(source_device_id: String, item: ClipboardItem) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            message_type: MessageType::ClipboardSync,
            source_device_id,
            target_device_id: None, // Broadcast to all peers
            payload: SyncPayload::ClipboardItem(item),
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 2,   // Updated version
            priority: 80, // High priority for clipboard
        }
    }

    /// Create a legacy clipboard message for compatibility
    pub fn new_clipboard(source_device_id: String, content: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            message_type: MessageType::ClipboardSync,
            source_device_id,
            target_device_id: None,
            payload: SyncPayload::Text(content),
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 1,
            priority: 50,
        }
    }

    /// Create a discovery message
    pub fn new_discovery(source_device_id: String, device_name: String) -> Self {
        let platform = if cfg!(target_os = "windows") {
            "Windows"
        } else if cfg!(target_os = "macos") {
            "macOS"
        } else if cfg!(target_os = "linux") {
            "Linux"
        } else {
            "Unknown"
        };

        Self {
            id: Uuid::new_v4().to_string(),
            message_type: MessageType::Discovery,
            source_device_id,
            target_device_id: None,
            payload: SyncPayload::DeviceInfo {
                name: device_name,
                platform: platform.to_string(),
                version: env!("CARGO_PKG_VERSION").to_string(),
                capabilities: vec![
                    "text".to_string(),
                    "images".to_string(),
                    "rich_text".to_string(),
                    "compression".to_string(),
                ],
            },
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 2,
            priority: 30,
        }
    }

    /// Serialize message to JSON with compression for large payloads
    pub fn to_json(&self) -> crate::Result<String> {
        let json = serde_json::to_string(self)?;

        // Compress if large
        if json.len() > 1024 {
            use base64::{engine::general_purpose, Engine as _};
            use lz4_flex::compress_prepend_size;

            let compressed = compress_prepend_size(json.as_bytes());

            // Only use compression if it actually saves space
            if compressed.len() < json.len() {
                let compressed_b64 = general_purpose::STANDARD.encode(&compressed);
                return Ok(format!("COMPRESSED:{}", compressed_b64));
            }
        }

        Ok(json)
    }

    /// Deserialize message from JSON with decompression support
    pub fn from_json(json: &str) -> crate::Result<Self> {
        if let Some(compressed_data) = json.strip_prefix("COMPRESSED:") {
            use base64::{engine::general_purpose, Engine as _};
            use lz4_flex::decompress_size_prepended;

            let compressed_bytes = general_purpose::STANDARD
                .decode(compressed_data)
                .map_err(|e| crate::SyncError::Unknown(format!("Base64 decode failed: {}", e)))?;

            let decompressed = decompress_size_prepended(&compressed_bytes)
                .map_err(|e| crate::SyncError::Unknown(format!("Decompression failed: {}", e)))?;

            let json_str = String::from_utf8(decompressed)
                .map_err(|e| crate::SyncError::Unknown(format!("UTF-8 decode failed: {}", e)))?;

            serde_json::from_str(&json_str).map_err(|e| e.into())
        } else {
            serde_json::from_str(json).map_err(|e| e.into())
        }
    }

    /// Check if message is expired (older than 5 minutes)
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        now - self.timestamp > 300 // 5 minutes
    }

    /// Get message size in bytes
    pub fn size(&self) -> usize {
        self.to_json().map(|s| s.len()).unwrap_or(0)
    }
}
