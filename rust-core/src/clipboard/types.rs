//! Advanced clipboard data types for the world's best clipboard sync

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Comprehensive clipboard item supporting all major data types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardItem {
    /// Unique identifier for this clipboard item
    pub id: String,

    /// Timestamp when this item was created
    pub timestamp: DateTime<Utc>,

    /// Source device that created this item
    pub source_device: String,

    /// The actual clipboard content
    pub content: ClipboardContent,

    /// Content metadata
    pub metadata: ClipboardMetadata,

    /// Hash of the content for deduplication
    pub content_hash: String,
}

/// All supported clipboard content types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClipboardContent {
    /// Plain text content
    Text {
        content: String,
        encoding: String, // UTF-8, UTF-16, etc.
    },

    /// Rich text with formatting
    RichText {
        plain_text: String,
        html: Option<String>,
        rtf: Option<String>,
    },

    /// Image content with multiple formats
    Image {
        /// Primary format (usually PNG)
        primary_data: Vec<u8>,
        primary_format: ImageFormat,
        /// Alternative formats for compatibility
        alternatives: HashMap<ImageFormat, Vec<u8>>,
        width: u32,
        height: u32,
    },

    /// File paths and metadata
    Files {
        paths: Vec<FileItem>,
        total_size: u64,
    },

    /// Binary data with MIME type detection
    Binary {
        data: Vec<u8>,
        mime_type: String,
        filename: Option<String>,
    },

    /// URL with metadata
    Url {
        url: String,
        title: Option<String>,
        description: Option<String>,
    },
}

/// Supported image formats
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ImageFormat {
    Png,
    Jpeg,
    Gif,
    Webp,
    Bmp,
    Tiff,
}

/// File item with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileItem {
    pub path: String,
    pub name: String,
    pub size: u64,
    pub mime_type: Option<String>,
    pub is_directory: bool,
}

/// Metadata about clipboard content
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardMetadata {
    /// Size of content in bytes
    pub size: usize,

    /// Whether content is compressed
    pub compressed: bool,

    /// Compression ratio if compressed
    pub compression_ratio: Option<f32>,

    /// Application that created this content
    pub source_app: Option<String>,

    /// Content priority (0-100, higher = more important)
    pub priority: u8,

    /// Tags for organization
    pub tags: Vec<String>,
}

impl ClipboardItem {
    /// Create a new clipboard item
    pub fn new(content: ClipboardContent, source_device: String) -> Self {
        let content_hash = Self::calculate_content_hash(&content);
        let metadata = ClipboardMetadata::from_content(&content);

        Self {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Utc::now(),
            source_device,
            content,
            metadata,
            content_hash,
        }
    }

    /// Calculate content hash for deduplication
    fn calculate_content_hash(content: &ClipboardContent) -> String {
        use sha2::{Digest, Sha256};

        let mut hasher = Sha256::new();

        match content {
            ClipboardContent::Text { content, .. } => {
                hasher.update(b"TEXT");
                hasher.update(content.as_bytes());
            }
            ClipboardContent::RichText {
                plain_text,
                html,
                rtf,
            } => {
                hasher.update(b"RICHTEXT");
                hasher.update(plain_text.as_bytes());
                if let Some(html) = html {
                    hasher.update(html.as_bytes());
                }
                if let Some(rtf) = rtf {
                    hasher.update(rtf.as_bytes());
                }
            }
            ClipboardContent::Image { primary_data, .. } => {
                hasher.update(b"IMAGE");
                hasher.update(primary_data);
            }
            ClipboardContent::Files { paths, .. } => {
                hasher.update(b"FILES");
                for file in paths {
                    hasher.update(file.path.as_bytes());
                }
            }
            ClipboardContent::Binary {
                data, mime_type, ..
            } => {
                hasher.update(b"BINARY");
                hasher.update(mime_type.as_bytes());
                hasher.update(data);
            }
            ClipboardContent::Url { url, .. } => {
                hasher.update(b"URL");
                hasher.update(url.as_bytes());
            }
        }

        format!("{:x}", hasher.finalize())
    }

    /// Get content size in bytes
    pub fn content_size(&self) -> usize {
        self.metadata.size
    }

    /// Check if content is large (>1MB)
    pub fn is_large_content(&self) -> bool {
        self.content_size() > 1024 * 1024
    }

    /// Get display summary of content
    pub fn summary(&self) -> String {
        match &self.content {
            ClipboardContent::Text { content, .. } => {
                let preview = if content.len() > 50 {
                    format!("{}...", &content[..50])
                } else {
                    content.clone()
                };
                format!("Text: {}", preview)
            }
            ClipboardContent::RichText { plain_text, .. } => {
                let preview = if plain_text.len() > 50 {
                    format!("{}...", &plain_text[..50])
                } else {
                    plain_text.clone()
                };
                format!("Rich Text: {}", preview)
            }
            ClipboardContent::Image {
                width,
                height,
                primary_format,
                ..
            } => {
                format!("Image: {}x{} {:?}", width, height, primary_format)
            }
            ClipboardContent::Files { paths, total_size } => {
                format!("Files: {} items ({} bytes)", paths.len(), total_size)
            }
            ClipboardContent::Binary { mime_type, .. } => {
                format!("Binary: {}", mime_type)
            }
            ClipboardContent::Url { url, .. } => {
                format!("URL: {}", url)
            }
        }
    }
}

impl ClipboardMetadata {
    /// Create metadata from content
    pub fn from_content(content: &ClipboardContent) -> Self {
        let size = match content {
            ClipboardContent::Text { content, .. } => content.len(),
            ClipboardContent::RichText {
                plain_text,
                html,
                rtf,
            } => {
                plain_text.len()
                    + html.as_ref().map_or(0, |h| h.len())
                    + rtf.as_ref().map_or(0, |r| r.len())
            }
            ClipboardContent::Image {
                primary_data,
                alternatives,
                ..
            } => primary_data.len() + alternatives.values().map(|v| v.len()).sum::<usize>(),
            ClipboardContent::Files { total_size, .. } => *total_size as usize,
            ClipboardContent::Binary { data, .. } => data.len(),
            ClipboardContent::Url {
                url,
                title,
                description,
            } => {
                url.len()
                    + title.as_ref().map_or(0, |t| t.len())
                    + description.as_ref().map_or(0, |d| d.len())
            }
        };

        Self {
            size,
            compressed: false,
            compression_ratio: None,
            source_app: None,
            priority: 50, // Default priority
            tags: Vec::new(),
        }
    }
}
