
//  SyncService.swift
//  LocalPeerSync
//
//  iOS-optimized sync service with native advertising and discovery
//

import Foundation
import Combine
import Network
import UIKit
import os.log
import SystemConfiguration

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
    
    // MARK: - iOS Native mDNS Properties
    private var nativeAdvertiser: NetService?
    private var nativeDiscoveryBrowser: NetServiceBrowser?
    private var nativeDiscoveryDelegate: NativeDiscoveryDelegate?
    private var nativeAdvertiserDelegate: NativeAdvertiserDelegate?
    private var discoveredServices: [String: NetService] = [:]
    
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
    
    func notifyClipboardChange(content: String, type: ClipboardContentType) async -> Bool {
        guard let bridge = rustBridge, isRunning else {
            logger.info("📋 Skipping clipboard notification - service not ready")
            return false
        }
        
        guard let handle = await bridge.handle else {
            logger.error("❌ Cannot notify clipboard change - missing handle")
            return false
        }
        
        let success = await bridge.notifyClipboardChange(content: content, type: type)
        
        if success {
            logger.info("📋 Successfully notified Rust of clipboard change")
        } else {
            logger.error("❌ Failed to notify Rust of clipboard change")
        }
        return success
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
    
    // MARK: - iOS Native Advertising
    private func startNativeAdvertising() {
        logger.info("🎯 ===== STARTING NATIVE iOS ADVERTISING =====")
        
        // Stop any existing advertising
        nativeAdvertiser?.stop()
        
        // Create TXT record data
        let txtData = createTXTRecord()
        
        // Create NetService for advertising
        nativeAdvertiser = NetService(
            domain: "local.",
            type: "_localpeersync._tcp.",
            name: deviceName,
            port: Int32(port)
        )
        
        nativeAdvertiserDelegate = NativeAdvertiserDelegate()
        nativeAdvertiser?.delegate = nativeAdvertiserDelegate
        
        // Set TXT record
        nativeAdvertiser?.setTXTRecord(txtData)
        
        logger.info("📝 Advertising details:")
        logger.info("   📱 Name: \(self.deviceName)")
        logger.info("   🔌 Port: \(self.port)")
        logger.info("   🆔 Device ID: \(self.deviceId)")
        logger.info("   🌐 Local IP: \(self.localIPAddress)")
        
        // Start advertising
        nativeAdvertiser?.publish()
        
        logger.info("✅ Native iOS advertising started")
    }
    
    private func stopNativeAdvertising() {
        logger.info("🛑 Stopping native iOS advertising")
        nativeAdvertiser?.stop()
        nativeAdvertiser = nil
        nativeAdvertiserDelegate = nil
    }
    
    private func createTXTRecord() -> Data {
        let txtDict: [String: Data] = [
            "device_id": deviceId.data(using: .utf8) ?? Data(),
            "version": "0.1.0".data(using: .utf8) ?? Data(),
            "encryption": "true".data(using: .utf8) ?? Data(),
            "port": "\(port)".data(using: .utf8) ?? Data(),
            "platform": "iOS".data(using: .utf8) ?? Data()
        ]
        
        return NetService.data(fromTXTRecord: txtDict)
    }
    
    // MARK: - iOS Native Discovery
    private func startNativeDiscovery() {
        logger.info("🎯 ===== STARTING NATIVE iOS DISCOVERY =====")
        
        // Stop any existing discovery
        nativeDiscoveryBrowser?.stop()
        
        // Create new browser and delegate
        nativeDiscoveryBrowser = NetServiceBrowser()
        nativeDiscoveryDelegate = NativeDiscoveryDelegate { [weak self] service in
            self?.handleDiscoveredService(service)
        }
        
        nativeDiscoveryBrowser?.delegate = nativeDiscoveryDelegate
        
        logger.info("🔍 Starting iOS NetServiceBrowser for _localpeersync._tcp.")
        nativeDiscoveryBrowser?.searchForServices(ofType: "_localpeersync._tcp.", inDomain: "local.")
        
        logger.info("✅ Native iOS discovery started")
    }
    
    private func stopNativeDiscovery() {
        logger.info("🛑 Stopping native iOS discovery")
        nativeDiscoveryBrowser?.stop()
        nativeDiscoveryBrowser = nil
        nativeDiscoveryDelegate = nil
        discoveredServices.removeAll()
    }
    
    private func handleDiscoveredService(_ service: NetService) {
        logger.info("🎯 ===== DISCOVERED SERVICE =====")
        logger.info("   📱 Name: \(service.name)")
        logger.info("   🔧 Type: \(service.type)")
        logger.info("   🌐 Domain: \(service.domain)")
        
        // Ignore our own service
        if service.name == deviceName {
            logger.info("🚫 Ignoring our own service")
            return
        }
        
        // Store the service
        discoveredServices[service.name] = service
        
        // Resolve the service to get details
        service.delegate = nativeDiscoveryDelegate
        service.resolve(withTimeout: 10.0)
    }
    
    func handleResolvedService(_ service: NetService) {
        logger.info("✅ ===== RESOLVED SERVICE =====")
        logger.info("   📱 Name: \(service.name)")
        logger.info("   🏠 Host: \(service.hostName ?? "Unknown")")
        logger.info("   🔌 Port: \(service.port)")
        
        // Parse TXT record
        let txtData = parseTXTRecord(service.txtRecordData())
        logger.info("   📝 TXT Data: \(txtData)")
        
        guard let deviceIdFromTxt = txtData["device_id"] else {
            logger.warning("⚠️ No device_id in TXT record, using service name")
            return
        }
        
        // Don't add our own device
        if deviceIdFromTxt == deviceId {
            logger.info("🚫 Ignoring our own device by ID")
            return
        }
        
        guard let hostName = service.hostName else {
            logger.warning("⚠️ No hostname resolved")
            return
        }
        
        // Extract IP from hostname (remove .local suffix)
        let cleanHostName = hostName.replacingOccurrences(of: ".local.", with: "")
        
        // Create peer device
        let peerDevice = PeerDevice(
            id: deviceIdFromTxt,
            name: service.name,
            model: txtData["platform"] ?? "Unknown Device",
            deviceType: deviceTypeFromName(service.name),
            ipAddress: cleanHostName,
            port: service.port,
            connectionStatus: .discovered,
            isConnected: false,
            isTrusted: false,
            lastSeen: Date(),
            syncCount: 0
        )
        
        // Add to discovered peers
        if !self.discoveredPeers.contains(where: { $0.id == deviceIdFromTxt }) {
            self.discoveredPeers.append(peerDevice)
            logger.info("📱 Added peer to discoveredPeers: \(service.name)")
        }
        
        // AUTO-CONNECT for testing
        Task {
            await autoConnectToPeer(peerDevice)
        }
        
        logger.info("🎉 Successfully processed discovered service: \(service.name)")
        logger.info("==============================")
    }
    
    private func deviceTypeFromName(_ name: String) -> DeviceType {
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("mac") {
            return .mac
        } else if lowercaseName.contains("win") {
            return .windows
        } else if lowercaseName.contains("iphone") {
            return .iPhone
        } else if lowercaseName.contains("ipad") {
            return .iPad
        } else {
            return .unknown
        }
    }
    
    private func autoConnectToPeer(_ peer: PeerDevice) async {
        logger.info("🤝 AUTO-CONNECTING to peer: \(peer.name)")
        
        // Add to trusted devices
        var trustedPeer = peer
        trustedPeer.connectionStatus = .connected
        trustedPeer.isConnected = true
        trustedPeer.isTrusted = true
        
        if !self.trustedDevices.contains(where: { $0.id == peer.id }) {
            self.trustedDevices.append(trustedPeer)
        }
        
        if !self.connectedPeers.contains(where: { $0.id == peer.id }) {
            self.connectedPeers.append(trustedPeer)
        }
        
        // Remove from discovered
        self.discoveredPeers.removeAll { $0.id == peer.id }
        
        logger.info("✅ Auto-connected to peer: \(peer.name)")
    }
    
    private func parseTXTRecord(_ data: Data?) -> [String: String] {
        guard let data = data else { return [:] }
        
        let txtDict = NetService.dictionary(fromTXTRecord: data)
        var result: [String: String] = [:]
        
        for (key, value) in txtDict {
            if let stringValue = String(data: value, encoding: .utf8) {
                result[key] = stringValue
            }
        }
        
        return result
    }
    
    // MARK: - Network Validation
    private func validateNetworkForDiscovery() -> Bool {
        guard let currentIP = getLocalIPAddress() else {
            logger.warning("⚠️ No local IP address available")
            return false
        }
        
        let isValidPrivateIP = currentIP.hasPrefix("192.168.") ||
                              (currentIP.hasPrefix("10.") && !currentIP.hasPrefix("10.18.")) ||
                              currentIP.hasPrefix("172.1") ||
                              currentIP.hasPrefix("172.2") ||
                              currentIP.hasPrefix("172.3")
        
        let likelyCellular = currentIP.hasPrefix("10.18.") ||
                           currentIP.hasPrefix("10.19.") ||
                           currentIP.contains("pdp")
        
        logger.info("🌐 Network validation:")
        logger.info("   - Current IP: \(currentIP)")
        logger.info("   - Valid private network: \(isValidPrivateIP)")
        logger.info("   - Likely cellular: \(likelyCellular)")
        
        if likelyCellular {
            logger.warning("⚠️ Device appears to be on cellular data!")
            self.statusDescription = "Please connect to WiFi for device discovery"
            return false
        }
        
        return isValidPrivateIP
    }
    
    // MARK: - Enhanced Network Interface Detection
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            var foundInterfaces: [(String, String)] = []
            
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    
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
                    
                    let ipAddress = String(cString: hostname)
                    foundInterfaces.append((name, ipAddress))
                }
            }
            freeifaddrs(ifaddr)
            
            // Priority order: prefer WiFi interfaces
            let preferredInterfaces = ["en0", "en1", "wlan0"]
            for preferred in preferredInterfaces {
                if let found = foundInterfaces.first(where: { $0.0 == preferred }) {
                    let ip = found.1
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") && !ip.hasPrefix("fe80") {
                        return ip
                    }
                }
            }
            
            // Fallback: any non-loopback, non-cellular interface
            for (name, ip) in foundInterfaces {
                if !ip.hasPrefix("127.") &&
                   !ip.hasPrefix("169.254.") &&
                   !name.contains("pdp") &&
                   !name.contains("cellular") {
                    return ip
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Debug Methods
    func debugDiscoveryStatus() {
        Task {
            logger.info("🔍 ===== DISCOVERY STATUS =====")
            logger.info("   - Service Running: \(self.isRunning)")
            logger.info("   - Device Name: \(self.deviceName)")
            logger.info("   - Device ID: \(self.deviceId)")
            logger.info("   - Local IP: \(self.localIPAddress)")
            logger.info("   - Connected Peers: \(self.connectedPeers.count)")
            logger.info("   - Discovered Peers: \(self.discoveredPeers.count)")
            logger.info("   - Trusted Devices: \(self.trustedDevices.count)")
            logger.info("   - Native Services: \(self.discoveredServices.count)")
            logger.info("   - Native Advertiser: \(self.nativeAdvertiser != nil ? "Running" : "Stopped")")
            logger.info("   - Native Discovery: \(self.nativeDiscoveryBrowser != nil ? "Running" : "Stopped")")
            
            for peer in connectedPeers {
                logger.info("     📱 Connected: \(peer.name) (\(peer.ipAddress))")
            }
            
            for peer in discoveredPeers {
                logger.info("     🔍 Discovered: \(peer.name) (\(peer.ipAddress))")
            }
            
            logger.info("=============================")
        }
    }
    
    // MARK: - Enhanced Start Sync
    func startSync() {
        guard isInitialized, let bridge = rustBridge else {
            logger.warning("⚠️ Cannot start sync - service not initialized")
            return
        }
        
        logger.info("🚀 ===== STARTING SYNC SERVICE =====")
        
        // Update network info
        updateNetworkInfo()
        
        // Validate network
        guard validateNetworkForDiscovery() else {
            logger.error("❌ Network validation failed - cannot start discovery")
            return
        }
        
        Task {
            // Start Rust TCP server (but skip Rust mDNS)
            let success = await bridge.start()
            
            await MainActor.run {
                if success {
                    self.isRunning = true
                    self.isDiscovering = true
                    self.statusDescription = "Searching for devices..."
                    self.startDiscoveryTimer()
                    
                    // Start iOS native advertising and discovery
                    self.startNativeAdvertising()
                    self.startNativeDiscovery()
                    
                    // Notify clipboard manager
                    ClipboardManager.shared.syncServiceDidStart()
                    
                    logger.info("✅ Sync service started successfully")
                    
                    // Debug after start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.debugDiscoveryStatus()
                    }
                } else {
                    self.statusDescription = "Failed to start"
                    logger.error("❌ Failed to start sync service")
                }
            }
        }
        
        logger.info("==================================")
    }
    
    func stopSync() {
        guard let bridge = rustBridge else { return }
        
        logger.info("🛑 Stopping sync service...")
        
        // Stop native services
        stopNativeAdvertising()
        stopNativeDiscovery()
        
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
        
        logger.info("🔍 Manually scanning for devices...")
        isDiscovering = true
        
        // Restart native discovery
        startNativeDiscovery()
        
        // Update UI after scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.isDiscovering = false
        }
    }
    
    func connectToPeer(_ peer: PeerDevice) async {
        logger.info("🤝 Connecting to peer: \(peer.name)")
        await autoConnectToPeer(peer)
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
            
            if isRunning {
                Task {
                    await refreshConnections()
                }
            }
        } else {
            localIPAddress = "No connection"
            currentNetworkName = "No network"
            
            connectedPeers.removeAll()
            discoveredPeers.removeAll()
        }
        
        logger.info("🌐 Network status changed: \(isConnected ? "Connected" : "Disconnected")")
    }
    
    private func updateNetworkInfo() {
        localIPAddress = getLocalIPAddress() ?? "Unknown"
        currentNetworkName = getWiFiNetworkName() ?? "Unknown"
    }
    
    private func initializeRustBridge() async throws {
        let deviceName = "\(self.deviceName)-iOS"
        
        logger.info("🔧 Initializing Rust bridge with device name: \(deviceName)")
        
        guard let bridge = await RustBridge(deviceName: deviceName) else {
            throw SyncError.bridgeInitializationFailed
        }
        
        self.rustBridge = bridge
        
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
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
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
        // Restart native discovery periodically
        startNativeDiscovery()
    }
    
    private func updatePeerStatus() async {
        let now = Date()
        
        for i in 0..<connectedPeers.count {
            connectedPeers[i].lastSeen = now
        }
    }
    
    private func getWiFiNetworkName() -> String? {
        return "WiFi Network"
    }
    
    deinit {
        logger.info("🧹 SyncService deinitializing")
        statusUpdateTimer?.invalidate()
        discoveryTimer?.invalidate()
        networkMonitor?.cancel()
        nativeAdvertiser?.stop()
        nativeDiscoveryBrowser?.stop()
    }
}

// MARK: - Native Advertiser Delegate
class NativeAdvertiserDelegate: NSObject, NetServiceDelegate {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "NativeAdvertiser")
    
    func netServiceDidPublish(_ sender: NetService) {
        logger.info("✅ NATIVE ADVERTISING: Successfully published \(sender.name)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        logger.error("❌ NATIVE ADVERTISING: Failed to publish \(sender.name): \(errorDict)")
    }
    
    func netServiceDidStop(_ sender: NetService) {
        logger.info("🛑 NATIVE ADVERTISING: Stopped advertising \(sender.name)")
    }
}

// MARK: - Native Discovery Delegate
class NativeDiscoveryDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "NativeDiscovery")
    private let onServiceDiscovered: (NetService) -> Void
    
    init(onServiceDiscovered: @escaping (NetService) -> Void) {
        self.onServiceDiscovered = onServiceDiscovered
        super.init()
    }
    
    // MARK: - NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logger.info("🎯 NATIVE DISCOVERY: Found service \(service.name)")
        onServiceDiscovered(service)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logger.info("🚫 NATIVE DISCOVERY: Removed service \(service.name)")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        logger.error("❌ NATIVE DISCOVERY: Search error \(errorDict)")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        logger.info("🛑 NATIVE DISCOVERY: Search stopped")
    }
    
    // MARK: - NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("✅ NATIVE DISCOVERY: Resolved \(sender.name)")
        
        // Notify the SyncService about the resolved service
        DispatchQueue.main.async {
            SyncService.shared.handleResolvedService(sender)
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        logger.error("❌ NATIVE DISCOVERY: Failed to resolve \(sender.name): \(errorDict)")
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
