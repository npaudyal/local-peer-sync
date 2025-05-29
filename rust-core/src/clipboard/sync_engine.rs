//! Core clipboard synchronization logic

use crate::Result;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::debug;

/// Manages clipboard synchronization
pub struct ClipboardSyncEngine {
    /// Current clipboard content
    current_content: Arc<RwLock<Option<String>>>,

    /// Clipboard history
    history: Arc<RwLock<Vec<String>>>,

    /// Maximum history size
    max_history_size: usize,
}

impl ClipboardSyncEngine {
    pub fn new(max_history_size: usize) -> Self {
        Self {
            current_content: Arc::new(RwLock::new(None)),
            history: Arc::new(RwLock::new(Vec::new())),
            max_history_size,
        }
    }

    /// Update clipboard content
    pub async fn set_content(&self, content: String) -> Result<()> {
        let mut current = self.current_content.write().await;
        let mut history = self.history.write().await;

        // Add to history if different from current
        if current.as_ref() != Some(&content) {
            history.push(content.clone());

            // Limit history size
            if history.len() > self.max_history_size {
                history.remove(0);
            }

            *current = Some(content);
            debug!("Clipboard content updated");
        }

        Ok(())
    }

    /// Get current clipboard content
    pub async fn get_content(&self) -> Option<String> {
        let current = self.current_content.read().await;
        current.clone()
    }

    /// Get clipboard history
    pub async fn get_history(&self) -> Vec<String> {
        let history = self.history.read().await;
        history.clone()
    }
}
