//! World-class clipboard synchronization module

pub mod handlers;
pub mod sync_engine;
pub mod types;

pub use sync_engine::*;
pub use types::*;

// Re-export handlers based on platform
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
pub use handlers::DesktopClipboardHandler;

#[cfg(target_os = "ios")]
pub use handlers::IOSClipboardHandler;

#[cfg(target_os = "android")]
pub use handlers::AndroidClipboardHandler;
