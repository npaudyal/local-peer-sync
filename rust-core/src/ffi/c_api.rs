//! C API bindings for iOS integration - ENHANCED with peer bridging
use crate::{LocalPeerSync, SyncConfig};
use crate::clipboard::{ClipboardItem, ClipboardContent, ClipboardSyncEngine};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::sync::Arc;
use tokio::runtime::Runtime;
use tracing::{error, info};
/// Simple test function to verify FFI integration
#[no_mangle]
pub extern "C" fn test_rust_connection() -> c_int {
println!("🦀 Rust test function called successfully!");
42
}
/// Another test with string
#[no_mangle]
pub extern "C" fn test_rust_string() -> *mut c_char {
let test_string = "Hello from Rust!";
match CString::new(test_string) {
Ok(c_string) => c_string.into_raw(),
Err(_) => ptr::null_mut(),
}
}
/// Handle to the sync service
pub struct SyncHandle {
sync: Arc<LocalPeerSync>,
runtime: Arc<Runtime>,
clipboard_engine: Option<Arc<ClipboardSyncEngine>>,
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

            // Create clipboard engine but make it optional for iOS
            let device_id = uuid::Uuid::new_v4().to_string();
            let clipboard_engine = match ClipboardSyncEngine::new(device_id, 50) {
                Ok(mut clipboard_engine) => {
                    info!("Clipboard engine created successfully");
                    
                    // Try to start monitoring, but don't fail if it doesn't work on iOS
                    match clipboard_engine.start_monitoring().await {
                        Ok(_clipboard_rx) => {
                            let clipboard_engine_arc = Arc::new(clipboard_engine);
                            
                            // Connect clipboard engine to sync service
                            if let Err(e) = sync_arc.set_clipboard_engine(clipboard_engine_arc.clone()).await {
                                error!("Failed to connect clipboard engine: {}", e);
                                None
                            } else {
                                info!("Clipboard engine connected successfully");
                                Some(clipboard_engine_arc)
                            }
                        }
                        Err(e) => {
                            info!("Failed to start clipboard monitoring: {}, continuing without it", e);
                            None
                        }
                    }
                }
                Err(e) => {
                    info!("Clipboard engine not available: {}, continuing without it", e);
                    None
                }
            };

            Some((sync_arc, clipboard_engine))
        }
        Err(e) => {
            error!("Failed to create LocalPeerSync: {}", e);
            None
        }
    }
});

match sync {
    Some((sync, clipboard_engine)) => {
        let handle = SyncHandle { 
            sync, 
            runtime,
            clipboard_engine,
        };
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
/// 🆕 ENHANCED: Add a discovered peer from iOS Swift discovery
#[no_mangle]
pub extern "C" fn sync_add_discovered_peer(
handle: *mut SyncHandle,
device_id: *const c_char,
device_name: *const c_char,
ip_address: *const c_char,
port: c_int,
) -> c_int {
if handle.is_null() || device_id.is_null() || device_name.is_null() || ip_address.is_null() {
error!("❌ sync_add_discovered_peer: Invalid parameters");
return 0;
}
let handle = unsafe { &*handle };

let device_id_str = match unsafe { CStr::from_ptr(device_id) }.to_str() {
    Ok(id) => id.to_string(),
    Err(e) => {
        error!("❌ Failed to parse device_id: {}", e);
        return 0;
    }
};

let device_name_str = match unsafe { CStr::from_ptr(device_name) }.to_str() {
    Ok(name) => name.to_string(),
    Err(e) => {
        error!("❌ Failed to parse device_name: {}", e);
        return 0;
    }
};

let ip_str = match unsafe { CStr::from_ptr(ip_address) }.to_str() {
    Ok(ip) => ip.to_string(),
    Err(e) => {
        error!("❌ Failed to parse ip_address: {}", e);
        return 0;
    }
};

info!("🌉 BRIDGE: Adding iOS-discovered peer: {} ({}) at {}:{}", 
      device_name_str, device_id_str, ip_str, port);

handle.runtime.block_on(async {
    // Get the peer manager from SyncManager
    let manager = handle.sync.manager.read().await;
    let peer_manager = manager.get_peer_manager().await;
    
    // Create socket address
    use std::net::{IpAddr, SocketAddr};
    let ip_addr: IpAddr = match ip_str.parse() {
        Ok(addr) => addr,
        Err(e) => {
            error!("❌ Failed to parse IP address {}: {}", ip_str, e);
            return 0;
        }
    };
    
    let socket_addr = SocketAddr::new(ip_addr, port as u16);
    
    // Create and add peer
    let peer = crate::network::peer::Peer::new(
        device_id_str.clone(),
        device_name_str.clone(),
        socket_addr,
    );
    
    info!("📝 Adding peer to Rust PeerManager: {} ({}) at {}", 
          device_name_str, device_id_str, socket_addr);
    peer_manager.add_peer(peer).await;
    
    // Auto-trust the peer (for testing - you can make this configurable)
    if let Err(e) = peer_manager.trust_peer(&device_id_str).await {
        error!("❌ Failed to trust iOS-discovered peer: {}", e);
        0
    } else {
        info!("✅ iOS-discovered peer trusted: {}", device_name_str);
        
        // Verify peer was added by checking count
        let peer_count = peer_manager.get_trusted_peers().await.len();
        info!("🔍 Rust now has {} trusted peers", peer_count);
        
        1
    }
})
}
/// 🆕 ENHANCED: Remove a peer that's no longer available
#[no_mangle]
pub extern "C" fn sync_remove_peer(
handle: *mut SyncHandle,
device_id: *const c_char,
) -> c_int {
if handle.is_null() || device_id.is_null() {
return 0;
}
let handle = unsafe { &*handle };

let device_id_str = match unsafe { CStr::from_ptr(device_id) }.to_str() {
    Ok(id) => id.to_string(),
    Err(_) => return 0,
};

info!("🌉 BRIDGE: Removing iOS peer: {}", device_id_str);

handle.runtime.block_on(async {
    let manager = handle.sync.manager.read().await;
    let peer_manager = manager.get_peer_manager().await;
    
    match peer_manager.remove_peer(&device_id_str).await {
        Ok(()) => {
            info!("✅ Removed iOS peer: {}", device_id_str);
            1
        }
        Err(e) => {
            error!("❌ Failed to remove iOS peer {}: {}", device_id_str, e);
            0
        }
    }
})
}
/// Notify Rust that iOS clipboard content changed
#[no_mangle]
pub extern "C" fn clipboard_content_changed(
handle: *mut SyncHandle,
content: *const c_char,
content_type: c_int,
) -> c_int {
if handle.is_null() || content.is_null() {
return 0;
}
let handle = unsafe { &*handle };

let content_str = match unsafe { CStr::from_ptr(content) }.to_str() {
    Ok(content) => content.to_string(),
    Err(_) => return 0,
};

info!("📋 iOS clipboard changed: {} chars, type: {}", content_str.len(), content_type);

// Create clipboard item based on type
let clipboard_content = match content_type {
    0 => ClipboardContent::Text { 
        content: content_str, 
        encoding: "UTF-8".to_string() 
    },
    1 => ClipboardContent::Url { 
        url: content_str, 
        title: None, 
        description: None 
    },
    _ => ClipboardContent::Text { 
        content: content_str, 
        encoding: "UTF-8".to_string() 
    },
};

let item = ClipboardItem::new(clipboard_content, "iOS".to_string());

// Sync to network
handle.runtime.block_on(async {
    // Check peer count before syncing
    let manager = handle.sync.manager.read().await;
    let peer_manager = manager.get_peer_manager().await;
    let trusted_peers = peer_manager.get_trusted_peers().await;
    
    info!("📊 Before sync - Trusted peers: {}", trusted_peers.len());
    for peer in &trusted_peers {
        info!("  📱 Peer: {} at {}", peer.device_name, peer.address);
    }
    
    if trusted_peers.is_empty() {
        error!("💥 No trusted peers available for sync!");
        return 0;
    }
    
    if let Err(e) = handle.sync.sync_clipboard(item.summary()).await {
        error!("❌ Failed to sync iOS clipboard change: {}", e);
        0
    } else {
        info!("✅ Successfully synced iOS clipboard change to {} peers", trusted_peers.len());
        1
    }
})
}
/// Get clipboard history count
#[no_mangle]
pub extern "C" fn get_clipboard_history_count(handle: *mut SyncHandle) -> c_int {
if handle.is_null() {
return 0;
}
let handle = unsafe { &*handle };

if let Some(ref clipboard_engine) = handle.clipboard_engine {
    handle.runtime.block_on(async {
        clipboard_engine.get_history().await.len() as c_int
    })
} else {
    0
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
/// Get health status for debugging
#[no_mangle]
pub extern "C" fn sync_get_health_status(handle: *mut SyncHandle) -> *mut c_char {
if handle.is_null() {
return ptr::null_mut();
}
let handle = unsafe { &*handle };

let health_status = handle.runtime.block_on(async {
    let manager = handle.sync.manager.read().await;
    manager.health_check().await
});

let status_json = serde_json::json!({
    "tcp_server_running": health_status.tcp_server_running,
    "peer_count": health_status.peer_count,
    "rust_mdns_enabled": health_status.rust_mdns_enabled,
    "platform": health_status.platform
});

match serde_json::to_string(&status_json) {
    Ok(json) => match CString::new(json) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => ptr::null_mut(),
    },
    Err(_) => ptr::null_mut(),
}
}
/// Force sync a clipboard item (enhanced version)
#[no_mangle]
pub extern "C" fn sync_clipboard_enhanced(
handle: *mut SyncHandle,
content: *const c_char,
_content_type: c_int,
source_device: *const c_char,
) -> c_int {
if handle.is_null() || content.is_null() {
return 0;
}
let handle = unsafe { &*handle };

let content_str = match unsafe { CStr::from_ptr(content) }.to_str() {
    Ok(content) => content.to_string(),
    Err(_) => return 0,
};

let source_str = if source_device.is_null() {
    "iOS".to_string()
} else {
    match unsafe { CStr::from_ptr(source_device) }.to_str() {
        Ok(source) => source.to_string(),
        Err(_) => "iOS".to_string(),
    }
};

info!("📋 Enhanced clipboard sync from {}: {} chars", source_str, content_str.len());

match handle.runtime.block_on(async {
    handle.sync.sync_clipboard(content_str).await
}) {
    Ok(_) => {
        info!("✅ Enhanced clipboard sync successful");
        1
    }
    Err(e) => {
        error!("❌ Enhanced clipboard sync failed: {}", e);
        0
    }
}
}
/// 🆕 DEBUG: Get trusted peer count for debugging
#[no_mangle]
pub extern "C" fn sync_get_trusted_peer_count(handle: *mut SyncHandle) -> c_int {
if handle.is_null() {
return 0;
}
let handle = unsafe { &*handle };

handle.runtime.block_on(async {
    let manager = handle.sync.manager.read().await;
    let peer_manager = manager.get_peer_manager().await;
    let trusted_peers = peer_manager.get_trusted_peers().await;
    
    info!("🔍 DEBUG: Trusted peer count: {}", trusted_peers.len());
    for peer in &trusted_peers {
        info!("  📱 Trusted peer: {} at {}", peer.device_name, peer.address);
    }
    
    trusted_peers.len() as c_int
})
}