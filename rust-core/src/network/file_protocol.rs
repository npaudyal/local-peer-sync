// network/file_protocol.rs
use super::protocol::{MessageType, SyncMessage, SyncPayload};
use crate::file_transfer::types::*;
use serde::{Deserialize, Serialize};

/// Extended message types for file transfers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FileMessageType {
    FileTransferRequest,
    FileTransferResponse,
    FileTransferStart,
    FileTransferChunk,
    FileTransferProgress,
    FileTransferComplete,
    FileTransferCancel,
    FileTransferResume,
}

/// Extended payload for file transfer messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FileTransferPayload {
    TransferRequest {
        package: FileTransferPackage,
        requires_permission: bool,
    },
    TransferResponse {
        transfer_id: String,
        accepted: bool,
        reason: Option<String>,
        available_space: u64,
    },
    TransferStart {
        transfer_id: String,
        resume_from: Option<String>, // file_id to resume from
    },
    ChunkData {
        transfer_id: String,
        file_id: String,
        chunk: FileChunk,
    },
    Progress {
        transfer_id: String,
        progress: TransferProgress,
    },
    Complete {
        transfer_id: String,
        success: bool,
        message: Option<String>,
        written_files: Vec<String>,
    },
    Cancel {
        transfer_id: String,
        reason: String,
    },
    Resume {
        transfer_id: String,
        file_id: String,
        chunk_id: u32,
    },
}

impl SyncMessage {
    /// Create file transfer request message
    pub fn new_file_transfer_request(
        source_device_id: String,
        package: FileTransferPackage,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            message_type: MessageType::ClipboardSync, // Reuse existing type
            source_device_id,
            target_device_id: None,
            payload: SyncPayload::FileTransfer(FileTransferPayload::TransferRequest {
                package,
                requires_permission: true,
            }),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 2,
            priority: 90, // High priority for file transfers
        }
    }

    /// Create file transfer chunk message
    pub fn new_file_chunk(
        source_device_id: String,
        transfer_id: String,
        file_id: String,
        chunk: FileChunk,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            message_type: MessageType::ClipboardSync,
            source_device_id,
            target_device_id: None,
            payload: SyncPayload::FileTransfer(FileTransferPayload::ChunkData {
                transfer_id,
                file_id,
                chunk,
            }),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 2,
            priority: 95, // Very high priority for chunks
        }
    }

    /// Create progress update message
    pub fn new_transfer_progress(
        source_device_id: String,
        transfer_id: String,
        progress: TransferProgress,
    ) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            message_type: MessageType::ClipboardSync,
            source_device_id,
            target_device_id: None,
            payload: SyncPayload::FileTransfer(FileTransferPayload::Progress {
                transfer_id,
                progress,
            }),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            version: 2,
            priority: 30, // Lower priority for progress updates
        }
    }
}

// Update the existing SyncPayload enum
impl SyncPayload {
    // Add this variant to the existing enum in protocol.rs
    // FileTransfer(FileTransferPayload),
}
