//! C API bindings for macOS integration

use crate::{LocalPeerSync, SyncConfig};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::sync::Arc;
use tokio::runtime::Runtime;
use tracing::{error, info};

/// Handle to the sync service
pub struct SyncHandle {
    sync: Arc<LocalPeerSync>,
    runtime: Arc<Runtime>,
}

/// Initialize the sync service
#[no_mangle]
pub extern "C" fn sync_init(device_name: *const c_char) -> *mut SyncHandle {
    if device_name.is_null() {
        return ptr::null_mut();
    }

    let device_name = match unsafe { CStr::from_ptr(device_name) }.to_str() {
        Ok(name) => name.to_string(),
        Err(_) => return ptr::null_mut(),
    };

    // Initialize logging
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .try_init();

    let runtime = match Runtime::new() {
        Ok(rt) => Arc::new(rt),
        Err(e) => {
            error!("Failed to create Tokio runtime: {}", e);
            return ptr::null_mut();
        }
    };

    let sync = runtime.block_on(async {
        let config = SyncConfig::with_device_name(device_name.clone());
        match LocalPeerSync::new(config).await {
            Ok(sync) => {
                let sync_arc = Arc::new(sync);

                // Create and connect clipboard engine
                let device_id = uuid::Uuid::new_v4().to_string();
                match crate::clipboard::ClipboardSyncEngine::new(device_id, 50) {
                    Ok(mut clipboard_engine) => {
                        // Start monitoring clipboard changes
                        if let Ok(_clipboard_rx) = clipboard_engine.start_monitoring().await {
                            let clipboard_engine_arc = Arc::new(clipboard_engine);

                            // Connect clipboard engine to sync service
                            if let Err(e) =
                                sync_arc.set_clipboard_engine(clipboard_engine_arc).await
                            {
                                error!("Failed to connect clipboard engine: {}", e);
                                return None;
                            }

                            info!("Clipboard engine connected successfully");
                        } else {
                            error!("Failed to start clipboard monitoring");
                            return None;
                        }
                    }
                    Err(e) => {
                        error!("Failed to create clipboard engine: {}", e);
                        return None;
                    }
                }

                Some(sync_arc)
            }
            Err(e) => {
                error!("Failed to create LocalPeerSync: {}", e);
                None
            }
        }
    });

    match sync {
        Some(sync) => {
            let handle = SyncHandle { sync, runtime };
            Box::into_raw(Box::new(handle))
        }
        None => ptr::null_mut(),
    }
}

/// Start the sync service
#[no_mangle]
pub extern "C" fn sync_start(handle: *mut SyncHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };

    match handle.runtime.block_on(async { handle.sync.start().await }) {
        Ok(_) => {
            info!("Sync service started successfully");
            1
        }
        Err(e) => {
            error!("Failed to start sync service: {}", e);
            0
        }
    }
}

/// Stop the sync service
#[no_mangle]
pub extern "C" fn sync_stop(handle: *mut SyncHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };

    match handle.runtime.block_on(async { handle.sync.stop().await }) {
        Ok(_) => {
            info!("Sync service stopped successfully");
            1
        }
        Err(e) => {
            error!("Failed to stop sync service: {}", e);
            0
        }
    }
}

/// Get device ID as C string
#[no_mangle]
pub extern "C" fn sync_get_device_id(handle: *mut SyncHandle) -> *mut c_char {
    if handle.is_null() {
        return ptr::null_mut();
    }

    let handle = unsafe { &*handle };
    let (device_id, _) = handle.sync.get_device_info();

    match CString::new(device_id) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get device name as C string
#[no_mangle]
pub extern "C" fn sync_get_device_name(handle: *mut SyncHandle) -> *mut c_char {
    if handle.is_null() {
        return ptr::null_mut();
    }

    let handle = unsafe { &*handle };
    let (_, device_name) = handle.sync.get_device_info();

    match CString::new(device_name) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if service is running
#[no_mangle]
pub extern "C" fn sync_is_running(handle: *mut SyncHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };

    handle
        .runtime
        .block_on(async { handle.sync.is_running().await }) as c_int
}

/// Get peer count
#[no_mangle]
pub extern "C" fn sync_get_peer_count(handle: *mut SyncHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };

    match handle
        .runtime
        .block_on(async { handle.sync.get_peers().await })
    {
        Ok(peers) => peers.len() as c_int,
        Err(_) => 0,
    }
}

/// Get peer names as JSON string
#[no_mangle]
pub extern "C" fn sync_get_peers_json(handle: *mut SyncHandle) -> *mut c_char {
    if handle.is_null() {
        return ptr::null_mut();
    }

    let handle = unsafe { &*handle };

    match handle
        .runtime
        .block_on(async { handle.sync.get_peers().await })
    {
        Ok(peers) => match serde_json::to_string(&peers) {
            Ok(json) => match CString::new(json) {
                Ok(c_string) => c_string.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Sync clipboard content
#[no_mangle]
pub extern "C" fn sync_clipboard(handle: *mut SyncHandle, content: *const c_char) -> c_int {
    if handle.is_null() || content.is_null() {
        return 0;
    }

    let handle = unsafe { &*handle };
    let content = match unsafe { CStr::from_ptr(content) }.to_str() {
        Ok(content) => content.to_string(),
        Err(_) => return 0,
    };

    match handle
        .runtime
        .block_on(async { handle.sync.sync_clipboard(content).await })
    {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

/// Free C string
#[no_mangle]
pub extern "C" fn sync_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Cleanup and free the sync handle
#[no_mangle]
pub extern "C" fn sync_cleanup(handle: *mut SyncHandle) {
    if !handle.is_null() {
        let handle = unsafe { Box::from_raw(handle) };
        let _ = handle.runtime.block_on(async { handle.sync.stop().await });
    }
}
