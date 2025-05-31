//
//  PeerDevice.swift
//  LocalPeerSync
//
//  Comprehensive peer device model
//

import Foundation
import Network

// MARK: - Peer Device
struct PeerDevice: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var model: String
    var deviceType: DeviceType
    var ipAddress: String
    var port: Int
    var connectionStatus: ConnectionStatus
    var isConnected: Bool
    var isTrusted: Bool
    var lastSeen: Date?
    var firstDiscovered: Date
    var syncCount: Int
    var bytesTransferred: Int64
    var capabilities: [String]
    var version: String
    var metadata: PeerMetadata?
    
    // MARK: - Initialization
    init(
        id: String,
        name: String,
        model: String,
        deviceType: DeviceType,
        ipAddress: String,
        port: Int = 8421,
        connectionStatus: ConnectionStatus = .discovered,
        isConnected: Bool = false,
        isTrusted: Bool = false,
        lastSeen: Date? = nil,
        syncCount: Int = 0,
        bytesTransferred: Int64 = 0,
        capabilities: [String] = [],
        version: String = "1.0.0"
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.deviceType = deviceType
        self.ipAddress = ipAddress
        self.port = port
        self.connectionStatus = connectionStatus
        self.isConnected = isConnected
        self.isTrusted = isTrusted
        self.lastSeen = lastSeen ?? Date()
        self.firstDiscovered = Date()
        self.syncCount = syncCount
        self.bytesTransferred = bytesTransferred
        self.capabilities = capabilities
        self.version = version
        self.metadata = PeerMetadata.generate(for: self)
    }
    
    // MARK: - Computed Properties
    var displayName: String {
        return name.isEmpty ? model : name
    }
    
    var statusDescription: String {
        switch connectionStatus {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return isOnline ? "Available" : "Offline"
        case .discovered:
            return "Discovered"
        case .error:
            return "Connection Error"
        }
    }
    
    var isOnline: Bool {
        guard let lastSeen = lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < 300 // 5 minutes
    }
    
    var connectionQuality: ConnectionQuality {
        guard let lastSeen = lastSeen else { return .poor }
        
        let timeSinceLastSeen = Date().timeIntervalSince(lastSeen)
        
        if timeSinceLastSeen < 30 {
            return .excellent
        } else if timeSinceLastSeen < 120 {
            return .good
        } else if timeSinceLastSeen < 300 {
            return .fair
        } else {
            return .poor
        }
    }
    
    var formattedBytesTransferred: String {
        return ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .file)
    }
    
    var uptime: TimeInterval {
        return Date().timeIntervalSince(firstDiscovered)
    }
    
    var formattedUptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "Unknown"
    }
    
    // MARK: - Device Capabilities
    func hasCapability(_ capability: String) -> Bool {
        return capabilities.contains(capability)
    }
    
    func supportsImages() -> Bool {
        return hasCapability("images") || hasCapability("image_sync")
    }
    
    func supportsFiles() -> Bool {
        return hasCapability("files") || hasCapability("file_sync")
    }
    
    func supportsRichText() -> Bool {
        return hasCapability("rich_text") || hasCapability("html")
    }
    
    func supportsCompression() -> Bool {
        return hasCapability("compression") || hasCapability("lz4")
    }
    
    func supportsEncryption() -> Bool {
        return hasCapability("encryption") || hasCapability("aes256")
    }
    
    // MARK: - Connection Management
    mutating func updateConnectionStatus(_ status: ConnectionStatus) {
        connectionStatus = status
        isConnected = (status == .connected)
        
        if isConnected {
            lastSeen = Date()
        }
    }
    
    mutating func updateLastSeen() {
        lastSeen = Date()
    }
    
    mutating func incrementSyncCount() {
        syncCount += 1
    }
    
    mutating func addBytesTransferred(_ bytes: Int64) {
        bytesTransferred += bytes
    }
    
    mutating func setTrusted(_ trusted: Bool) {
        isTrusted = trusted
    }
    
    // MARK: - Network Information
    func socketAddress() -> SocketAddress? {
        guard let ipv4Address = IPv4Address(ipAddress) else { return nil }
        return SocketAddress(ipv4Address: ipv4Address, port: NWEndpoint.Port(integerLiteral: UInt16(port)))
    }
    
    func endpoint() -> NWEndpoint {
        return NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
    }
    
    // MARK: - Validation
    func isValid() -> Bool {
        return !id.isEmpty &&
               !name.isEmpty &&
               !ipAddress.isEmpty &&
               port > 0 &&
               port < 65536
    }
    
    func canConnect() -> Bool {
        return isValid() && (connectionStatus == .discovered || connectionStatus == .disconnected)
    }
    
    // MARK: - Export/Import
    func exportData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "name": name,
            "model": model,
            "deviceType": deviceType.rawValue,
            "ipAddress": ipAddress,
            "port": port,
            "connectionStatus": connectionStatus.rawValue,
            "isConnected": isConnected,
            "isTrusted": isTrusted,
            "firstDiscovered": firstDiscovered.ISO8601String(),
            "syncCount": syncCount,
            "bytesTransferred": bytesTransferred,
            "capabilities": capabilities,
            "version": version
        ]
        
        if let lastSeen = lastSeen {
            data["lastSeen"] = lastSeen.ISO8601String()
        }
        
        if let metadata = metadata {
            data["metadata"] = metadata.exportData()
        }
        
        return data
    }
    
    static func importData(_ data: [String: Any]) -> PeerDevice? {
        guard let id = data["id"] as? String,
              let name = data["name"] as? String,
              let model = data["model"] as? String,
              let deviceTypeRaw = data["deviceType"] as? String,
              let deviceType = DeviceType(rawValue: deviceTypeRaw),
              let ipAddress = data["ipAddress"] as? String,
              let port = data["port"] as? Int,
              let connectionStatusRaw = data["connectionStatus"] as? String,
              let connectionStatus = ConnectionStatus(rawValue: connectionStatusRaw),
              let isConnected = data["isConnected"] as? Bool,
              let isTrusted = data["isTrusted"] as? Bool,
              let firstDiscoveredString = data["firstDiscovered"] as? String,
              let firstDiscovered = Date.fromISO8601String(firstDiscoveredString),
              let syncCount = data["syncCount"] as? Int,
              let bytesTransferred = data["bytesTransferred"] as? Int64,
              let capabilities = data["capabilities"] as? [String],
              let version = data["version"] as? String else {
            return nil
        }
        
        var lastSeen: Date?
        if let lastSeenString = data["lastSeen"] as? String {
            lastSeen = Date.fromISO8601String(lastSeenString)
        }
        
        var metadata: PeerMetadata?
        if let metadataData = data["metadata"] as? [String: Any] {
            metadata = PeerMetadata.importData(metadataData)
        }
        
        var peer = PeerDevice(
            id: id,
            name: name,
            model: model,
            deviceType: deviceType,
            ipAddress: ipAddress,
            port: port,
            connectionStatus: connectionStatus,
            isConnected: isConnected,
            isTrusted: isTrusted,
            lastSeen: lastSeen,
            syncCount: syncCount,
            bytesTransferred: bytesTransferred,
            capabilities: capabilities,
            version: version
        )
        
        peer.firstDiscovered = firstDiscovered
        peer.metadata = metadata
        
        return peer
    }
}

// MARK: - Device Type
enum DeviceType: String, CaseIterable, Codable {
    case iPhone
    case iPad
    case mac
    case windows
    case android
    case linux
    case unknown
    
    var displayName: String {
        switch self {
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .mac: return "Mac"
        case .windows: return "Windows PC"
        case .android: return "Android"
        case .linux: return "Linux"
        case .unknown: return "Unknown Device"
        }
    }
    
    var iconName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "laptopcomputer"
        case .windows: return "pc"
        case .android: return "smartphone"
        case .linux: return "desktopcomputer"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var platform: String {
        switch self {
        case .iPhone, .iPad: return "iOS"
        case .mac: return "macOS"
        case .windows: return "Windows"
        case .android: return "Android"
        case .linux: return "Linux"
        case .unknown: return "Unknown"
        }
    }
    
    static func detect(from userAgent: String) -> DeviceType {
        let lowercasedAgent = userAgent.lowercased()
        
        if lowercasedAgent.contains("iphone") {
            return .iPhone
        } else if lowercasedAgent.contains("ipad") {
            return .iPad
        } else if lowercasedAgent.contains("mac") {
            return .mac
        } else if lowercasedAgent.contains("windows") {
            return .windows
        } else if lowercasedAgent.contains("android") {
            return .android
        } else if lowercasedAgent.contains("linux") {
            return .linux
        } else {
            return .unknown
        }
    }
}

// MARK: - Connection Status
enum ConnectionStatus: String, CaseIterable, Codable {
    case discovered
    case connecting
    case connected
    case disconnected
    case error
    
    var displayName: String {
        switch self {
        case .discovered: return "Discovered"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
    
    var color: String {
        switch self {
        case .discovered: return "blue"
        case .connecting: return "orange"
        case .connected: return "green"
        case .disconnected: return "gray"
        case .error: return "red"
        }
    }
}

// MARK: - Connection Quality
enum ConnectionQuality: String, CaseIterable {
    case excellent
    case good
    case fair
    case poor
    
    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "yellow"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
    
    var signalBars: Int {
        switch self {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        }
    }
}

// MARK: - Peer Metadata
struct PeerMetadata: Codable, Hashable {
    let osVersion: String?
    let appVersion: String
    let deviceModel: String?
    let screenResolution: String?
    let timeZone: String
    let locale: String
    let createdAt: Date
    let updatedAt: Date
    
    static func generate(for peer: PeerDevice) -> PeerMetadata {
        return PeerMetadata(
            osVersion: extractOSVersion(from: peer.model),
            appVersion: peer.version,
            deviceModel: peer.model,
            screenResolution: nil,
            timeZone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private static func extractOSVersion(from model: String) -> String? {
        // Extract OS version from device model string if available
        return nil // Implementation would depend on the format of model string
    }
    
    func exportData() -> [String: Any] {
        var data: [String: Any] = [
            "appVersion": appVersion,
            "timeZone": timeZone,
            "locale": locale,
            "createdAt": createdAt.ISO8601String(),
            "updatedAt": updatedAt.ISO8601String()
        ]
        
        if let osVersion = osVersion {
            data["osVersion"] = osVersion
        }
        
        if let deviceModel = deviceModel {
            data["deviceModel"] = deviceModel
        }
        
        if let screenResolution = screenResolution {
            data["screenResolution"] = screenResolution
        }
        
        return data
    }
    
    static func importData(_ data: [String: Any]) -> PeerMetadata? {
        guard let appVersion = data["appVersion"] as? String,
              let timeZone = data["timeZone"] as? String,
              let locale = data["locale"] as? String,
              let createdAtString = data["createdAt"] as? String,
              let createdAt = Date.fromISO8601String(createdAtString),
              let updatedAtString = data["updatedAt"] as? String,
              let updatedAt = Date.fromISO8601String(updatedAtString) else {
            return nil
        }
        
        return PeerMetadata(
            osVersion: data["osVersion"] as? String,
            appVersion: appVersion,
            deviceModel: data["deviceModel"] as? String,
            screenResolution: data["screenResolution"] as? String,
            timeZone: timeZone,
            locale: locale,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Socket Address Helper
struct SocketAddress {
    let ipv4Address: IPv4Address
    let port: NWEndpoint.Port
    
    var string: String {
        return "\(ipv4Address):\(port)"
    }
}
