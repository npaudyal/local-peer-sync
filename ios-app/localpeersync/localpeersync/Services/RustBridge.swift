//
//  RustBridge.swift
//  LocalPeerSync - Simplified Version (UPDATED)
//

import Foundation
import UIKit
import os.log

// MARK: - Shared Types (ADDED - needed for ClipboardContentType)

/// Clipboard content type enum - shared across the app
enum ClipboardContentType: Int32, CaseIterable {
    case text = 0
    case url = 1
    case image = 2
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL"
        case .image: return "Image"
        }
    }
}

// MARK: - FFI Function Declarations

@_silgen_name("sync_init")
func rust_sync_init(_ device_name: UnsafePointer<CChar>) -> OpaquePointer?

@_silgen_name("sync_start")
func rust_sync_start(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_stop")
func rust_sync_stop(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_cleanup")
func rust_sync_cleanup(_ handle: OpaquePointer)

@_silgen_name("sync_get_device_id")
func rust_sync_get_device_id(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_get_device_name")
func rust_sync_get_device_name(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_is_running")
func rust_sync_is_running(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_get_peer_count")
func rust_sync_get_peer_count(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_get_peers_json")
func rust_sync_get_peers_json(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_clipboard")
func rust_sync_clipboard(_ handle: OpaquePointer, _ content: UnsafePointer<CChar>) -> Int32

@_silgen_name("clipboard_content_changed")
func rust_clipboard_content_changed(_ handle: OpaquePointer, _ content: UnsafePointer<CChar>, _ type: Int32) -> Int32

@_silgen_name("get_clipboard_history_count")
func rust_get_clipboard_history_count(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_get_health_status")
func rust_sync_get_health_status(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_clipboard_enhanced")
func rust_sync_clipboard_enhanced(_ handle: OpaquePointer, _ content: UnsafePointer<CChar>, _ content_type: Int32, _ source_device: UnsafePointer<CChar>) -> Int32

@_silgen_name("sync_add_discovered_peer")
func rust_sync_add_discovered_peer(_ handle: OpaquePointer, _ device_id: UnsafePointer<CChar>, _ device_name: UnsafePointer<CChar>, _ ip_address: UnsafePointer<CChar>, _ port: Int32) -> Int32

@_silgen_name("sync_remove_peer")
func rust_sync_remove_peer(_ handle: OpaquePointer, _ device_id: UnsafePointer<CChar>) -> Int32

@_silgen_name("sync_get_trusted_peer_count")
func rust_sync_get_trusted_peer_count(_ handle: OpaquePointer) -> Int32


// MARK: - Device Info Structure

struct DeviceInfo {
    let id: String
    let name: String
}

// MARK: - Rust Bridge Actor

actor RustBridge {
    private var _handle: OpaquePointer?
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "RustBridge")
    
    var handle: OpaquePointer? {
        return _handle
    }
    
    init?(deviceName: String) async {
        logger.info("🔧 Initializing ENHANCED iOS RustBridge...")
        
        let result = deviceName.withCString { deviceNamePtr in
            rust_sync_init(deviceNamePtr)
        }
        
        if let handle = result {
            self._handle = handle
            logger.info("✅ ENHANCED iOS Rust bridge initialized successfully")
            
            if let healthStatus = await getHealthStatus() {
                logger.info("🏥 Initial health status: \(healthStatus)")
            }
        } else {
            logger.error("❌ rust_sync_init returned null handle")
            return nil
        }
    }
    
    func start() async -> Bool {
        logger.info("▶️ Starting ENHANCED Rust service...")
        
        guard let handle = _handle else {
            logger.error("❌ Cannot start - missing handle")
            return false
        }
        
        let result = rust_sync_start(handle) == 1
        
        if result {
            logger.info("✅ ENHANCED Rust service started successfully")
            
            if let healthStatus = await getHealthStatus() {
                logger.info("🏥 Post-start health status: \(healthStatus)")
            }
        } else {
            logger.error("❌ Failed to start ENHANCED Rust service")
        }
        
        return result
    }
    
    func stop() async -> Bool {
        logger.info("⏹️ Stopping ENHANCED Rust service...")
        
        guard let handle = _handle else {
            logger.error("❌ Cannot stop - missing handle")
            return false
        }
        
        let result = rust_sync_stop(handle) == 1
        
        if result {
            logger.info("✅ ENHANCED Rust service stopped successfully")
        } else {
            logger.error("❌ Failed to stop ENHANCED Rust service")
        }
        
        return result
    }
    
    func getDeviceInfo() async -> DeviceInfo {
        guard let handle = _handle else {
            logger.warning("⚠️ Cannot get device info - missing handle")
            return DeviceInfo(id: "unknown", name: "Unknown Device")
        }
        
        var deviceId = "unknown"
        if let deviceIdPtr = rust_sync_get_device_id(handle) {
            deviceId = String(cString: deviceIdPtr)
            rust_sync_free_string(deviceIdPtr)
        }
        
        var deviceName = "Unknown Device"
        if let deviceNamePtr = rust_sync_get_device_name(handle) {
            deviceName = String(cString: deviceNamePtr)
            rust_sync_free_string(deviceNamePtr)
        }
        
        return DeviceInfo(id: deviceId, name: deviceName)
    }
    
    func isRunning() async -> Bool {
        guard let handle = _handle else { return false }
        return rust_sync_is_running(handle) == 1
    }
    
    func getPeerCount() async -> Int {
        guard let handle = _handle else { return 0 }
        return Int(rust_sync_get_peer_count(handle))
    }
    
    func getPeers() async -> [String] {
        guard let handle = _handle else { return [] }
        
        guard let jsonPtr = rust_sync_get_peers_json(handle) else {
            logger.error("❌ rust_sync_get_peers_json returned null")
            return []
        }
        
        let jsonString = String(cString: jsonPtr)
        rust_sync_free_string(jsonPtr)
        
        guard let data = jsonString.data(using: .utf8),
              let peers = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            logger.error("❌ Failed to parse peers JSON: \(jsonString)")
            return []
        }
        
        return peers
    }
    
    func syncClipboard(_ content: String) async -> Bool {
        guard let handle = _handle else {
            logger.error("❌ Cannot sync clipboard - missing handle")
            return false
        }
        
        return content.withCString { contentPtr in
            rust_sync_clipboard(handle, contentPtr) == 1
        }
    }
    
    func notifyClipboardChange(content: String, type: ClipboardContentType) async -> Bool {
        guard let handle = _handle else {
            logger.error("❌ Cannot notify clipboard change - missing handle")
            return false
        }
        
        logger.info("📋 Notifying Rust of ENHANCED clipboard change: \(content.prefix(50))...")
        
        let success = content.withCString { contentPtr in
            rust_clipboard_content_changed(handle, contentPtr, type.rawValue) == 1
        }
        
        if success {
            logger.info("✅ Rust notified of ENHANCED clipboard change successfully")
        } else {
            logger.error("❌ Failed to notify Rust of ENHANCED clipboard change")
        }
        
        return success
    }
    
    func syncClipboardEnhanced(content: String, type: ClipboardContentType, sourceDevice: String = "iOS") async -> Bool {
        guard let handle = _handle else {
            logger.error("❌ Cannot sync enhanced clipboard - missing handle")
            return false
        }
        
        logger.info("📋 ENHANCED clipboard sync: \(content.prefix(50))... from \(sourceDevice)")
        
        let success = content.withCString { contentPtr in
            sourceDevice.withCString { sourcePtr in
                rust_sync_clipboard_enhanced(handle, contentPtr, type.rawValue, sourcePtr) == 1
            }
        }
        
        if success {
            logger.info("✅ ENHANCED clipboard sync successful")
        } else {
            logger.error("❌ ENHANCED clipboard sync failed")
        }
        
        return success
    }
    
    func getClipboardHistoryCount() async -> Int {
        guard let handle = _handle else { return 0 }
        return Int(rust_get_clipboard_history_count(handle))
    }
    
    func addDiscoveredPeer(deviceId: String, deviceName: String, ipAddress: String, port: Int) async -> Bool {
        guard let handle = _handle else {
            logger.error("❌ Cannot add discovered peer - missing handle")
            return false
        }
        
        logger.info("🌉 BRIDGE: Adding discovered peer to Rust: \(deviceName) (\(deviceId)) at \(ipAddress):\(port)")
        
        let success = deviceId.withCString { deviceIdPtr in
            deviceName.withCString { deviceNamePtr in
                ipAddress.withCString { ipPtr in
                    rust_sync_add_discovered_peer(handle, deviceIdPtr, deviceNamePtr, ipPtr, Int32(port)) == 1
                }
            }
        }
        
        if success {
            logger.info("✅ Successfully bridged peer to Rust: \(deviceName)")
            
            let trustedCount = await getTrustedPeerCount()
            logger.info("🔍 Rust now has \(trustedCount) trusted peers")
        } else {
            logger.error("❌ Failed to bridge peer to Rust: \(deviceName)")
        }
        
        return success
    }
    
    func removeDiscoveredPeer(deviceId: String) async -> Bool {
        guard let handle = _handle else {
            logger.error("❌ Cannot remove discovered peer - missing handle")
            return false
        }
        
        logger.info("🌉 BRIDGE: Removing peer from Rust: \(deviceId)")
        
        let success = deviceId.withCString { deviceIdPtr in
            rust_sync_remove_peer(handle, deviceIdPtr) == 1
        }
        
        if success {
            logger.info("✅ Successfully removed peer from Rust: \(deviceId)")
        } else {
            logger.error("❌ Failed to remove peer from Rust: \(deviceId)")
        }
        
        return success
    }
    
    func getTrustedPeerCount() async -> Int {
        guard let handle = _handle else { return 0 }
        return Int(rust_sync_get_trusted_peer_count(handle))
    }
    
    func getHealthStatus() async -> String? {
        guard let handle = _handle else { return nil }
        
        guard let statusPtr = rust_sync_get_health_status(handle) else { return nil }
        
        let statusString = String(cString: statusPtr)
        rust_sync_free_string(statusPtr)
        
        return statusString
    }
    
    func performDiagnostics() async -> [String: Any] {
        var diagnostics: [String: Any] = [:]
        
        diagnostics["handle_available"] = _handle != nil
        diagnostics["is_running"] = await isRunning()
        diagnostics["peer_count"] = await getPeerCount()
        diagnostics["trusted_peer_count"] = await getTrustedPeerCount()
        
        let deviceInfo = await getDeviceInfo()
        diagnostics["device_info"] = [
            "id": deviceInfo.id,
            "name": deviceInfo.name
        ]
        
        if let healthStatus = await getHealthStatus() {
            diagnostics["health_status"] = healthStatus
        }
        
        logger.info("🔍 Rust diagnostics: \(diagnostics)")
        return diagnostics
    }
    
    deinit {
        logger.info("🧹 ENHANCED iOS RustBridge deinitializing")
        
        if let handle = _handle {
            rust_sync_cleanup(handle)
            logger.info("✅ Called rust_sync_cleanup")
        }
    }
}
