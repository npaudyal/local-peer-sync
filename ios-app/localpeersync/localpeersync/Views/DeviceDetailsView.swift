//
//  DeviceDetailsView.swift
//  LocalPeerSync
//
//  Detailed device information and management
//

import SwiftUI

struct DeviceDetailsView: View {
    let peer: PeerDevice
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var syncService: SyncService
    @State private var showingDisconnectAlert = false
    @State private var showingRemoveAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Device Header
                    DeviceHeaderCard(peer: peer)
                    
                    // Connection Status
                    ConnectionStatusCard(peer: peer)
                    
                    // Statistics
                    StatisticsCard(peer: peer)
                    
                    // Capabilities
                    CapabilitiesCard(peer: peer)
                    
                    // Network Information
                    NetworkInfoCard(peer: peer)
                    
                    // Actions
                    ActionButtonsCard(
                        peer: peer,
                        showingDisconnectAlert: $showingDisconnectAlert,
                        showingRemoveAlert: $showingRemoveAlert
                    )
                }
                .padding()
            }
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Refresh") {
                            // Refresh device info
                        }
                        
                        if peer.isConnected {
                            Button("Disconnect") {
                                showingDisconnectAlert = true
                            }
                        }
                        
                        Divider()
                        
                        Button("Remove Device", role: .destructive) {
                            showingRemoveAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Disconnect Device", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                // Handle disconnect
            }
        } message: {
            Text("Are you sure you want to disconnect from \(peer.name)?")
        }
        .alert("Remove Device", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                // Handle removal
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("This will permanently remove \(peer.name) from your trusted devices. You'll need to pair again to reconnect.")
        }
    }
}

struct DeviceHeaderCard: View {
    let peer: PeerDevice
    
    var body: some View {
        VStack(spacing: 16) {
            DeviceIcon(deviceType: peer.deviceType, isConnected: peer.isConnected, isCurrentDevice: false)
                .scaleEffect(1.5)
            
            VStack(spacing: 8) {
                Text(peer.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(peer.model)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                ConnectionStatusBadge(status: peer.connectionStatus)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

struct ConnectionStatusCard: View {
    let peer: PeerDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                StatusRow(
                    label: "Status",
                    value: peer.statusDescription,
                    color: Color(peer.connectionStatus.color)
                )
                
                StatusRow(
                    label: "Connection Quality",
                    value: peer.connectionQuality.displayName,
                    color: Color(peer.connectionQuality.color)
                )
                
                if let lastSeen = peer.lastSeen {
                    StatusRow(
                        label: "Last Seen",
                        value: lastSeen.timeAgoDisplay,
                        color: .secondary
                    )
                }
                
                StatusRow(
                    label: "Uptime",
                    value: peer.formattedUptime,
                    color: .secondary
                )
                
                if peer.isTrusted {
                    StatusRow(
                        label: "Trust Level",
                        value: "Trusted Device",
                        color: .green
                    )
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct StatisticsCard: View {
    let peer: PeerDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatisticItem(
                    title: "Syncs",
                    value: "\(peer.syncCount)",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue
                )
                
                StatisticItem(
                    title: "Data",
                    value: peer.formattedBytesTransferred,
                    icon: "icloud.and.arrow.up.and.arrow.down",
                    color: .green
                )
                
                StatisticItem(
                    title: "Quality",
                    value: "\(peer.connectionQuality.signalBars)/4",
                    icon: "wifi",
                    color: Color(peer.connectionQuality.color)
                )
                
                StatisticItem(
                    title: "Version",
                    value: peer.version,
                    icon: "number",
                    color: .orange
                )
            }
        }
    }
}

struct StatisticItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct CapabilitiesCard: View {
    let peer: PeerDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capabilities")
                .font(.headline)
                .fontWeight(.semibold)
            
            if peer.capabilities.isEmpty {
                Text("No specific capabilities reported")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    
                    CapabilityItem(
                        title: "Images",
                        isSupported: peer.supportsImages(),
                        icon: "photo"
                    )
                    
                    CapabilityItem(
                        title: "Files",
                        isSupported: peer.supportsFiles(),
                        icon: "doc"
                    )
                    
                    CapabilityItem(
                        title: "Rich Text",
                        isSupported: peer.supportsRichText(),
                        icon: "doc.richtext"
                    )
                    
                    CapabilityItem(
                        title: "Compression",
                        isSupported: peer.supportsCompression(),
                        icon: "arrow.up.and.down.and.arrow.left.and.right"
                    )
                    
                    CapabilityItem(
                        title: "Encryption",
                        isSupported: peer.supportsEncryption(),
                        icon: "lock.shield"
                    )
                }
            }
        }
    }
}

struct CapabilityItem: View {
    let title: String
    let isSupported: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isSupported ? .green : .gray)
            
            Text(title)
                .font(.caption)
                .foregroundColor(isSupported ? .primary : .secondary)
            
            Spacer()
            
            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption)
                .foregroundColor(isSupported ? .green : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

struct NetworkInfoCard: View {
    let peer: PeerDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Information")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                NetworkInfoRow(label: "IP Address", value: peer.ipAddress, icon: "wifi")
                NetworkInfoRow(label: "Port", value: "\(peer.port)", icon: "network")
                NetworkInfoRow(label: "Device Type", value: peer.deviceType.displayName, icon: peer.deviceType.iconName)
                NetworkInfoRow(label: "Platform", value: peer.deviceType.platform, icon: "gear")
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct NetworkInfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
}

struct ActionButtonsCard: View {
    let peer: PeerDevice
    @Binding var showingDisconnectAlert: Bool
    @Binding var showingRemoveAlert: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if peer.isConnected {
                Button(action: {
                    showingDisconnectAlert = true
                }) {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Disconnect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                Button(action: {
                    // Handle reconnect
                }) {
                    HStack {
                        Image(systemName: "wifi")
                        Text("Connect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            
            Button(action: {
                showingRemoveAlert = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Remove Device")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

#Preview {
    DeviceDetailsView(peer: PeerDevice(
        id: "preview-device",
        name: "MacBook Pro",
        model: "MacBook Pro 16-inch",
        deviceType: .mac,
        ipAddress: "192.168.1.100",
        connectionStatus: .connected,
        isConnected: true,
        isTrusted: true,
        syncCount: 42,
        bytesTransferred: 1024 * 1024,
        capabilities: ["images", "files", "compression", "encryption"],
        version: "1.0.0"
    ))
    .environmentObject(SyncService.shared)
}
