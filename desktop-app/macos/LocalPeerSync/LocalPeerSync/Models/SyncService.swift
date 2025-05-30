//
//  SyncService.swift
//  LocalPeerSync
//
//  Core sync service that bridges to Rust
//

import Foundation
import Combine
import os.log

class SyncService: ObservableObject {
    static let shared = SyncService()
    
    // MARK: - Published Properties
    @Published var isRunning: Bool = false
    @Published var peers: [String] = []
    @Published var deviceName: String = ""
    @Published var deviceId: String = ""
    @Published var port: Int = 8421
    @Published var statusText: String = "Initializing..."
    
    // MARK: - Private Properties
    private var rustBridge: RustBridge?
    private var updateTimer: Timer?
    private var clipboardMonitor: ClipboardMonitor?
    private let logger = Logger(subsystem: "com.localpeersync.macos", category: "SyncService")
    private var isInitialized = false
    
    // MARK: - Initialization
    private init() {
        logger.info("🚀 SyncService singleton initializing...")
        
        // Defer heavy initialization to avoid blocking the singleton creation
        DispatchQueue.main.async {
            self.initializeService()
        }
    }
    
    // MARK: - Private Initialization
    private func initializeService() {
        logger.info("🔧 Starting service initialization...")
        
        do {
            try setupService()
            startUpdateTimer()
            isInitialized = true
            logger.info("✅ SyncService initialized successfully")
        } catch {
            logger.error("❌ Failed to initialize SyncService: \(error)")
            DispatchQueue.main.async {
                self.statusText = "Failed to initialize"
            }
        }
    }
    
    // MARK: - Public Methods
    func toggleSync() {
        guard isInitialized else {
            logger.warning("⚠️ Service not initialized yet")
            return
        }
        
        if isRunning {
            stopSync()
        } else {
            startSync()
        }
    }
    
    func startSync() {
        guard isInitialized else {
            logger.warning("⚠️ Service not initialized yet")
            return
        }
        
        guard let bridge = rustBridge else {
            logger.error("❌ Rust bridge not initialized")
            return
        }
        
        logger.info("🚀 Starting sync service")
        
        if bridge.start() {
            // Start clipboard monitoring
            if clipboardMonitor == nil {
                clipboardMonitor = ClipboardMonitor()
            }
            clipboardMonitor?.startMonitoring()
            
            DispatchQueue.main.async {
                self.isRunning = true
                self.statusText = "Running"
            }
            logger.info("✅ Sync service started successfully")
        } else {
            logger.error("❌ Failed to start sync service")
            DispatchQueue.main.async {
                self.statusText = "Failed to start"
            }
        }
    }
    
    func stopSync() {
        guard isInitialized else { return }
        guard let bridge = rustBridge else { return }
        
        logger.info("🛑 Stopping sync service")
        
        // Stop clipboard monitoring first
        clipboardMonitor?.stopMonitoring()
        
        if bridge.stop() {
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusText = "Stopped"
                self.peers = []
            }
            logger.info("✅ Sync service stopped successfully")
        } else {
            logger.error("❌ Failed to stop sync service")
        }
    }
    
    func syncClipboard(_ content: String) {
        guard isInitialized, let bridge = rustBridge, isRunning else {
            logger.info("📋 Skipping clipboard sync - service not ready")
            return
        }
        
        logger.info("📋 Syncing clipboard content: \(content.prefix(50))...")
        
        if bridge.syncClipboard(content) {
            logger.info("✅ Clipboard synced successfully")
        } else {
            logger.error("❌ Failed to sync clipboard")
        }
    }
    
    // MARK: - Private Methods
    private func setupService() throws {
        let hostName = Host.current().localizedName ?? "Mac"
        let deviceName = "\(hostName)-LocalPeerSync"
        
        logger.info("🔧 Initializing Rust bridge with device name: \(deviceName)")
        
        guard let bridge = RustBridge(deviceName: deviceName) else {
            throw NSError(domain: "SyncService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize Rust bridge"
            ])
        }
        
        rustBridge = bridge
        
        let deviceInfo = bridge.getDeviceInfo()
        
        DispatchQueue.main.async {
            self.deviceName = deviceInfo.name
            self.deviceId = deviceInfo.id
            self.statusText = "Ready"
        }
        
        logger.info("✅ Rust bridge initialized successfully")
    }
    
    private func startUpdateTimer() {
        // Make sure we're on the main queue for timer
        DispatchQueue.main.async {
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                self.updateStatus()
            }
            self.logger.info("⏰ Update timer started")
        }
    }
    
    private func updateStatus() {
        guard isInitialized, let bridge = rustBridge else { return }
        
        let peerCount = bridge.getPeerCount()
        let peers = bridge.getPeers()
        let actualIsRunning = bridge.isRunning()
        
        DispatchQueue.main.async {
            self.peers = peers
            self.isRunning = actualIsRunning
            
            if self.isRunning {
                if peerCount > 0 {
                    self.statusText = "Connected to \(peerCount) device\(peerCount == 1 ? "" : "s")"
                } else {
                    self.statusText = "Searching for devices..."
                }
            } else if self.isInitialized {
                self.statusText = "Ready"
            }
        }
    }
    
    deinit {
        logger.info("🧹 SyncService deinitializing")
        updateTimer?.invalidate()
        clipboardMonitor?.stopMonitoring()
        stopSync()
    }
}
