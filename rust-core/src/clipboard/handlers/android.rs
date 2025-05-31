//! Android clipboard handler (stub)
use crate::clipboard::{sync_engine::ClipboardHandler, types::*};
use crate::{Result, SyncError};

pub struct AndroidClipboardHandler {
    device_id: String,
}

impl AndroidClipboardHandler {
    pub fn new() -> Result<Self> {
        Err(SyncError::Unknown(
            "Android clipboard not yet implemented".to_string(),
        ))
    }
}

#[async_trait::async_trait]
impl ClipboardHandler for AndroidClipboardHandler {
    async fn read_content(&mut self, _config: &ClipboardConfig) -> Result<Option<ClipboardItem>> {
        Err(SyncError::Unknown(
            "Android clipboard not implemented".to_string(),
        ))
    }

    async fn write_content(&mut self, _item: &ClipboardItem) -> Result<()> {
        Err(SyncError::Unknown(
            "Android clipboard not implemented".to_string(),
        ))
    }

    async fn is_available(&self) -> bool {
        false
    }

    fn get_platform_name(&self) -> &'static str {
        "Android"
    }
}
