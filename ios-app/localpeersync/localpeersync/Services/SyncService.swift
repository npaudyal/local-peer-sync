//
//  SyncService.swift
//  LocalPeerSync - Background Ready Production (COMPLETE)
//

import Foundation
import Network
import UIKit
import os.log
import BackgroundTasks

@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()
    
    // MARK: - Published Properties
    @Published var isRunning: Bool = false
    @Published var connectedPeers: [PeerDevice] = []
    @Published var discoveredPeers: [PeerDevice] = []
    @Published var statusMessage: String = "Ready"
    @Published var discoveryMethod: String = "Initializing..."
    @Published var backgroundOperationsCount: Int = 0
    
    // MARK: - Private Properties
    private var rustBridge: RustBridge?
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "SyncService")
    
    // Device Info
    private let deviceName = UIDevice.current.name
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let port = 8421
    
    // Background Support
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundSession: URLSession?
    
    // Discovery
    private var discoveryManager: MultiMethodDiscoveryManager?
    private var networkMonitor: NWPathMonitor?
    private var currentNetworkInterface: String = ""
    
    private init() {
        setupNetworkMonitoring()
        setupBackgroundSession()
        setupBackgroundObservers()
        registerBackgroundTasks()
    }
    
    // MARK: - Background Setup
    
    private func setupBackgroundSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.localpeersync.background")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        backgroundSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        logger.info("🌐 Background URL session configured")
    }
    
    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func registerBackgroundTasks() {
        let result = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.localpeersync.sync",
            using: nil
        ) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
        
        if result {
            logger.info("✅ Background task registered successfully")
        } else {
            logger.error("❌ Failed to register background task")
        }
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("📱 App entering background - preparing for background operation")
        startBackgroundTask()
        scheduleBackgroundRefresh()
    }
    
    @objc private func appWillEnterForeground() {
        logger.info("📱 App entering foreground - resuming full operation")
        endBackgroundTask()
    }
    
    private func startBackgroundTask() {
        endBackgroundTask()
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LocalPeerSyncNetwork") { [weak self] in
            self?.logger.warning("⏰ Background network task expiring")
            self?.endBackgroundTask()
        }
        
        if backgroundTask != .invalid {
            logger.info("✅ Background network task started: \(self.backgroundTask.rawValue)")
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            logger.info("🛑 Ending background network task: \(self.backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.localpeersync.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("✅ Background refresh scheduled")
        } catch {
            logger.error("❌ Failed to schedule background refresh: \(error)")
        }
    }
    
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        logger.info("🔄 Handling background sync task")
        
        task.expirationHandler = {
            self.logger.warning("⏰ Background sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            // Perform quick sync check
            await self.performBackgroundSync()
            
            // Schedule next background refresh
            self.scheduleBackgroundRefresh()
            
            task.setTaskCompleted(success: true)
            self.logger.info("✅ Background sync completed")
        }
    }
    
    func performBackgroundSync() async {
        guard isRunning else { return }
        
        logger.info("🔄 Performing background sync check")
        
        // Quick peer health check
        await refreshStatus()
        
        // Increment background operations counter
        backgroundOperationsCount += 1
    }
    
    // MARK: - Public Methods
    
    func startSync() async {
        logger.info("🚀 Starting LocalPeerSync with background support...")
        
        do {
            try await initializeRustBridge()
            try await startTcpServer()
            try await startRobustDiscovery()
            
            isRunning = true
            statusMessage = "Active - \(connectedPeers.count) devices"
            
            logger.info("✅ All services started successfully with background support")
            
        } catch {
            logger.error("❌ Failed to start services: \(error)")
            statusMessage = "Failed to start: \(error.localizedDescription)"
            isRunning = false
        }
    }
    
    func stopSync() {
        logger.info("🛑 Stopping LocalPeerSync services...")
        
        Task {
            if let bridge = rustBridge {
                let _ = await bridge.stop()
            }
            
            stopRobustDiscovery()
            endBackgroundTask()
            
            await MainActor.run {
                isRunning = false
                connectedPeers.removeAll()
                discoveredPeers.removeAll()
                statusMessage = "Stopped"
                discoveryMethod = "Stopped"
            }
            
            logger.info("✅ All services stopped")
        }
    }
    
    func syncClipboard(_ content: String) async -> Bool {
        guard isRunning, let bridge = rustBridge else {
            logger.warning("⚠️ Cannot sync - service not running")
            return false
        }
        
        logger.info("📋 Syncing clipboard with background support: \(content.prefix(50))...")
        
        // Start background task for sync operation
        startBackgroundTask()
        
        let success = await bridge.notifyClipboardChange(content: content, type: .text)
        
        if success {
            logger.info("✅ Clipboard sync successful")
            if UIApplication.shared.applicationState != .active {
                backgroundOperationsCount += 1
            }
        } else {
            logger.error("❌ Clipboard sync failed")
        }
        
        // Don't end background task immediately - let it finish naturally
        
        return success
    }
    
    func scanForDevices() async {
        logger.info("🔍 Starting comprehensive device scan...")
        
        connectedPeers.removeAll()
        discoveredPeers.removeAll()
        
        await discoveryManager?.performFullScan()
        
        logger.info("📱 Scan completed - found \(self.connectedPeers.count) devices")
    }
    
    func refreshStatus() async {
        guard let bridge = rustBridge else { return }
        
        let isRustRunning = await bridge.isRunning()
        let peerCount = await bridge.getPeerCount()
        
        await MainActor.run {
            if isRustRunning {
                statusMessage = "Active - \(peerCount) peers"
            } else {
                statusMessage = "TCP server not running"
            }
        }
    }
    
    func getDebugInfo() async -> String {
        var info = ["=== LocalPeerSync Debug Info (Background Ready) ==="]
        
        info.append("App Status:")
        info.append("  - Running: \(isRunning)")
        info.append("  - Status: \(statusMessage)")
        info.append("  - Discovery Method: \(discoveryMethod)")
        info.append("  - Device: \(deviceName)")
        info.append("  - Network Interface: \(currentNetworkInterface)")
        info.append("  - Background Operations: \(backgroundOperationsCount)")
        info.append("  - App State: \(UIApplication.shared.applicationState.description)")
        
        if let bridge = rustBridge {
            let isRustRunning = await bridge.isRunning()
            let peerCount = await bridge.getPeerCount()
            let trustedCount = await bridge.getTrustedPeerCount()
            
            info.append("Rust Status:")
            info.append("  - TCP Server: \(isRustRunning ? "Running" : "Stopped")")
            info.append("  - Total Peers: \(peerCount)")
            info.append("  - Trusted Peers: \(trustedCount)")
        }
        
        info.append("Discovery Status:")
        info.append("  - Connected Peers: \(connectedPeers.count)")
        info.append("  - Discovered Peers: \(discoveredPeers.count)")
        
        if let manager = discoveryManager {
            info.append("  - mDNS Status: \(manager.mdnsStatus)")
            info.append("  - Scanner Status: \(manager.scannerStatus)")
        }
        
        for peer in connectedPeers {
            info.append("  - Connected: \(peer.name) (\(peer.ipAddress))")
        }
        
        return info.joined(separator: "\n")
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                if path.status == .satisfied {
                    self?.currentNetworkInterface = self?.getNetworkInterfaceName(path) ?? "Unknown"
                    self?.logger.info("🌐 Network connected via: \(self?.currentNetworkInterface ?? "Unknown")")
                } else {
                    self?.logger.warning("🌐 Network disconnected")
                    self?.connectedPeers.removeAll()
                    self?.currentNetworkInterface = "Disconnected"
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    private func getNetworkInterfaceName(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else {
            return "Other"
        }
    }
    
    private func initializeRustBridge() async throws {
        let fullDeviceName = "\(deviceName)-iOS"
        
        guard let bridge = await RustBridge(deviceName: fullDeviceName) else {
            throw SyncError.bridgeInitializationFailed
        }
        
        self.rustBridge = bridge
        logger.info("✅ Rust bridge initialized with background support")
    }
    
    private func startTcpServer() async throws {
        guard let bridge = rustBridge else {
            throw SyncError.bridgeNotAvailable
        }
        
        let success = await bridge.start()
        
        if !success {
            throw SyncError.tcpServerFailed
        }
        
        logger.info("✅ TCP server started on port \(self.port) with background support")
    }
    
    private func startRobustDiscovery() async throws {
        logger.info("🔍 Starting robust multi-method discovery with background support...")
        
        discoveryManager = MultiMethodDiscoveryManager(
            deviceName: deviceName,
            deviceId: deviceId,
            port: port,
            onPeerDiscovered: { [weak self] peer in
                Task { @MainActor in
                    self?.handleDiscoveredPeer(peer)
                }
            },
            onDiscoveryStatusChanged: { [weak self] status in
                Task { @MainActor in
                    self?.discoveryMethod = status
                }
            }
        )
        
        try await discoveryManager?.start()
        
        logger.info("✅ Robust discovery started with background support")
    }
    
    private func stopRobustDiscovery() {
        discoveryManager?.stop()
        discoveryManager = nil
        logger.info("🛑 Robust discovery stopped")
    }
    
    private func handleDiscoveredPeer(_ peer: PeerDevice) {
        logger.info("🎯 Discovered peer: \(peer.name) at \(peer.ipAddress)")
        
        if !connectedPeers.contains(where: { $0.id == peer.id }) {
            connectedPeers.append(peer)
            statusMessage = "Active - \(connectedPeers.count) devices"
            
            Task {
                await bridgeToRust(peer)
            }
            
            logger.info("✅ Added peer: \(peer.name)")
        }
    }
    
    private func bridgeToRust(_ peer: PeerDevice) async {
        guard let bridge = rustBridge else { return }
        
        let success = await bridge.addDiscoveredPeer(
            deviceId: peer.id,
            deviceName: peer.name,
            ipAddress: peer.ipAddress,
            port: peer.port
        )
        
        if success {
            logger.info("✅ Bridged peer to Rust: \(peer.name)")
        } else {
            logger.error("❌ Failed to bridge peer to Rust: \(peer.name)")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // FIXED: Use nonisolated cleanup
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        
        logger.info("🧹 SyncService deinitialized")
    }
}

// MARK: - Multi-Method Discovery Manager

class MultiMethodDiscoveryManager {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "Discovery")
    
    // Configuration
    private let deviceName: String
    private let deviceId: String
    private let port: Int
    
    // Callbacks
    private let onPeerDiscovered: (PeerDevice) -> Void
    private let onDiscoveryStatusChanged: (String) -> Void
    
    // Discovery methods
    private var mdnsDiscovery: MDNSDiscovery?
    private var networkScanner: NetworkScanner?
    private var advertisingService: AdvertisingService?
    
    // Status tracking
    var mdnsStatus: String = "Stopped"
    var scannerStatus: String = "Stopped"
    
    init(
        deviceName: String,
        deviceId: String,
        port: Int,
        onPeerDiscovered: @escaping (PeerDevice) -> Void,
        onDiscoveryStatusChanged: @escaping (String) -> Void
    ) {
        self.deviceName = deviceName
        self.deviceId = deviceId
        self.port = port
        self.onPeerDiscovered = onPeerDiscovered
        self.onDiscoveryStatusChanged = onDiscoveryStatusChanged
    }
    
    func start() async throws {
        logger.info("🚀 Starting multi-method discovery with background support...")
        
        // Start advertising first
        advertisingService = AdvertisingService(
            deviceName: deviceName,
            deviceId: deviceId,
            port: port
        )
        try advertisingService?.start()
        
        // Start mDNS discovery (primary method)
        mdnsDiscovery = MDNSDiscovery(
            deviceName: deviceName,
            onPeerFound: { [weak self] peer in
                self?.onPeerDiscovered(peer)
            },
            onStatusChanged: { [weak self] status in
                self?.mdnsStatus = status
                self?.updateStatus()
            }
        )
        
        mdnsDiscovery?.start()
        
        // Start network scanner (fallback method) with background awareness
        networkScanner = NetworkScanner(
            targetPort: port,
            onPeerFound: { [weak self] peer in
                self?.onPeerDiscovered(peer)
            },
            onStatusChanged: { [weak self] status in
                self?.scannerStatus = status
                self?.updateStatus()
            }
        )
        
        // Delay network scanner to give mDNS time to work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.networkScanner?.start()
        }
        
        logger.info("✅ Multi-method discovery started")
    }
    
    func stop() {
        mdnsDiscovery?.stop()
        networkScanner?.stop()
        advertisingService?.stop()
        
        mdnsStatus = "Stopped"
        scannerStatus = "Stopped"
        updateStatus()
        
        logger.info("🛑 Multi-method discovery stopped")
    }
    
    func performFullScan() async {
        logger.info("🔍 Performing full network scan...")
        
        // Restart mDNS
        mdnsDiscovery?.restart()
        
        // Perform immediate network scan
        await networkScanner?.performScan()
        
        logger.info("✅ Full scan completed")
    }
    
    private func updateStatus() {
        let status = "mDNS: \(mdnsStatus) | Scanner: \(scannerStatus)"
        onDiscoveryStatusChanged(status)
    }
}

// MARK: - mDNS Discovery

class MDNSDiscovery: NSObject {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "mDNS")
    
    private let deviceName: String
    private let onPeerFound: (PeerDevice) -> Void
    private let onStatusChanged: (String) -> Void
    
    private var browser: NetServiceBrowser?
    private var foundServices: Set<String> = []
    
    init(
        deviceName: String,
        onPeerFound: @escaping (PeerDevice) -> Void,
        onStatusChanged: @escaping (String) -> Void
    ) {
        self.deviceName = deviceName
        self.onPeerFound = onPeerFound
        self.onStatusChanged = onStatusChanged
        super.init()
    }
    
    func start() {
        logger.info("🔍 Starting mDNS discovery...")
        
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_localpeersync._tcp.", inDomain: "local.")
        
        onStatusChanged("Starting...")
    }
    
    func stop() {
        browser?.stop()
        browser = nil
        foundServices.removeAll()
        onStatusChanged("Stopped")
        
        logger.info("🛑 mDNS discovery stopped")
    }
    
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.start()
        }
    }
}

extension MDNSDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name != deviceName else { return }
        
        logger.info("🔍 Found mDNS service: \(service.name)")
        foundServices.insert(service.name)
        onStatusChanged("Found \(foundServices.count) services")
        
        // Don't try to resolve - create peer with basic info
        let peer = PeerDevice(
            id: service.name,
            name: service.name,
            model: "Unknown",
            deviceType: .unknown,
            ipAddress: "0.0.0.0", // Will be resolved by network scanner
            port: service.port,
            connectionStatus: .discovered,
            isConnected: false,
            isTrusted: true
        )
        
        onPeerFound(peer)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logger.info("🚫 mDNS service removed: \(service.name)")
        foundServices.remove(service.name)
        onStatusChanged("Active - \(foundServices.count) services")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        onStatusChanged("Search stopped")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        logger.error("❌ mDNS search error: \(errorDict)")
        onStatusChanged("Error: \(errorDict)")
    }
}

// MARK: - Background-Aware Network Scanner (FIXED)

class NetworkScanner {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "Scanner")
    
    private let targetPort: Int
    private let onPeerFound: (PeerDevice) -> Void
    private let onStatusChanged: (String) -> Void
    
    private var isScanning = false
    private var scanTimer: Timer?
    private let maxConcurrentConnections = 5 // FIXED: Limit for iOS
    
    init(
        targetPort: Int,
        onPeerFound: @escaping (PeerDevice) -> Void,
        onStatusChanged: @escaping (String) -> Void
    ) {
        self.targetPort = targetPort
        self.onPeerFound = onPeerFound
        self.onStatusChanged = onStatusChanged
    }
    
    func start() {
        guard !isScanning else { return }
        
        logger.info("🔍 Starting background-aware network scanner...")
        isScanning = true
        onStatusChanged("Starting scan...")
        
        Task {
            await performScan()
        }
        
        // Background-aware scanning interval
        let interval: TimeInterval = UIApplication.shared.applicationState == .active ? 30.0 : 60.0
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task {
                await self.performScan()
            }
        }
    }
    
    func stop() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        onStatusChanged("Stopped")
        
        logger.info("🛑 Network scanner stopped")
    }
    
    func performScan() async {
        guard isScanning else { return }
        
        logger.info("🔍 Performing background-aware network scan...")
        onStatusChanged("Scanning...")
        
        guard let localIP = getLocalIPAddress(),
              let networkRange = getNetworkRange(from: localIP) else {
            logger.warning("⚠️ Could not determine network range")
            onStatusChanged("No network")
            return
        }
        
        logger.info("🔍 Scanning network range: \(networkRange)")
        
        // FIXED: Scan in small batches for iOS background compatibility
        let batchSize = maxConcurrentConnections
        
        for batchStart in stride(from: 1, through: 254, by: batchSize) {
            guard isScanning else { break }
            
            let batchEnd = min(batchStart + batchSize - 1, 254)
            
            await withTaskGroup(of: Void.self) { group in
                for i in batchStart...batchEnd {
                    let targetIP = "\(networkRange).\(i)"
                    
                    group.addTask {
                        await self.testConnection(to: targetIP)
                    }
                }
            }
            
            // Longer delay for background scanning
            let delay = UIApplication.shared.applicationState == .active ? 50_000_000 : 200_000_000 // 0.05s or 0.2s
            try? await Task.sleep(nanoseconds: UInt64(delay))
        }
        
        onStatusChanged("Scan complete")
        logger.info("✅ Network scan completed")
    }
    
    private func testConnection(to ipAddress: String) async {
        do {
            let connection = NWConnection(
                host: NWEndpoint.Host(ipAddress),
                port: NWEndpoint.Port(integerLiteral: UInt16(targetPort)),
                using: .tcp
            )
            
            connection.start(queue: DispatchQueue.global())
            
            // Shorter timeout for background operation
            let timeout = UIApplication.shared.applicationState == .active ? 2.0 : 1.0
            let result = await withTimeout(seconds: timeout) {
                await withCheckedContinuation { continuation in
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            continuation.resume(returning: true)
                        case .failed:
                            continuation.resume(returning: false)
                        default:
                            break
                        }
                    }
                }
            }
            
            connection.cancel()
            
            if result == true {
                logger.info("✅ Found peer at: \(ipAddress)")
                
                let peer = PeerDevice(
                    id: ipAddress,
                    name: "Device-\(ipAddress.suffix(3))",
                    model: "Network Device",
                    deviceType: .unknown,
                    ipAddress: ipAddress,
                    port: targetPort,
                    connectionStatus: .connected,
                    isConnected: true,
                    isTrusted: true
                )
                
                onPeerFound(peer)
            }
            
        } catch {
            // Connection failed - ignore
        }
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
    
    private func getNetworkRange(from ipAddress: String) -> String? {
        let components = ipAddress.components(separatedBy: ".")
        guard components.count == 4 else { return nil }
        
        return "\(components[0]).\(components[1]).\(components[2])"
    }
}

// MARK: - Advertising Service

class AdvertisingService: NSObject {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "Advertising")
    
    private let deviceName: String
    private let deviceId: String
    private let port: Int
    
    private var netService: NetService?
    
    init(deviceName: String, deviceId: String, port: Int) {
        self.deviceName = deviceName
        self.deviceId = deviceId
        self.port = port
        super.init()
    }
    
    func start() throws {
        netService = NetService(
            domain: "local.",
            type: "_localpeersync._tcp.",
            name: deviceName,
            port: Int32(port)
        )
        
        netService?.delegate = self
        
        // Set TXT record
        let txtData = createTXTRecord()
        netService?.setTXTRecord(txtData)
        
        netService?.publish()
        logger.info("📡 Started advertising: \(self.deviceName)")
    }
    
    func stop() {
        netService?.stop()
        netService = nil
        logger.info("🛑 Stopped advertising")
    }
    
    private func createTXTRecord() -> Data {
        let txtDict: [String: Data] = [
            "device_id": deviceId.data(using: .utf8) ?? Data(),
            "version": "1.0.0".data(using: .utf8) ?? Data(),
            "encryption": "true".data(using: .utf8) ?? Data(),
            "port": "\(port)".data(using: .utf8) ?? Data()
        ]
        return NetService.data(fromTXTRecord: txtDict)
    }
}

extension AdvertisingService: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        logger.info("✅ Successfully published: \(sender.name)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        logger.error("❌ Failed to publish: \(errorDict)")
    }
}

// MARK: - Utility Functions

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    return await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }
        
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        
        let result = await group.next()
        group.cancelAll()
        return result ?? nil
    }
}

// MARK: - Supporting Types

enum SyncError: LocalizedError {
    case bridgeInitializationFailed
    case bridgeNotAvailable
    case tcpServerFailed
    
    var errorDescription: String? {
        switch self {
        case .bridgeInitializationFailed:
            return "Failed to initialize Rust bridge"
        case .bridgeNotAvailable:
            return "Rust bridge not available"
        case .tcpServerFailed:
            return "Failed to start TCP server"
        }
    }
}

// MARK: - Supporting Extensions

extension UIApplication.State {
    var description: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .background: return "Background"
        @unknown default: return "Unknown"
        }
    }
}
