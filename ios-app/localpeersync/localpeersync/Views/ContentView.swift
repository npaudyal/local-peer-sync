//
//  ContentView.swift
//  LocalPeerSync
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HeaderSection()
                    
                    // Quick Status
                    StatusSection()
                    
                    // Control Center Instructions
                    ControlCenterSection()
                    
                    // Device List
                    if syncService.isRunning {
                        DevicesSection()
                    }
                    
                    // Manual Controls (for troubleshooting)
                    ManualControlsSection()
                }
                .padding()
            }
            .navigationTitle("LocalPeerSync")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("About") {
                        showingAbout = true
                    }
                }
            }
        }
        .onAppear {
            // Auto-start if not running (first time setup)
            if !syncService.isRunning {
                syncService.startSync()
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
    
    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("LocalPeerSync")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Instant clipboard sync across your devices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    private func StatusSection() -> some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(syncService.isRunning ? .green : .red)
                    .frame(width: 12, height: 12)
                
                Text(syncService.isRunning ? "Service Running" : "Service Stopped")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            if syncService.isRunning {
                HStack {
                    Text("Connected Devices:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(syncService.peers.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func ControlCenterSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "switch.2")
                    .font(.title3)
                    .foregroundColor(.blue)
                
                Text("Control Center Widget")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    number: "1",
                    text: "Add widget to Control Center",
                    detail: "Long press home screen → + → Search 'LocalPeerSync'"
                )
                
                InstructionRow(
                    number: "2",
                    text: "Toggle service anytime",
                    detail: "Swipe down from top-right → Tap LocalPeerSync widget"
                )
                
                InstructionRow(
                    number: "3",
                    text: "Sync automatically",
                    detail: "Copy on any device → Paste on any other device"
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func InstructionRow(number: String, text: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(.blue, in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func DevicesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Devices")
                .font(.headline)
                .fontWeight(.semibold)
            
            if syncService.peers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Searching for devices...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(syncService.peers, id: \.self) { peer in
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .foregroundColor(.blue)
                            
                            Text(peer)
                                .font(.body)
                            
                            Spacer()
                            
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func ManualControlsSection() -> some View {
        VStack(spacing: 12) {
            Text("Manual Controls")
                .font(.headline)
                .fontWeight(.semibold)
            
            Button(action: {
                syncService.toggleSync()
            }) {
                HStack {
                    Image(systemName: syncService.isRunning ? "stop.circle" : "play.circle")
                    Text(syncService.isRunning ? "Stop Service" : "Start Service")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(syncService.isRunning ? .red : .green, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("LocalPeerSync")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Secure, private clipboard sync for your local network. No cloud, no tracking, just seamless copy and paste across your devices.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncService.shared)
}
