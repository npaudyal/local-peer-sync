//
//  PeerDevice.swift
//  LocalPeerSync - Simplified Version
//

import Foundation

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
        lastSeen: Date? = nil
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
    }
    
    var displayName: String {
        return name.isEmpty ? model : name
    }
    
    var statusDescription: String {
        switch connectionStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Offline"
        case .discovered: return "Discovered"
        case .error: return "Error"
        }
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
        case .windows: return "Windows"
        case .android: return "Android"
        case .linux: return "Linux"
        case .unknown: return "Unknown"
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
}
