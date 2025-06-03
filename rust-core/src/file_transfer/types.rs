// src/file_transfer/types.rs
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Represents a file being transferred between devices
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferableFile {
    pub id: String,
    pub name: String,
    pub relative_path: String,
    pub size: u64,
    pub mime_type: String,
    pub checksum: String,
    pub is_directory: bool,
    pub permissions: FilePermissions,
    pub metadata: FileMetadata,
    pub chunks: Vec<FileChunk>,
}

/// File chunk for large file transfers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChunk {
    pub chunk_id: u32,
    pub offset: u64,
    pub size: u32,
    pub checksum: String,
    pub data: Vec<u8>,
    pub is_compressed: bool,
}

/// File permissions and security info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePermissions {
    pub readable: bool,
    pub writable: bool,
    pub executable: bool,
    pub is_safe_type: bool,
    pub scan_result: ScanResult,
}

/// Security scan result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ScanResult {
    Safe,
    Suspicious { reason: String },
    Blocked { reason: String },
    Pending,
}

/// Extended file metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileMetadata {
    pub created_at: u64,
    pub modified_at: u64,
    pub author: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub category: FileCategory,
}

/// AI-powered file categorization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FileCategory {
    Document,
    Image,
    Video,
    Audio,
    Archive,
    Code,
    Data,
    Executable,
    Unknown,
}

/// Complete file transfer package
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileTransferPackage {
    pub transfer_id: String,
    pub source_device_id: String,
    pub files: Vec<TransferableFile>,
    pub total_size: u64,
    pub compression_ratio: f32,
    pub created_at: u64,
    pub expires_at: u64,
    pub metadata: TransferMetadata,
}

/// Transfer metadata and analytics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferMetadata {
    pub title: Option<String>,
    pub description: Option<String>,
    pub priority: TransferPriority,
    pub estimated_duration: u64,
    pub bandwidth_limit: Option<u64>,
    pub auto_cleanup: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TransferPriority {
    Low,
    Normal,
    High,
    Urgent,
}

/// Transfer progress tracking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferProgress {
    pub transfer_id: String,
    pub files_completed: usize,
    pub files_total: usize,
    pub bytes_transferred: u64,
    pub bytes_total: u64,
    pub current_file: Option<String>,
    pub current_file_progress: f32,
    pub speed_bps: u64,
    pub eta_seconds: u64,
    pub status: TransferStatus,
    pub errors: Vec<TransferError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TransferStatus {
    Pending,
    Preparing,
    Transferring,
    Verifying,
    Completed,
    Failed,
    Cancelled,
    Paused,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferError {
    pub error_type: String,
    pub message: String,
    pub file_path: Option<String>,
    pub is_recoverable: bool,
    pub retry_count: u32,
    pub timestamp: u64,
}

/// Configuration for file transfers
#[derive(Debug, Clone)]
pub struct TransferConfig {
    pub max_file_size: u64,
    pub max_total_size: u64,
    pub max_files_per_transfer: usize,
    pub chunk_size: usize,
    pub max_concurrent_chunks: usize,
    pub compression_threshold: u64,
    pub encryption_enabled: bool,
    pub scan_files: bool,
    pub auto_cleanup_hours: u64,
    pub bandwidth_limit: Option<u64>,
}

impl Default for TransferConfig {
    fn default() -> Self {
        Self {
            max_file_size: 100 * 1024 * 1024,  // 100MB per file
            max_total_size: 500 * 1024 * 1024, // 500MB total
            max_files_per_transfer: 50,        // 50 files max
            chunk_size: 1024 * 1024,           // 1MB chunks
            max_concurrent_chunks: 4,          // 4 parallel chunks
            compression_threshold: 10 * 1024,  // Compress files > 10KB
            encryption_enabled: true,
            scan_files: true,
            auto_cleanup_hours: 24,
            bandwidth_limit: None,
        }
    }
}

impl TransferableFile {
    pub fn new(path: &PathBuf, base_path: &PathBuf) -> crate::Result<Self> {
        let metadata = std::fs::metadata(path)?;
        let relative_path = path
            .strip_prefix(base_path)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        let name = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();

        let mime_type = Self::detect_mime_type(path);
        let category = Self::categorize_file(&mime_type, path);
        let is_safe = Self::is_safe_file_type(path);

        Ok(Self {
            id: Uuid::new_v4().to_string(),
            name,
            relative_path,
            size: metadata.len(),
            mime_type,
            checksum: String::new(), // Will be calculated during reading
            is_directory: metadata.is_dir(),
            permissions: FilePermissions {
                readable: true,
                writable: false,
                executable: false,
                is_safe_type: is_safe,
                scan_result: if is_safe {
                    ScanResult::Safe
                } else {
                    ScanResult::Pending
                },
            },
            metadata: FileMetadata {
                created_at: metadata
                    .created()
                    .unwrap_or(SystemTime::UNIX_EPOCH)
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
                modified_at: metadata
                    .modified()
                    .unwrap_or(SystemTime::UNIX_EPOCH)
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
                author: None,
                description: None,
                tags: Vec::new(),
                category,
            },
            chunks: Vec::new(),
        })
    }

    fn detect_mime_type(path: &PathBuf) -> String {
        match path.extension().and_then(|ext| ext.to_str()) {
            Some("txt") => "text/plain".to_string(),
            Some("pdf") => "application/pdf".to_string(),
            Some("doc") | Some("docx") => "application/msword".to_string(),
            Some("jpg") | Some("jpeg") => "image/jpeg".to_string(),
            Some("png") => "image/png".to_string(),
            Some("gif") => "image/gif".to_string(),
            Some("mp4") => "video/mp4".to_string(),
            Some("mp3") => "audio/mpeg".to_string(),
            Some("zip") => "application/zip".to_string(),
            Some("json") => "application/json".to_string(),
            Some("xml") => "application/xml".to_string(),
            Some("csv") => "text/csv".to_string(),
            Some("py") => "text/x-python".to_string(),
            Some("rs") => "text/x-rust".to_string(),
            Some("js") => "text/javascript".to_string(),
            Some("html") => "text/html".to_string(),
            Some("css") => "text/css".to_string(),
            _ => "application/octet-stream".to_string(),
        }
    }

    fn categorize_file(mime_type: &str, path: &PathBuf) -> FileCategory {
        if mime_type.starts_with("text/") || mime_type.contains("document") {
            FileCategory::Document
        } else if mime_type.starts_with("image/") {
            FileCategory::Image
        } else if mime_type.starts_with("video/") {
            FileCategory::Video
        } else if mime_type.starts_with("audio/") {
            FileCategory::Audio
        } else if mime_type.contains("zip") || mime_type.contains("archive") {
            FileCategory::Archive
        } else if Self::is_code_file(path) {
            FileCategory::Code
        } else if Self::is_executable_file(path) {
            FileCategory::Executable
        } else {
            FileCategory::Unknown
        }
    }

    fn is_safe_file_type(path: &PathBuf) -> bool {
        let safe_extensions = [
            "txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "jpg", "jpeg", "png", "gif",
            "svg", "bmp", "tiff", "mp3", "mp4", "mov", "avi", "mkv", "wav", "flac", "zip", "7z",
            "tar", "gz", "json", "xml", "csv", "yaml", "toml", "py", "rs", "js", "ts", "html",
            "css", "md",
        ];

        path.extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| safe_extensions.contains(&ext.to_lowercase().as_str()))
            .unwrap_or(false)
    }

    fn is_code_file(path: &PathBuf) -> bool {
        let code_extensions = [
            "py", "rs", "js", "ts", "java", "cpp", "c", "h", "go", "php", "rb", "swift", "kt",
            "cs", "html", "css", "json", "xml", "yaml", "toml", "sql", "sh", "bat",
        ];

        path.extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| code_extensions.contains(&ext.to_lowercase().as_str()))
            .unwrap_or(false)
    }

    fn is_executable_file(path: &PathBuf) -> bool {
        let executable_extensions = [
            "exe", "msi", "dmg", "pkg", "deb", "rpm", "app", "dll", "so", "dylib", "bat", "cmd",
            "sh", "ps1",
        ];

        path.extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| executable_extensions.contains(&ext.to_lowercase().as_str()))
            .unwrap_or(false)
    }
}
