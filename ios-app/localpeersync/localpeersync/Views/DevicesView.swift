//
//  DevicesView.swift
//  LocalPeerSync
//
//  Device discovery and management
//

import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var showingAddDevice = false
    @State private var isScanning = false
    
    var body: some View {
        NavigationView {
            List {
                // Current Device Section
                Section("This Device") {
                    CurrentDeviceRow()
                }
                
                // Connected Devices Section
                Section("Connected Devices") {
                    if syncService.connectedPeers.isEmpty {
                        EmptyDevicesView()
                    } else {
                        ForEach(syncService.connectedPeers, id: \.id) { peer in
                            DeviceRow(peer: peer)
                        }
                    }
                }
                
                // Discovered Devices Section
                if !syncService.discoveredPeers.isEmpty {
                    Section("Discovered Devices") {
                        ForEach(syncService.discoveredPeers, id: \.id) { peer in
                            DiscoveredDeviceRow(peer: peer)
                        }
                    }
                }
                
                // Network Info Section - Fixed the call
                Section("Network Information") {
                    NetworkInfoDisplay()
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        scanForDevices()
                    }) {
                        Image(systemName: isScanning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                            .rotationEffect(.degrees(isScanning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)
                    }
                    .disabled(isScanning)
                }
            }
            .refreshable {
                await refreshDevices()
            }
        }
    }
    
    // MARK: - Actions
    private func scanForDevices() {
        HapticFeedback.medium()
        isScanning = true
        
        Task {
            await syncService.scanForDevices()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isScanning = false
            }
        }
    }
    
    private func refreshDevices() async {
        await syncService.refreshPeers()
    }
}

// MARK: - Current Device Row
struct CurrentDeviceRow: View {
    @EnvironmentObject var syncService: SyncService
    
    var body: some View {
        HStack(spacing: 16) {
            DeviceIcon(deviceType: .iPhone, isConnected: true, isCurrentDevice: true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(syncService.deviceName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("This Device")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Label("Port: \(syncService.port)", systemImage: "network")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Circle()
                    .fill(syncService.isRunning ? .green : .red)
                    .frame(width: 12, height: 12)
                
                Text(syncService.isRunning ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let peer: PeerDevice
    @EnvironmentObject var syncService: SyncService
    @State private var showingDeviceDetails = false
    
    var body: some View {
        Button(action: {
            showingDeviceDetails = true
        }) {
            HStack(spacing: 16) {
                DeviceIcon(deviceType: peer.deviceType, isConnected: peer.isConnected, isCurrentDevice: false)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(peer.model)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Label(peer.ipAddress, systemImage: "wifi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let lastSeen = peer.lastSeen {
                            Label(lastSeen.timeAgoDisplay, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    ConnectionStatusBadge(status: peer.connectionStatus)
                    
                    if peer.isConnected {
                        Text("\(peer.syncCount) synced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDeviceDetails) {
            DeviceDetailsView(peer: peer)
        }
    }
}

// MARK: - Discovered Device Row
struct DiscoveredDeviceRow: View {
    let peer: PeerDevice
    @EnvironmentObject var syncService: SyncService
    @State private var isConnecting = false
    
    var body: some View {
        HStack(spacing: 16) {
            DeviceIcon(deviceType: peer.deviceType, isConnected: false, isCurrentDevice: false)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text("Available to connect")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Label(peer.ipAddress, systemImage: "wifi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                connectToPeer()
            }) {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Connect")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
            }
            .disabled(isConnecting)
        }
        .padding(.vertical, 8)
    }
    
    private func connectToPeer() {
        isConnecting = true
        HapticFeedback.medium()
        
        Task {
            await syncService.connectToPeer(peer)
            isConnecting = false
        }
    }
}

// MARK: - Device Icon
struct DeviceIcon: View {
    let deviceType: DeviceType
    let isConnected: Bool
    let isCurrentDevice: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
                .frame(width: 48, height: 48)
            
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isCurrentDevice ? 2 : 0)
        )
    }
    
    private var iconName: String {
        switch deviceType {
        case .iPhone:
            return "iphone"
        case .iPad:
            return "ipad"
        case .mac:
            return "laptopcomputer"
        case .windows:
            return "pc"
        case .android:
            return "smartphone"
        case .linux:
            return "desktopcomputer"
        case .unknown:
            return "questionmark"
        }
    }
    
    private var backgroundColor: Color {
        if isCurrentDevice {
            return .blue.opacity(0.2)
        } else if isConnected {
            return .green.opacity(0.2)
        } else {
            return .gray.opacity(0.2)
        }
    }
    
    private var iconColor: Color {
        if isCurrentDevice {
            return .blue
        } else if isConnected {
            return .green
        } else {
            return .gray
        }
    }
    
    private var borderColor: Color {
        return isCurrentDevice ? .blue : .clear
    }
}

// MARK: - Connection Status Badge
struct ConnectionStatusBadge: View {
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        case .discovered:
            return .blue
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Offline"
        case .discovered:
            return "Found"
        case .error:
            return "Error"
        }
    }
}

// MARK: - Empty Devices View
struct EmptyDevicesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No devices connected")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Make sure other devices are on the same WiFi network and have LocalPeerSync running.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Network Info Display (Renamed to avoid conflicts)
struct NetworkInfoDisplay: View {
    @EnvironmentObject var syncService: SyncService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network Status", systemImage: "wifi")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                DeviceInfoRow(label: "WiFi Network", value: syncService.currentNetworkName)
                DeviceInfoRow(label: "Local IP", value: syncService.localIPAddress)
                DeviceInfoRow(label: "Listening Port", value: "\(syncService.port)")
                DeviceInfoRow(label: "Discovery", value: syncService.isDiscovering ? "Active" : "Inactive")
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Device Info Row (Renamed to be unique to this file)
struct DeviceInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    DevicesView()
        .environmentObject(SyncService.shared)
}
