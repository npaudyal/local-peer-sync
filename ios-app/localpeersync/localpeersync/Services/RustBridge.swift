//
//  RustBridge.swift
//  LocalPeerSync - Simple iOS Version
//

import Foundation
import os.log

struct DeviceInfo {
    let id: String
    let name: String
}

class RustBridge {
    private var handle: OpaquePointer?
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "RustBridge")
    
    init?(deviceName: String) {
        logger.info("🔧 Initializing RustBridge...")
        
        // On iOS, the Rust library is statically linked, so we can call functions directly
        logger.info("🚀 Calling Rust initialization...")
        
        handle = deviceName.withCString { deviceNamePtr in
            sync_init(deviceNamePtr)
        }
        
        if handle == nil {
            logger.error("❌ Rust initialization returned null handle")
            return nil
        }
        
        logger.info("✅ Rust bridge initialized successfully")
    }
    
    func start() -> Bool {
        logger.info("▶️ Starting Rust service...")
        
        guard let handle = handle else {
            logger.error("❌ Cannot start - missing handle")
            return false
        }
        
        let result = sync_start(handle) == 1
        
        if result {
            logger.info("✅ Rust service started")
        } else {
            logger.error("❌ Failed to start Rust service")
        }
        
        return result
    }

    func stop() -> Bool {
        logger.info("⏹️ Stopping Rust service...")
        
        guard let handle = handle else {
            return false
        }
        
        let result = sync_stop(handle) == 1
        
        if result {
            logger.info("✅ Rust service stopped")
        } else {
            logger.error("❌ Failed to stop Rust service")
        }
        
        return result
    }
    
    func getDeviceInfo() -> DeviceInfo {
        guard let handle = handle else {
            logger.warning("⚠️ Cannot get device info - missing handle")
            return DeviceInfo(id: "unknown", name: "Unknown Device")
        }
        
        // Get device ID
        var deviceId = "unknown"
        if let deviceIdPtr = sync_get_device_id(handle) {
            deviceId = String(cString: deviceIdPtr)
            sync_free_string(deviceIdPtr)
        }
        
        // Get device name
        var deviceName = "Unknown Device"
        if let deviceNamePtr = sync_get_device_name(handle) {
            deviceName = String(cString: deviceNamePtr)
            sync_free_string(deviceNamePtr)
        }
        
        return DeviceInfo(id: deviceId, name: deviceName)
    }
    
    func isRunning() -> Bool {
        guard let handle = handle else { return false }
        return sync_is_running(handle) == 1
    }
    
    func getPeerCount() -> Int {
        guard let handle = handle else { return 0 }
        return Int(sync_get_peer_count(handle))
    }
    
    func getPeers() -> [String] {
        guard let handle = handle else { return [] }
        
        guard let jsonPtr = sync_get_peers_json(handle) else {
            return []
        }
        
        let jsonString = String(cString: jsonPtr)
        sync_free_string(jsonPtr)
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let peers = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        
        return peers
    }
    
    func syncClipboard(_ content: String) -> Bool {
        guard let handle = handle else { return false }
        
        return content.withCString { contentPtr in
            sync_clipboard(handle, contentPtr) == 1
        }
    }
    
    // Add this method to RustBridge class
    func testBridge() -> Bool {
        logger.info("🧪 Testing bridge connection...")
        
        let result = ios_test_bridge()
        
        if result == 42 {
            logger.info("✅ Bridge test successful!")
            return true
        } else {
            logger.error("❌ Bridge test failed!")
            return false
        }
    }

    // Add this FFI declaration
    @_silgen_name("ios_test_bridge")
    func ios_test_bridge() -> Int32
    
    func addDiscoveredPeer(deviceId: String, deviceName: String, ipAddress: String, port: Int) -> Bool {
        guard let handle = handle else {
            logger.error("❌ Cannot add discovered peer - missing handle")
            return false
        }
        
        logger.info("🌉 BRIDGE: Adding discovered peer to Rust: \(deviceName) (\(deviceId)) at \(ipAddress):\(port)")
        
        let success = deviceId.withCString { deviceIdPtr in
            deviceName.withCString { deviceNamePtr in
                ipAddress.withCString { ipPtr in
                    sync_add_discovered_peer(handle, deviceIdPtr, deviceNamePtr, ipPtr, Int32(port)) == 1
                }
            }
        }
        
        if success {
            logger.info("✅ Successfully bridged peer to Rust: \(deviceName)")
        } else {
            logger.error("❌ Failed to bridge peer to Rust: \(deviceName)")
        }
        
        return success
    }

    func getTrustedPeerCount() -> Int {
        guard let handle = handle else { return 0 }
        return Int(sync_get_trusted_peer_count(handle))
    }
    
    deinit {
        logger.info("🧹 RustBridge deinitializing")
        
        if let handle = handle {
            sync_cleanup(handle)
        }
    }
}

// MARK: - FFI Function Declarations
@_silgen_name("sync_init")
func sync_init(_ device_name: UnsafePointer<CChar>) -> OpaquePointer?

@_silgen_name("sync_start")
func sync_start(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_stop")
func sync_stop(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_cleanup")
func sync_cleanup(_ handle: OpaquePointer)

@_silgen_name("sync_get_device_id")
func sync_get_device_id(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_get_device_name")
func sync_get_device_name(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_is_running")
func sync_is_running(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_get_peer_count")
func sync_get_peer_count(_ handle: OpaquePointer) -> Int32

@_silgen_name("sync_get_peers_json")
func sync_get_peers_json(_ handle: OpaquePointer) -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_clipboard")
func sync_clipboard(_ handle: OpaquePointer, _ content: UnsafePointer<CChar>) -> Int32

@_silgen_name("sync_free_string")
func sync_free_string(_ ptr: UnsafeMutablePointer<CChar>)

@_silgen_name("sync_add_discovered_peer")
func sync_add_discovered_peer(_ handle: OpaquePointer, _ device_id: UnsafePointer<CChar>, _ device_name: UnsafePointer<CChar>, _ ip_address: UnsafePointer<CChar>, _ port: Int32) -> Int32

@_silgen_name("sync_get_trusted_peer_count")
func sync_get_trusted_peer_count(_ handle: OpaquePointer) -> Int32
