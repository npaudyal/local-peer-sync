//
//  SyncService.swift
//  LocalPeerSync
//
//  iOS-optimized sync service
//

import Foundation
import Combine
import Network
import UIKit
import os.log

@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()
    
    // MARK: - Published Properties
    @Published var isRunning: Bool = false
    @Published var connectedPeers: [PeerDevice] = []
    @Published var discoveredPeers: [PeerDevice] = []
    @Published var trustedDevices: [PeerDevice] = []
    @Published var deviceName: String = ""
    @Published var deviceId: String = ""
    @Published var deviceModel: String = ""
    @Published var localIPAddress: String = ""
    @Published var currentNetworkName: String = ""
    @Published var port: Int = 8421
    @Published var statusDescription: String = "Initializing..."
    @Published var isDiscovering: Bool = false
    @Published var lastSyncTime: Date?
    @Published var syncCount: Int = 0
    @Published var errorCount: Int = 0

    
    // MARK: - Private Properties
    private var rustBridge: RustBridge?
    private var networkMonitor: NWPathMonitor?
    private var statusUpdateTimer: Timer?
    private var discoveryTimer: Timer?
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "SyncService")
    private var isInitialized = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        setupDeviceInfo()
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    func initialize() async {
        logger.info("🚀 Initializing SyncService...")
        
        do {
            try await initializeRustBridge()
            await startStatusUpdates()
            isInitialized = true
            statusDescription = "Ready"
            logger.info("✅ SyncService initialized successfully")
        } catch {
            logger.error("❌ Failed to initialize SyncService: \(error)")
            statusDescription = "Failed to initialize"
        }
    }
    
    func notifyClipboardChange(content: String, type: ClipboardContentType) async {
        guard let bridge = rustBridge, isRunning else {
            logger.info("📋 Skipping clipboard notification - service not ready")
            return
        }
        
        // Get the handle from the bridge
        guard let handle = await bridge.handle else {
            logger.error("❌ Cannot notify clipboard change - missing handle")
            return
        }
        
        let success = await bridge.notifyClipboardChange(content: content, type: type)
        
        if success {
            logger.info("📋 Successfully notified Rust of clipboard change")
        } else {
            logger.error("❌ Failed to notify Rust of clipboard change")
        }
    }
    
    func getClipboardHistoryCount() async -> Int {
        guard let bridge = rustBridge else { return 0 }
        return await bridge.getClipboardHistoryCount()
    }
    
    func toggleSync() {
        if isRunning {
            stopSync()
        } else {
            startSync()
        }
    }
    
    func startSync() {
        guard isInitialized, let bridge = rustBridge else {
            logger.warning("⚠️ Cannot start sync - service not initialized")
            return
        }
        
        logger.info("🚀 Starting sync service...")
        
        Task {
            let success = await bridge.start()
            
            await MainActor.run {
                if success {
                    self.isRunning = true
                    self.isDiscovering = true
                    self.statusDescription = "Searching for devices..."
                    self.startDiscoveryTimer()
                    
                    // Notify clipboard manager
                    ClipboardManager.shared.syncServiceDidStart()
                    
                    logger.info("✅ Sync service started successfully")
                } else {
                    self.statusDescription = "Failed to start"
                    logger.error("❌ Failed to start sync service")
                }
            }
        }
    }
    
    func stopSync() {
        guard let bridge = rustBridge else { return }
        
        logger.info("🛑 Stopping sync service...")
        
        Task {
            let success = await bridge.stop()
            
            await MainActor.run {
                if success {
                    self.isRunning = false
                    self.isDiscovering = false
                    self.connectedPeers.removeAll()
                    self.discoveredPeers.removeAll()
                    self.statusDescription = "Stopped"
                    self.stopDiscoveryTimer()
                    
                    // Notify clipboard manager
                    ClipboardManager.shared.syncServiceDidStop()
                    
                    logger.info("✅ Sync service stopped successfully")
                } else {
                    logger.error("❌ Failed to stop sync service")
                }
            }
        }
    }
    
    
    func syncClipboard(_ content: String) {
        guard isInitialized, let bridge = rustBridge, isRunning else {
            logger.info("📋 Skipping clipboard sync - service not ready")
            return
        }
        
        logger.info("📋 Syncing clipboard content: \(content.prefix(50))...")
        
        Task {
            let success = await bridge.syncClipboard(content)
            
            await MainActor.run {
                if success {
                    self.syncCount += 1
                    self.lastSyncTime = Date()
                    logger.info("✅ Clipboard synced successfully")
                    
                    // Send notification if app is in background
                    if UIApplication.shared.applicationState != .active {
                        NotificationManager.shared.sendSyncNotification(content: content)
                    }
                } else {
                    self.errorCount += 1
                    logger.error("❌ Failed to sync clipboard")
                }
            }
        }
    }
    
    // MARK: - Peer Management
    func scanForDevices() async {
        guard isRunning else { return }
        
        logger.info("🔍 Scanning for devices...")
        isDiscovering = true
        
        // Trigger active discovery
        await refreshPeers()
        
        // Update UI after scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isDiscovering = false
        }
    }
    
    func connectToPeer(_ peer: PeerDevice) async {
        logger.info("🤝 Connecting to peer: \(peer.name)")
        
        // In a real implementation, this would initiate a connection
        // For now, we'll simulate adding to trusted devices
        await MainActor.run {
            if !self.trustedDevices.contains(where: { $0.id == peer.id }) {
                var updatedPeer = peer
                updatedPeer.connectionStatus = .connected
                self.trustedDevices.append(updatedPeer)
                self.connectedPeers.append(updatedPeer)
                
                // Remove from discovered if present
                self.discoveredPeers.removeAll { $0.id == peer.id }
            }
        }
    }
    
    
    func refreshStatus() async {
        await updatePeerStatus()
        await updateNetworkInfo()
    }
    
    func refreshPeers() async {
        guard let bridge = rustBridge else { return }
        
        let peerCount = await bridge.getPeerCount()
        let peerNames = await bridge.getPeers()
        
        await MainActor.run {
            // Update connected peers based on actual data
            self.updateConnectedPeersFromRust(count: peerCount, names: peerNames)
            
            // Update status description
            if self.isRunning {
                if self.connectedPeers.isEmpty {
                    self.statusDescription = "Searching for devices..."
                } else {
                    self.statusDescription = "Connected to \(self.connectedPeers.count) device\(self.connectedPeers.count == 1 ? "" : "s")"
                }
            }
        }
    }
    
    func refreshConnections() async {
        // Background refresh for maintaining connections
        await refreshPeers()
    }
    
    // MARK: - Private Methods
    private func setupDeviceInfo() {
            self.deviceName = UIDevice.current.name
            self.deviceModel = UIDevice.current.model
            self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            
            logger.info("📱 Device info: \(self.deviceName) (\(self.deviceModel))")
        }
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkChange(path)
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    private func handleNetworkChange(_ path: NWPath) {
        let isConnected = path.status == .satisfied
        
        if isConnected {
            updateNetworkInfo()
            
            // Restart sync if it was running
            if isRunning {
                Task {
                    await refreshConnections()
                }
            }
        } else {
            localIPAddress = "No connection"
            currentNetworkName = "No network"
            
            // Clear peers if network is lost
            connectedPeers.removeAll()
            discoveredPeers.removeAll()
        }
        
        logger.info("🌐 Network status changed: \(isConnected ? "Connected" : "Disconnected")")
    }
    
    private func updateNetworkInfo() {
        // Get local IP address
        localIPAddress = getLocalIPAddress() ?? "Unknown"
        
        // Get WiFi network name
        currentNetworkName = getWiFiNetworkName() ?? "Unknown"
    }
    
    private func initializeRustBridge() async throws {
        let deviceName = "\(self.deviceName)-iOS"
        
        logger.info("🔧 Initializing Rust bridge with device name: \(deviceName)")
        
        guard let bridge = await RustBridge(deviceName: deviceName) else {
            throw SyncError.bridgeInitializationFailed
        }
        
        self.rustBridge = bridge
        
        // Get device info from Rust
        let deviceInfo = await bridge.getDeviceInfo()
        await MainActor.run {
            self.deviceId = deviceInfo.id
            if !deviceInfo.name.isEmpty {
                self.deviceName = deviceInfo.name
            }
        }
        
        logger.info("✅ Rust bridge initialized successfully")
    }
    
    private func startStatusUpdates() async {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshPeers()
            }
        }
        
        logger.info("⏰ Started status update timer")
    }
    
    private func startDiscoveryTimer() {
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.performPeriodicDiscovery()
            }
        }
    }
    
    private func stopDiscoveryTimer() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }
    
    private func performPeriodicDiscovery() async {
        // Simulate device discovery
        await generateSimulatedDiscoveredPeers()
    }
    
    private func updateConnectedPeersFromRust(count: Int, names: [String]) {
        // Clear current connected peers
        connectedPeers.removeAll()
        
        // Add peers based on Rust data
        for (index, name) in names.enumerated() {
            let peer = PeerDevice(
                id: "rust-peer-\(index)",
                name: name,
                model: "Unknown Device",
                deviceType: .unknown,
                ipAddress: "192.168.1.\(100 + index)",
                connectionStatus: .connected,
                isConnected: true,
                lastSeen: Date(),
                syncCount: Int.random(in: 1...50)
            )
            connectedPeers.append(peer)
        }
    }
    
    private func generateSimulatedDiscoveredPeers() async {
        // This would be replaced with real device discovery
        guard isRunning && discoveredPeers.count < 2 else { return }
        
        let simulatedDevices = [
            PeerDevice(
                id: "sim-mac-1",
                name: "MacBook Pro",
                model: "MacBook Pro 16-inch",
                deviceType: .mac,
                ipAddress: "192.168.1.101",
                connectionStatus: .discovered,
                isConnected: false,
                lastSeen: Date(),
                syncCount: 0
            ),
            PeerDevice(
                id: "sim-ipad-1",
                name: "iPad Air",
                model: "iPad Air (5th generation)",
                deviceType: .iPad,
                ipAddress: "192.168.1.102",
                connectionStatus: .discovered,
                isConnected: false,
                lastSeen: Date(),
                syncCount: 0
            )
        ]
        
        await MainActor.run {
            for device in simulatedDevices {
                if !self.discoveredPeers.contains(where: { $0.id == device.id }) &&
                   !self.connectedPeers.contains(where: { $0.id == device.id }) {
                    self.discoveredPeers.append(device)
                }
            }
        }
    }
    
    private func updatePeerStatus() async {
        // Update last seen times and connection status
        let now = Date()
        
        for i in 0..<connectedPeers.count {
            connectedPeers[i].lastSeen = now
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    let name = String(cString: (interface?.ifa_name)!)
                    
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        
                        getnameinfo(
                            interface?.ifa_addr,
                            socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST
                        )
                        
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    private func getWiFiNetworkName() -> String? {
        // iOS restricts access to WiFi network name
        // This would require special entitlements in a real app
        return "WiFi Network"
    }
    
    deinit {
        logger.info("🧹 SyncService deinitializing")
        statusUpdateTimer?.invalidate()
        discoveryTimer?.invalidate()
        networkMonitor?.cancel()
    }
}

// MARK: - Supporting Types
enum SyncError: LocalizedError {
    case bridgeInitializationFailed
    case networkUnavailable
    case peerConnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .bridgeInitializationFailed:
            return "Failed to initialize sync bridge"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .peerConnectionFailed:
            return "Failed to connect to peer device"
        }
    }
}
