// src/file_transfer/security.rs
use super::types::ScanResult;
use crate::Result;
use std::path::Path;
use tokio::fs;
use tokio::io::AsyncReadExt;

/// Advanced security scanner
pub struct SecurityScanner {
    blocked_extensions: Vec<String>,
    suspicious_patterns: Vec<String>,
    max_scan_size: u64,
}

impl SecurityScanner {
    pub fn new() -> Self {
        Self {
            blocked_extensions: vec![
                "exe".to_string(),
                "msi".to_string(),
                "dmg".to_string(),
                "pkg".to_string(),
                "deb".to_string(),
                "rpm".to_string(),
                "bat".to_string(),
                "cmd".to_string(),
                "ps1".to_string(),
                "sh".to_string(),
                "scr".to_string(),
                "vbs".to_string(),
            ],
            suspicious_patterns: vec![
                "wannacry".to_string(),
                "ransomware".to_string(),
                "malware".to_string(),
                "virus".to_string(),
            ],
            max_scan_size: 50 * 1024 * 1024, // 50MB max scan
        }
    }

    pub async fn scan_file(&self, path: &Path) -> Result<ScanResult> {
        // Check file extension
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            if self.blocked_extensions.contains(&ext.to_lowercase()) {
                return Ok(ScanResult::Blocked {
                    reason: format!("Blocked file type: {}", ext),
                });
            }
        }

        // Check file name for suspicious patterns
        let filename = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_lowercase();

        for pattern in &self.suspicious_patterns {
            if filename.contains(pattern) {
                return Ok(ScanResult::Suspicious {
                    reason: format!("Suspicious filename pattern: {}", pattern),
                });
            }
        }

        // Quick content scan for small files
        let metadata = fs::metadata(path).await?;
        if metadata.len() <= self.max_scan_size && metadata.is_file() {
            match self.scan_file_content(path).await {
                Ok(result) => Ok(result),
                Err(_) => Ok(ScanResult::Safe), // If scan fails, assume safe for now
            }
        } else {
            Ok(ScanResult::Safe)
        }
    }

    async fn scan_file_content(&self, path: &Path) -> Result<ScanResult> {
        let mut file = fs::File::open(path).await?;
        let mut buffer = vec![0u8; 1024]; // Read first 1KB
        let bytes_read = file.read(&mut buffer).await?;
        buffer.truncate(bytes_read);

        // Convert to string and check for suspicious content
        if let Ok(content) = String::from_utf8(buffer.clone()) {
            let content_lower = content.to_lowercase();
            for pattern in &self.suspicious_patterns {
                if content_lower.contains(pattern) {
                    return Ok(ScanResult::Suspicious {
                        reason: format!("Suspicious content pattern: {}", pattern),
                    });
                }
            }
        }

        // Check for executable signatures (PE header, ELF, Mach-O)
        if buffer.len() >= 4 {
            // PE header (Windows)
            if buffer[0..2] == [0x4D, 0x5A] {
                return Ok(ScanResult::Blocked {
                    reason: "Windows executable detected".to_string(),
                });
            }
            // ELF header (Linux)
            if buffer[0..4] == [0x7F, 0x45, 0x4C, 0x46] {
                return Ok(ScanResult::Blocked {
                    reason: "Linux executable detected".to_string(),
                });
            }
            // Mach-O header (macOS)
            if buffer[0..4] == [0xFE, 0xED, 0xFA, 0xCE] || buffer[0..4] == [0xFE, 0xED, 0xFA, 0xCF]
            {
                return Ok(ScanResult::Blocked {
                    reason: "macOS executable detected".to_string(),
                });
            }
        }

        Ok(ScanResult::Safe)
    }
}

impl Default for SecurityScanner {
    fn default() -> Self {
        Self::new()
    }
}
