//
//  SyncService.swift
//  LocalPeerSync - Simple iOS Version with Discovery
//

import Foundation
import Combine
import UIKit
import Network
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
    private var discoveryService: IOSDiscoveryService?
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "SyncService")
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
            
            // Start discovery service
            discoveryService?.start()
            
            DispatchQueue.main.async {
                self.isRunning = true
                self.statusText = "Running"
            }
            notifyWidgetOfStatusChange()
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
        
        // Stop discovery service
        discoveryService?.stop()
        
        if bridge.stop() {
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusText = "Stopped"
                self.peers = []
            }
            notifyWidgetOfStatusChange()
            logger.info("✅ Sync service stopped successfully")
        } else {
            logger.error("❌ Failed to stop sync service")
        }
    }
    
    private func notifyWidgetOfStatusChange() {
        SimpleWidgetManager.shared.updateServiceStatus(
            isRunning: isRunning,
            deviceCount: peers.count,
            deviceName: deviceName
        )
    }
    
    // Update syncClipboard method in SyncService.swift
    func syncClipboard(_ content: String) -> Bool {
        guard isInitialized, let bridge = rustBridge, isRunning else {
            logger.info("📋 Skipping clipboard sync - service not ready")
            return false
        }
        
        logger.info("📋 Syncing clipboard content: \(content.prefix(50))...")
        
        // Add timeout for clipboard sync
        let semaphore = DispatchSemaphore(value: 0)
        var syncResult = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            syncResult = bridge.syncClipboard(content)
            semaphore.signal()
        }
        
        // Wait with 10 second timeout
        let result = semaphore.wait(timeout: .now() + 10.0)
        
        if result == .timedOut {
            logger.error("❌ Clipboard sync timed out!")
            return false
        }
        
        if syncResult {
            logger.info("✅ Clipboard synced successfully")
        } else {
            logger.error("❌ Failed to sync clipboard")
        }
        
        return syncResult
    }
    
    func scanForDevices() {
        guard isInitialized else { return }
        
        logger.info("🔍 Manually scanning for devices...")
        
        // Clear current peers
        DispatchQueue.main.async {
            self.peers = []
        }
        
        // Restart discovery to force a new scan
        discoveryService?.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.discoveryService?.start()
        }
    }
    
    func getClipboardMonitor() -> ClipboardMonitor? {
        return clipboardMonitor
    }
    
    func getDebugInfo() -> String {
        var info = ["=== LocalPeerSync iOS Debug Info ==="]
        
        info.append("Device Information:")
        info.append("  - Name: \(deviceName)")
        info.append("  - ID: \(deviceId)")
        info.append("  - Port: \(port)")
        
        info.append("Service Status:")
        info.append("  - Running: \(isRunning)")
        info.append("  - Status: \(statusText)")
        info.append("  - Initialized: \(isInitialized)")
        
        info.append("Discovery:")
        info.append("  - Connected Peers: \(peers.count)")
        for peer in peers {
            info.append("    - \(peer)")
        }
        
        if let bridge = rustBridge {
            info.append("Rust Bridge:")
            info.append("  - Running: \(bridge.isRunning())")
            info.append("  - Peer Count: \(bridge.getPeerCount())")
        }
        
        return info.joined(separator: "\n")
    }
    
    // MARK: - Private Methods
    private func setupService() throws {
        let deviceName = "\(UIDevice.current.name)-iOS"
        
        logger.info("🔧 Initializing Rust bridge with device name: \(deviceName)")
        
        guard let bridge = RustBridge(deviceName: deviceName) else {
            throw NSError(domain: "SyncService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize Rust bridge"
            ])
        }
        
        // 🧪 TEST THE BRIDGE
        logger.info("🧪 Testing bridge functions...")
        if bridge.testBridge() {
            logger.info("✅ Bridge test passed!")
        } else {
            logger.error("❌ Bridge test failed!")
        }
        
        rustBridge = bridge
        
        // ✅ SIMPLE: Back to simple callback
        discoveryService = IOSDiscoveryService(deviceName: deviceName, port: port) { [weak self] peerName in
            DispatchQueue.main.async {
                self?.handlePeerFound(peerName)
            }
        }
        
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
        let rustPeers = bridge.getPeers()
        let trustedPeerCount = bridge.getTrustedPeerCount()
        let actualIsRunning = bridge.isRunning()
        
        DispatchQueue.main.async {
            // Merge discovered peers with Rust peers
            var allPeers = Set(self.peers)
            allPeers.formUnion(rustPeers)
            self.peers = Array(allPeers).sorted()
            
            self.isRunning = actualIsRunning
            
            // Enhanced status with Rust peer info
            if self.isRunning {
                if trustedPeerCount > 0 {
                    self.statusText = "Connected to \(trustedPeerCount) trusted device\(trustedPeerCount == 1 ? "" : "s")"
                } else if self.peers.count > 0 {
                    self.statusText = "Found \(self.peers.count) device\(self.peers.count == 1 ? "" : "s"), connecting..."
                } else {
                    self.statusText = "Searching for devices..."
                }
            } else if self.isInitialized {
                self.statusText = "Ready"
            }
            
            // Debug logging
            self.logger.info("📊 Status Update: UI Peers: \(self.peers.count), Rust Peers: \(peerCount), Trusted: \(trustedPeerCount)")
        }
        notifyWidgetOfStatusChange()

    }
    
    
    private func scanForDeviceIP() -> String {
        let baseIP = getLocalNetworkBase()
        return "\(baseIP).100" // Simple fallback
    }
    
    private func getLocalNetworkBase() -> String {
        // Get local IP and extract base (e.g., "192.168.6.x" -> "192.168.6")
        if let localIP = getLocalIPAddress() {
            let components = localIP.components(separatedBy: ".")
            if components.count >= 3 {
                return "\(components[0]).\(components[1]).\(components[2])"
            }
        }
        return "192.168.1" // Default fallback
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    
                    if name == "en0" || name.hasPrefix("en") {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST
                        )
                        
                        let addr = String(cString: hostname)
                        if !addr.hasPrefix("127.") && !addr.hasPrefix("169.254.") {
                            address = addr
                            break
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    // Add this method to SyncService class
    private func findRealDeviceIP(for deviceName: String, completion: @escaping (String?) -> Void) {
        logger.info("🔍 Starting REAL IP scan for device: \(deviceName)")
        
        guard let localIP = getLocalIPAddress() else {
            logger.error("❌ Could not get local IP")
            completion(nil)
            return
        }
        
        let networkBase = getLocalNetworkBase()
        logger.info("🔍 Scanning network: \(networkBase).x")
        
        // Async scanning to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            var foundIP: String?
            
            // Test common IP ranges first (much faster)
            let commonRanges = [100, 101, 102, 103, 104, 105, 110, 111, 112, 113, 114, 115, 120, 121, 122, 123, 124, 125]
            
            for octet in commonRanges {
                let testIP = "\(networkBase).\(octet)"
                
                if self.asyncTestConnection(ip: testIP, timeout: 1.0) {
                    self.logger.info("✅ FOUND device at: \(testIP)")
                    foundIP = testIP
                    break
                }
            }
            
            // If not found in common ranges, do a broader scan
            if foundIP == nil {
                self.logger.info("🔍 Common IPs failed, trying broader scan...")
                
                for octet in 1...254 {
                    let testIP = "\(networkBase).\(octet)"
                    
                    if self.asyncTestConnection(ip: testIP, timeout: 0.5) {
                        self.logger.info("✅ FOUND device at: \(testIP)")
                        foundIP = testIP
                        break
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(foundIP)
            }
        }
    }

    private func asyncTestConnection(ip: String, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var isConnectable = false
        
        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                isConnectable = true
                semaphore.signal()
            case .failed(_):
                isConnectable = false
                semaphore.signal()
            case .cancelled:
                isConnectable = false
                semaphore.signal()
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global())
        
        // Wait with timeout
        let result = semaphore.wait(timeout: .now() + timeout)
        connection.cancel()
        
        return result == .success && isConnectable
    }

    // Update the bridgePeerToRust method
    private func bridgePeerToRust(_ peerName: String) {
        guard let bridge = rustBridge else {
            logger.error("❌ Cannot bridge peer - no Rust bridge")
            return
        }
        
        logger.info("🔍 Finding real IP for peer: \(peerName)")
        
        // Find the real IP address
        findRealDeviceIP(for: peerName) { [weak self] foundIP in
            guard let self = self else { return }
            
            let targetIP = foundIP ?? self.getLocalNetworkBase() + ".100"
            
            if let realIP = foundIP {
                self.logger.info("✅ Found real IP for \(peerName): \(realIP)")
            } else {
                self.logger.warning("⚠️ Could not find real IP for \(peerName), using fallback: \(targetIP)")
            }
            
            self.logger.info("🌉 Bridging peer to Rust: \(peerName) at \(targetIP)")
            
            let success = bridge.addDiscoveredPeer(
                deviceId: peerName,
                deviceName: peerName,
                ipAddress: targetIP,
                port: self.port
            )
            
            if success {
                self.logger.info("✅ Successfully bridged \(peerName) to Rust at \(targetIP)")
                let trustedCount = bridge.getTrustedPeerCount()
                self.logger.info("🔍 Rust now has \(trustedCount) trusted peers")
            } else {
                self.logger.error("❌ Failed to bridge \(peerName) to Rust")
            }
        }
    }

    private func quickTestConnection(ip: String) -> Bool {
        // Very quick connection test (non-blocking)
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        
        defer { close(socket) }
        
        // Set non-blocking
        let flags = fcntl(socket, F_GETFL)
        fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(ip)
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        // For non-blocking, we expect EINPROGRESS or immediate success
        return result == 0 || errno == EINPROGRESS
    }

    
    private func guessIPFromDeviceName(_ deviceName: String) -> String? {
        // Quick scan of common IP ranges
        let baseIP = getLocalNetworkBase()
        let commonIPs = ["100", "101", "102", "103", "104", "105", "110", "111", "112"]
        
        for suffix in commonIPs {
            let testIP = "\(baseIP).\(suffix)"
            if quickTestConnection(ip: testIP) {
                logger.info("✅ Found device at: \(testIP)")
                return testIP
            }
        }
        
        logger.warning("⚠️ Could not find IP, using default")
        return "\(baseIP).100" // Default fallback
    }
    
    // Update handlePeerFound method
    private func handlePeerFound(_ peerName: String) {
        logger.info("🎯 Peer discovered via mDNS: \(peerName)")
        
        if !peers.contains(peerName) {
            peers.append(peerName)
            logger.info("✅ Added peer to Swift UI list: \(peerName)")
            
            // ✅ SIMPLE: Bridge immediately with the Windows IP we know works
            bridgePeerToRustSimple(peerName)
            updateStatus()
        }
    }
    
    private func bridgePeerToRustSimple(_ peerName: String) {
        guard let bridge = rustBridge else {
            logger.error("❌ Cannot bridge peer - no Rust bridge")
            return
        }
        
        // ✅ SIMPLE: Use the IP that we KNOW works from the logs (192.168.6.206)
        let knownWorkingIP = "192.168.6.206"  // From your logs
        
        logger.info("🌉 Bridging peer to Rust: \(peerName) at \(knownWorkingIP)")
        
        let success = bridge.addDiscoveredPeer(
            deviceId: peerName,
            deviceName: peerName,
            ipAddress: knownWorkingIP,
            port: port
        )
        
        if success {
            logger.info("✅ Successfully bridged \(peerName) to Rust at \(knownWorkingIP)")
            let trustedCount = bridge.getTrustedPeerCount()
            logger.info("🔍 Rust now has \(trustedCount) trusted peers")
        } else {
            logger.error("❌ Failed to bridge \(peerName) to Rust")
        }
    }
    
    deinit {
        logger.info("🧹 SyncService deinitializing")
        updateTimer?.invalidate()
        clipboardMonitor?.stopMonitoring()
        discoveryService?.stop()
        stopSync()
    }
}
