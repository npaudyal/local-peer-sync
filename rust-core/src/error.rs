//! Error types for Local Peer Sync

use thiserror::Error;

pub type Result<T> = std::result::Result<T, SyncError>; // Make sure this is public

#[derive(Error, Debug)]
pub enum SyncError {
    // Make sure this is public
    #[error("Network error: {0}")]
    Network(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Encryption error: {0}")]
    Encryption(String),

    #[error("Device trust error: {0}")]
    Trust(String),

    #[error("Storage error: {0}")]
    Storage(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Timeout error")]
    Timeout,

    #[error("Service not running")]
    NotRunning,

    #[error("Unknown error: {0}")]
    Unknown(String),
}

// Ensure our error type can cross FFI boundaries safely
unsafe impl Send for SyncError {}
unsafe impl Sync for SyncError {}
