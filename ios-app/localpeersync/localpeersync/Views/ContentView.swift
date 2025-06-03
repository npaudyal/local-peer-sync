//
//  ContentView.swift
//  LocalPeerSync - Simple iOS Version
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Card
                    StatusCard()
                    
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
        }
        .onAppear {
            // Auto-start when app appears
            if !syncService.isRunning {
                syncService.startSync()
            }
        }
        .alert("LocalPeerSync", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Status Card
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
                
                Text("\(syncService.peers.count) devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(syncService.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Clipboard Card
    @ViewBuilder
    private func ClipboardCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clipboard Test")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Test Sync") {
                    testSync()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            Text("Tap 'Test Sync' to test clipboard synchronization")
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Devices Section
    @ViewBuilder
    private func DevicesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Devices")
                .font(.headline)
                .fontWeight(.semibold)
            
            if syncService.peers.isEmpty {
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
                    ForEach(syncService.peers, id: \.self) { peer in
                        DeviceRow(peer: peer)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Controls Section
    @ViewBuilder
    private func ControlsSection() -> some View {
        VStack(spacing: 12) {
            Button(action: {
                syncService.toggleSync()
            }) {
                HStack {
                    Image(systemName: syncService.isRunning ? "stop.circle" : "play.circle")
                    Text(syncService.isRunning ? "Stop Sync" : "Start Sync")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(syncService.isRunning ? .red : .green, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
            }
            Button("Test Bridge") {
                testBridgeDirectly()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.red, in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.white)
            
            Button("Device Info") {
                showDeviceInfo()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue, in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.white)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func testBridgeDirectly() {
        print("🧪 Testing bridge directly...")
        
        let testText = "Bridge test \(Date().timeIntervalSince1970)"
        let result = testText.withCString { cString in
            ios_set_clipboard_text(cString)
        }
        
        if result == 1 {
            showAlert("✅ Bridge test successful!")
        } else {
            showAlert("❌ Bridge test failed!")
        }
    }
    
    // MARK: - Device Row
    @ViewBuilder
    private func DeviceRow(peer: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(peer)
                .font(.body)
                .fontWeight(.medium)
            
            Spacer()
            
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Methods
    private func testSync() {
        let testMessage = "Test sync from iOS at \(Date().formatted(.dateTime))"
        
        // Set clipboard content
        UIPasteboard.general.string = testMessage
        
        // Async sync to avoid blocking UI
        Task {
            do {
                let success = await performAsyncClipboardSync(testMessage)
                
                await MainActor.run {
                    if success {
                        showAlert("✅ Test sync sent successfully!")
                    } else {
                        showAlert("❌ Test sync failed!")
                    }
                }
            } catch {
                await MainActor.run {
                    showAlert("❌ Test sync error: \(error.localizedDescription)")
                }
            }
        }
    }

    // Add this new async sync method to ContentView
    private func performAsyncClipboardSync(_ content: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = syncService.syncClipboard(content)
                continuation.resume(returning: success)
            }
        }
    }
    
    private func showDeviceInfo() {
        alertMessage = """
        Device Name: \(syncService.deviceName)
        Device ID: \(syncService.deviceId)
        Port: \(syncService.port)
        Status: \(syncService.statusText)
        Connected Peers: \(syncService.peers.count)
        """
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
