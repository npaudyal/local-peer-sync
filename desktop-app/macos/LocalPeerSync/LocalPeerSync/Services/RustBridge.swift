//
//  RustBridge.swift
//  LocalPeerSync
//
//  Bridge to Rust core library
//

import Foundation
import os.log

struct DeviceInfo {
    let id: String
    let name: String
}

class RustBridge {
    private var handle: OpaquePointer?
    private var library: UnsafeMutableRawPointer?
    private let logger = Logger(subsystem: "com.localpeersync.macos", category: "RustBridge")
    
    init?(deviceName: String) {
        logger.info("🔧 Initializing RustBridge...")
        
        // Step 1: Find the library
        logger.info("📚 Looking for Rust library...")
        guard let libraryPath = Bundle.main.path(forResource: "liblocal_peer_sync_core", ofType: "dylib") else {
            logger.error("❌ Could not find Rust library in bundle")
            logger.error("Bundle path: \(Bundle.main.bundlePath)")
            return nil
        }
        
        logger.info("📚 Found library at: \(libraryPath)")
        
        // Step 2: Load the library
        library = dlopen(libraryPath, RTLD_LAZY)
        guard let library = library else {
            let error = String(cString: dlerror())
            logger.error("❌ Could not load Rust library: \(error)")
            return nil
        }
        
        logger.info("✅ Rust library loaded successfully")
        
        // Step 3: Find the init function
        guard let initFunc = dlsym(library, "sync_init") else {
            logger.error("❌ Could not find sync_init function")
            dlclose(library)
            return nil
        }
        
        logger.info("✅ Found sync_init function")
        
        // Step 4: Call initialization
        typealias InitFunction = @convention(c) (UnsafePointer<CChar>) -> OpaquePointer?
        let initFn = unsafeBitCast(initFunc, to: InitFunction.self)
        
        logger.info("🚀 Calling Rust initialization...")
        
        deviceName.withCString { deviceNamePtr in
            handle = initFn(deviceNamePtr)
        }
        
        if handle == nil {
            logger.error("❌ Rust initialization returned null handle")
            dlclose(library)
            return nil
        }
        
        logger.info("✅ Rust bridge initialized successfully")
    }
    
    func start() -> Bool {
        logger.info("▶️ Starting Rust service...")
        
        guard let handle = handle,
              let library = library,
              let startFunc = dlsym(library, "sync_start") else {
            logger.error("❌ Cannot start - missing handle or function")
            return false
        }
        
        typealias StartFunction = @convention(c) (OpaquePointer) -> Int32
        let startFn = unsafeBitCast(startFunc, to: StartFunction.self)
        let result = startFn(handle) == 1
        
        if result {
            logger.info("✅ Rust service started")
        } else {
            logger.error("❌ Failed to start Rust service")
        }
        
        return result
    }

    func stop() -> Bool {
        logger.info("⏹️ Stopping Rust service...")
        
        guard let handle = handle,
              let library = library,
              let stopFunc = dlsym(library, "sync_stop") else {
            return false
        }
        
        typealias StopFunction = @convention(c) (OpaquePointer) -> Int32
        let stopFn = unsafeBitCast(stopFunc, to: StopFunction.self)
        let result = stopFn(handle) == 1
        
        if result {
            logger.info("✅ Rust service stopped")
        } else {
            logger.error("❌ Failed to stop Rust service")
        }
        
        return result
    }
    
    func getDeviceInfo() -> DeviceInfo {
        guard let handle = handle,
              let library = library else {
            logger.warning("⚠️ Cannot get device info - missing handle")
            return DeviceInfo(id: "unknown", name: "Unknown Device")
        }
        
        // Get device ID
        var deviceId = "unknown"
        if let getDeviceIdFunc = dlsym(library, "sync_get_device_id") {
            typealias GetDeviceIdFunction = @convention(c) (OpaquePointer) -> UnsafeMutablePointer<CChar>?
            let getDeviceIdFn = unsafeBitCast(getDeviceIdFunc, to: GetDeviceIdFunction.self)
            
            if let deviceIdPtr = getDeviceIdFn(handle) {
                deviceId = String(cString: deviceIdPtr)
                // Free the string
                if let freeFunc = dlsym(library, "sync_free_string") {
                    typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
                    let freeFn = unsafeBitCast(freeFunc, to: FreeStringFunction.self)
                    freeFn(deviceIdPtr)
                }
            }
        }
        
        // Get device name
        var deviceName = "Unknown Device"
        if let getDeviceNameFunc = dlsym(library, "sync_get_device_name") {
            typealias GetDeviceNameFunction = @convention(c) (OpaquePointer) -> UnsafeMutablePointer<CChar>?
            let getDeviceNameFn = unsafeBitCast(getDeviceNameFunc, to: GetDeviceNameFunction.self)
            
            if let deviceNamePtr = getDeviceNameFn(handle) {
                deviceName = String(cString: deviceNamePtr)
                // Free the string
                if let freeFunc = dlsym(library, "sync_free_string") {
                    typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
                    let freeFn = unsafeBitCast(freeFunc, to: FreeStringFunction.self)
                    freeFn(deviceNamePtr)
                }
            }
        }
        
        return DeviceInfo(id: deviceId, name: deviceName)
    }
    
    func isRunning() -> Bool {
        guard let handle = handle,
              let library = library,
              let isRunningFunc = dlsym(library, "sync_is_running") else {
            return false
        }
        
        typealias IsRunningFunction = @convention(c) (OpaquePointer) -> Int32
        let isRunningFn = unsafeBitCast(isRunningFunc, to: IsRunningFunction.self)
        return isRunningFn(handle) == 1
    }
    
    func getPeerCount() -> Int {
        guard let handle = handle,
              let library = library,
              let getPeerCountFunc = dlsym(library, "sync_get_peer_count") else {
            return 0
        }
        
        typealias GetPeerCountFunction = @convention(c) (OpaquePointer) -> Int32
        let getPeerCountFn = unsafeBitCast(getPeerCountFunc, to: GetPeerCountFunction.self)
        return Int(getPeerCountFn(handle))
    }
    
    func getPeers() -> [String] {
        guard let handle = handle,
              let library = library,
              let getPeersFunc = dlsym(library, "sync_get_peers_json") else {
            return []
        }
        
        typealias GetPeersFunction = @convention(c) (OpaquePointer) -> UnsafeMutablePointer<CChar>?
        let getPeersFn = unsafeBitCast(getPeersFunc, to: GetPeersFunction.self)
        
        guard let jsonPtr = getPeersFn(handle) else {
            return []
        }
        
        let jsonString = String(cString: jsonPtr)
        
        // Free the C string
        if let freeFunc = dlsym(library, "sync_free_string") {
            typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
            let freeFn = unsafeBitCast(freeFunc, to: FreeStringFunction.self)
            freeFn(jsonPtr)
        }
        
        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let peers = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        
        return peers
    }
    
    func syncClipboard(_ content: String) -> Bool {
        guard let handle = handle,
              let library = library,
              let syncFunc = dlsym(library, "sync_clipboard") else {
            return false
        }
        
        typealias SyncClipboardFunction = @convention(c) (OpaquePointer, UnsafePointer<CChar>) -> Int32
        let syncFn = unsafeBitCast(syncFunc, to: SyncClipboardFunction.self)
        
        return content.withCString { contentPtr in
            syncFn(handle, contentPtr) == 1
        }
    }
    
    deinit {
        logger.info("🧹 RustBridge deinitializing")
        
        if let handle = handle,
           let library = library,
           let cleanupFunc = dlsym(library, "sync_cleanup") {
            typealias CleanupFunction = @convention(c) (OpaquePointer) -> Void
            let cleanupFn = unsafeBitCast(cleanupFunc, to: CleanupFunction.self)
            cleanupFn(handle)
        }
        
        if let library = library {
            dlclose(library)
        }
    }
}
