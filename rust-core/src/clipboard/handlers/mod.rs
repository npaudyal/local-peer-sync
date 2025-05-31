//! Platform-specific clipboard handlers

// Declare all modules (but they'll only compile on their target platforms)
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
pub mod desktop;

#[cfg(target_os = "ios")]
pub mod ios;

#[cfg(target_os = "android")]
pub mod android;

// Re-export the platform-specific handlers
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
pub use desktop::DesktopClipboardHandler;

#[cfg(target_os = "ios")]
pub use ios::IOSClipboardHandler;

#[cfg(target_os = "android")]
pub use android::AndroidClipboardHandler;

// Also re-export the trait
pub use crate::clipboard::sync_engine::ClipboardHandler;
