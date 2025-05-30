//
//  SettingsView.swift
//  LocalPeerSync
//
//  Created by Nischal Paudyal on 5/29/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var syncService: SyncService
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(syncService)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var autoStart = false
    @State private var showNotifications = true
    
    var body: some View {
        Form {
            Section("Device Information") {
                LabeledContent("Device Name", value: syncService.deviceName)
                LabeledContent("Device ID", value: String(syncService.deviceId.prefix(8)) + "...")
                LabeledContent("Port", value: String(syncService.port))
            }
            
            Section("Preferences") {
                Toggle("Start automatically at login", isOn: $autoStart)
                Toggle("Show notifications", isOn: $showNotifications)
            }
            
            Section("Status") {
                LabeledContent("Service Status", value: syncService.statusText)
                LabeledContent("Connected Devices", value: String(syncService.peers.count))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("LocalPeerSync")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("The world's best clipboard synchronization")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Features:")
                    .font(.headline)
                
                Label("Real-time clipboard sync", systemImage: "doc.on.clipboard")
                Label("Secure local network only", systemImage: "lock.shield")
                Label("Multi-format support", systemImage: "photo.on.rectangle")
                Label("Cross-platform compatibility", systemImage: "laptopcomputer.and.iphone")
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(SyncService.shared)
}
