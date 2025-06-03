//
//  ContentView.swift
//  LocalPeerSync - Background Ready UI (PRODUCTION)
//

import SwiftUI
import os.log

struct ContentView: View {
    @EnvironmentObject var syncService: SyncService
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var notificationManager = BackgroundNotificationManager.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var appState = UIApplication.shared.applicationState
    
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ContentView")
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Enhanced Status Section
                    StatusCard()
                    
                    // Background Status Card
                    BackgroundStatusCard()
                    
                    // Current Clipboard
                    ClipboardCard()
                    
                    // Devices List
                    DevicesSection()
                    
                    // Controls
                    ControlsSection()
                }
                .padding()
            }
            .navigationTitle("LocalPeerSync")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshServices()
            }
        }
        .onAppear {
            startServices()
            requestNotificationPermissions()
        }
        .onDisappear {
            clipboardManager.cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            appState = .active
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            appState = .background
        }
        .alert("LocalPeerSync", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    
    // MARK: - Enhanced Status Card
    @ViewBuilder
    private func StatusCard() -> some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(syncService.isRunning ? .green : .red)
                    .frame(width: 12, height: 12)
                
                Text(syncService.isRunning ? "Active" : "Inactive")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(syncService.connectedPeers.count) devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("App: \(appState.description)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Monitoring")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(clipboardManager.isMonitoring ? "Active" : "Inactive")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Synced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(clipboardManager.syncCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            if let lastSync = clipboardManager.lastSyncTime {
                Text("Last sync: \(lastSync.formatted(.relative(presentation: .numeric)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - NEW: Background Status Card
    @ViewBuilder
    private func BackgroundStatusCard() -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "moon.circle.fill")
                    .foregroundColor(.purple)
                
                Text("Background Operations")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if notificationManager.notificationsEnabled {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "bell.slash")
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Background Syncs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(clipboardManager.backgroundSyncCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Network Ops")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(syncService.backgroundOperationsCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            HStack {
                Button("Enable Notifications") {
                    notificationManager.requestPermissions()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(notificationManager.notificationsEnabled)
                
                Spacer()
                
                Button("Clear Badge") {
                    notificationManager.clearBadge()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Enhanced Clipboard Card
    @ViewBuilder
    private func ClipboardCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Clipboard")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 8) {
                    if !clipboardManager.currentContent.isEmpty {
                        Button("Sync") {
                            Task {
                                let success = await clipboardManager.syncCurrentContent()
                                showAlert(success ? "Synced to other devices!" : "Sync failed!")
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Clear") {
                        clipboardManager.clearClipboard()
                        showAlert("Clipboard cleared!")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            
            ScrollView {
                Text(clipboardManager.getCurrentContentPreview())
                    .font(.body)
                    .foregroundColor(clipboardManager.currentContent.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxHeight: 100)
            
            HStack {
                Text("\(clipboardManager.currentContent.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if clipboardManager.currentContent.hasPrefix("http") {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("URL")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Devices Section (unchanged)
    @ViewBuilder
    private func DevicesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Devices")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Scan") {
                    Task {
                        await scanForDevices()
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            if syncService.connectedPeers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No devices found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Make sure other devices are on the same WiFi network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(syncService.connectedPeers, id: \.id) { peer in
                        DeviceRow(peer: peer)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Enhanced Controls Section
    @ViewBuilder
    private func ControlsSection() -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: {
                    if syncService.isRunning {
                        syncService.stopSync()
                        clipboardManager.stopMonitoring()
                    } else {
                        startServices()
                    }
                }) {
                    HStack {
                        Image(systemName: syncService.isRunning ? "stop.circle" : "play.circle")
                        Text(syncService.isRunning ? "Stop" : "Start")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(syncService.isRunning ? .red : .green, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)
                }
                
                Button("Test Sync") {
                    testSync()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
            }
            
            HStack(spacing: 12) {
                Button("Stats") {
                    showEnhancedStats()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.purple, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
                
                Button("Debug") {
                    Task {
                        await showDebugInfo()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.gray, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Device Row (unchanged)
    @ViewBuilder
    private func DeviceRow(peer: PeerDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: peer.deviceType.iconName)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(peer.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Circle()
                    .fill(peer.isConnected ? .green : .orange)
                    .frame(width: 8, height: 8)
                
                Text(peer.isConnected ? "Connected" : "Discovered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Methods
    
    private func startServices() {
        logger.info("🚀 Starting services with background support...")
        Task {
            await syncService.startSync()
            if syncService.isRunning {
                await clipboardManager.startMonitoring()
                showAlert("Services started with background support!")
            } else {
                showAlert("Failed to start services")
            }
        }
    }
    
    private func requestNotificationPermissions() {
        notificationManager.requestPermissions()
    }
    
    private func testSync() {
        let testMessage = "Test sync at \(Date().formatted(.dateTime))"
        clipboardManager.copyText(testMessage)
        
        Task {
            let success = await clipboardManager.syncCurrentContent()
            await MainActor.run {
                showAlert(success ? "Test sync sent!" : "Test sync failed!")
            }
        }
    }
    
    private func scanForDevices() async {
        await syncService.scanForDevices()
        await MainActor.run {
            showAlert("Device scan completed")
        }
    }
    
    private func refreshServices() async {
        await syncService.refreshStatus()
    }
    
    private func showDebugInfo() async {
        let debugInfo = await syncService.getDebugInfo()
        await MainActor.run {
            alertMessage = debugInfo
            showingAlert = true
        }
    }
    
    private func showEnhancedStats() {
        let stats = clipboardManager.getStats()
        alertMessage = stats.description
        showingAlert = true
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncService.shared)
}
