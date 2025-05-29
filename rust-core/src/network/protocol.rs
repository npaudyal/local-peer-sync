//! Network protocol for peer communication

use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Types of messages that can be sent between peers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    /// Clipboard synchronization message
    Clipboard,
    /// Device discovery/announcement
    Discovery,
    /// Pairing request
    PairingRequest,
    /// Pairing response
    PairingResponse,
    /// Heartbeat/keep-alive
    Heartbeat,
}

/// Main message structure for peer communication
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
    pub payload: String,

    /// Timestamp when message was created
    pub timestamp: u64,

    /// Message version for protocol compatibility
    pub version: u8,
}

impl SyncMessage {
    /// Create a new clipboard sync message
    pub fn new_clipboard(source_device_id: String, content: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            message_type: MessageType::Clipboard,
            source_device_id,
            target_device_id: None, // Broadcast to all peers
            payload: content,
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 1,
        }
    }

    /// Create a discovery message
    pub fn new_discovery(source_device_id: String, device_name: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            message_type: MessageType::Discovery,
            source_device_id,
            target_device_id: None,
            payload: device_name,
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 1,
        }
    }

    /// Create a pairing request
    pub fn new_pairing_request(source_device_id: String, target_device_id: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            message_type: MessageType::PairingRequest,
            source_device_id,
            target_device_id: Some(target_device_id),
            payload: String::new(),
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 1,
        }
    }

    /// Serialize message to JSON
    pub fn to_json(&self) -> crate::Result<String> {
        serde_json::to_string(self).map_err(|e| e.into())
    }

    /// Deserialize message from JSON
    pub fn from_json(json: &str) -> crate::Result<Self> {
        serde_json::from_str(json).map_err(|e| e.into())
    }

    /// Check if message is expired (older than 5 minutes)
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        now - self.timestamp > 300 // 5 minutes
    }
}
