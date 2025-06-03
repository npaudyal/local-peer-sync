// src/file_transfer/progress.rs
use std::time::{Duration, Instant};

/// Bandwidth monitoring and optimization
#[derive(Debug)]
pub struct ProgressTracker {
    transfer_history: Vec<(Instant, u64)>, // (timestamp, bytes)
    window_size: Duration,
}

impl ProgressTracker {
    pub fn new() -> Self {
        Self {
            transfer_history: Vec::new(),
            window_size: Duration::from_secs(10),
        }
    }

    pub fn record_transfer(&mut self, bytes: u64) {
        let now = Instant::now();
        self.transfer_history.push((now, bytes));

        // Clean old entries
        let cutoff = now - self.window_size;
        self.transfer_history.retain(|(time, _)| *time > cutoff);
    }

    pub fn get_current_speed(&self) -> u64 {
        if self.transfer_history.len() < 2 {
            return 0;
        }

        let total_bytes: u64 = self.transfer_history.iter().map(|(_, bytes)| *bytes).sum();
        let duration =
            self.transfer_history.last().unwrap().0 - self.transfer_history.first().unwrap().0;

        if duration.as_secs() > 0 {
            total_bytes / duration.as_secs()
        } else {
            0
        }
    }
}

impl Default for ProgressTracker {
    fn default() -> Self {
        Self::new()
    }
}
