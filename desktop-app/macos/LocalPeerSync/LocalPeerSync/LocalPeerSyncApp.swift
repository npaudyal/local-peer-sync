//
//  LocalPeerSyncApp.swift
//  LocalPeerSync
//
//  Created by Nischal Paudyal on 5/29/25.
//
import SwiftUI
import Combine

@main
struct LocalPeerSyncApp: App {
    @StateObject private var syncService = SyncService.shared
    @State private var settingsWindow: NSWindow?
    
    var body: some Scene {
        // Hide the main window - we're a menu bar app
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        // Menu bar extra
        MenuBarExtra("LocalPeerSync", systemImage: syncService.isRunning ? "wifi" : "wifi.slash") {
            MenuBarView()
                .environmentObject(syncService)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        Settings {
            SettingsView()
                .environmentObject(syncService)
        }
    }
}

// MARK: - Menu Bar View
struct MenuBarView: View {
    @EnvironmentObject var syncService: SyncService
    @Environment(\.openWindow) var openWindow
    
    // Update the MenuBarView body
    var body: some View {
        VStack(spacing: 0) {
            // Header with better styling
            HStack {
                Image(systemName: syncService.isRunning ? "wifi" : "wifi.slash")
                    .foregroundColor(syncService.isRunning ? .green : .red)
                    .font(.title2)
                    .symbolEffect(.pulse, isActive: syncService.isRunning)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("LocalPeerSync")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(syncService.statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { syncService.toggleSync() }) {
                    Image(systemName: syncService.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(syncService.isRunning ? .orange : .green)
                        .symbolEffect(.bounce, value: syncService.isRunning)
                }
                .buttonStyle(.plain)
                .help(syncService.isRunning ? "Pause Sync" : "Start Sync")
            }
            .padding()
            
            Divider()
            
            // Peer List with better empty state
            if !syncService.peers.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Connected Devices")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(syncService.peers.count)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                        
                        ForEach(syncService.peers, id: \.self) { peer in
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                    .symbolEffect(.pulse)
                                
                                Text(peer)
                                    .font(.body)
                                
                                Spacer()
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 150)
                
                Divider()
            } else if syncService.isRunning {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    VStack(spacing: 4) {
                        Text("Searching for devices...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Make sure other devices are on the same WiFi network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                
                Divider()
            }
            
            // Device Info with better styling
            VStack(alignment: .leading, spacing: 8) {
                Text("This Device")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(spacing: 4) {
                    HStack {
                        Text("Name:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(syncService.deviceName)
                            .font(.system(.caption, design: .monospaced))

                    }
                    
                    HStack {
                        Text("Port:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(syncService.port)")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Actions
            VStack(spacing: 4) {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.link)
                
                Button("Quit LocalPeerSync") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}
