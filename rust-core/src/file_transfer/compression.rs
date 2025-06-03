// src/file_transfer/compression.rs
use crate::{Result, SyncError};

/// Intelligent compression engine
pub struct CompressionEngine {
    #[allow(dead_code)] // 🔧 Fixed: Allow dead code for future use
    compression_level: u32,
}

impl CompressionEngine {
    pub fn new() -> Self {
        Self {
            compression_level: 6, // Balanced compression
        }
    }

    pub async fn compress_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        use lz4_flex::compress_prepend_size;
        Ok(compress_prepend_size(data))
    }

    pub async fn decompress_data(&self, compressed: &[u8]) -> Result<Vec<u8>> {
        use lz4_flex::decompress_size_prepended;
        decompress_size_prepended(compressed)
            .map_err(|e| SyncError::Unknown(format!("Decompression failed: {}", e)))
    }

    pub fn should_compress(&self, size: u64, mime_type: &str) -> bool {
        // Don't compress already compressed formats
        let uncompressible = [
            "image/jpeg",
            "image/png",
            "video/mp4",
            "audio/mp3",
            "application/zip",
        ];
        if uncompressible.iter().any(|&t| mime_type.contains(t)) {
            return false;
        }

        size >= 1024 // Compress files larger than 1KB
    }
}

impl Default for CompressionEngine {
    fn default() -> Self {
        Self::new()
    }
}
