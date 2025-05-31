//
//  DebugView.swift
//  localpeersync
//
//  Created by Nischal Paudyal on 5/30/25.
//

import SwiftUI

struct DebugView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var debugOutput = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("🧪 mDNS Discovery Debug")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    // Status Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📊 Status")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Running: \(syncService.isRunning ? "✅" : "❌")")
                            Text("Discovering: \(syncService.isDiscovering ? "✅" : "❌")")
                            Text("Local IP: \(syncService.localIPAddress)")
                            Text("Connected Peers: \(syncService.connectedPeers.count)")
                            Text("Discovered Peers: \(syncService.discoveredPeers.count)")
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Debug Actions
                    VStack(spacing: 12) {
                        Text("🔍 Debug Actions")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            
                            DebugButton(title: "Start Discovery") {
                                syncService.startSync()
                            }
                            
                            DebugButton(title: "Stop Discovery") {
                                syncService.stopSync()
                            }
                            
                        }
                    }
                    
                    // Expected Services
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🎯 Expected Services")
                            .font(.headline)
                        
                        Text("Looking for these services on your network:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Ultimate-mac-2689._localpeersync._tcp.local.")
                            Text("• Ultimate-Win-*._localpeersync._tcp.local.")
                            Text("• Port: 8421")
                            Text("• TXT: device_id, version, encryption, port")
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📝 Instructions")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Ensure Mac/Windows apps are running")
                            Text("2. Both devices on same WiFi network")
                            Text("3. Check Console.app for detailed logs")
                            Text("4. Grant local network permission")
                            Text("5. Test on real device (not simulator)")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Debug")
        }
    }
}

struct DebugButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.blue)
                .cornerRadius(8)
        }
    }
}

#Preview {
    DebugView()
        .environmentObject(SyncService.shared)
}
