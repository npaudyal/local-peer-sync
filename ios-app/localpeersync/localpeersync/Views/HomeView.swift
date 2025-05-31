//
//  HomeView.swift
//  LocalPeerSync
//
//  ENHANCED beautiful home screen - FIXED compilation errors
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var showingClipboardInput = false
    @State private var showingQRCode = false
    @State private var isAnimating = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero Status Card
                    StatusHeroCard()
                    
                    // Quick Actions
                    QuickActionsCard(
                        showingClipboardInput: $showingClipboardInput,
                        showingQRCode: $showingQRCode
                    )
                    
                    // Recent Activity
                    if !clipboardManager.recentItems.isEmpty {
                        RecentActivityCard()
                    }
                    
                    // Connection Stats
                    ConnectionStatsCard()
                }
                .padding()
            }
            .navigationTitle("LocalPeerSync")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshData()
            }
        }
        .sheet(isPresented: $showingClipboardInput) {
            ClipboardInputView()
        }
        .sheet(isPresented: $showingQRCode) {
            QRCodeSharingView()
        }
    }
    
    // MARK: - Refresh
    private func refreshData() async {
        await syncService.refreshStatus()
        clipboardManager.checkClipboardChanges()
    }
    
    // MARK: - 🔧 FIXED: Debug Info Method
    private func getDebugInfo() async -> String {
        var info = ["=== LocalPeerSync Debug Info ==="]
        info.append("Swift Side:")
        info.append("  - Running: \(syncService.isRunning)")
        info.append("  - Local IP: \(syncService.localIPAddress)")
        info.append("  - Connected Peers: \(syncService.connectedPeers.count)")
        info.append("  - Discovered Peers: \(syncService.discoveredPeers.count)")
        
        return info.joined(separator: "\n")
    }
}

// MARK: - Status Hero Card
struct StatusHeroCard: View {
    @EnvironmentObject var syncService: SyncService
    
    var body: some View {
        VStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusGradient)
                    .frame(width: 80, height: 80)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            .scaleEffect(syncService.isRunning ? 1.0 : 0.8)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: syncService.isRunning)
            
            // Status Text
            VStack(spacing: 4) {
                Text(syncService.isRunning ? "Active" : "Paused")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(syncService.statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Device Info
            if syncService.isRunning {
                VStack(spacing: 8) {
                    Label("\(syncService.connectedPeers.count) Connected", systemImage: "wifi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !syncService.deviceName.isEmpty {
                        Label(syncService.deviceName, systemImage: "iphone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .animation(.easeInOut(duration: 0.3), value: syncService.isRunning)
    }
    
    private var statusGradient: LinearGradient {
        if syncService.isRunning {
            return LinearGradient(
                colors: [.green, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.gray, .secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var statusIcon: String {
        if syncService.isRunning {
            return syncService.connectedPeers.isEmpty ? "magnifyingglass" : "wifi"
        } else {
            return "wifi.slash"
        }
    }
}

// MARK: - 🔧 FIXED: Quick Actions Card
struct QuickActionsCard: View {
    @EnvironmentObject var syncService: SyncService
    @Binding var showingClipboardInput: Bool
    @Binding var showingQRCode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                // Toggle Sync Button
                ActionButton(
                    title: syncService.isRunning ? "Pause" : "Start",
                    icon: syncService.isRunning ? "pause.circle.fill" : "play.circle.fill",
                    color: syncService.isRunning ? .orange : .green
                ) {
                    HapticFeedback.medium()
                    syncService.toggleSync()
                }
                
                // Add Clipboard Button
                ActionButton(
                    title: "Add Text",
                    icon: "doc.on.clipboard.fill",
                    color: .blue
                ) {
                    HapticFeedback.light()
                    showingClipboardInput = true
                }
                
                // Share QR Code Button
                ActionButton(
                    title: "Share",
                    icon: "qrcode",
                    color: .purple
                ) {
                    HapticFeedback.light()
                    showingQRCode = true
                }
                
                // Settings Button
                NavigationLink(destination: SettingsView()) {
                    ActionButtonContent(
                        title: "Settings",
                        icon: "gear",
                        color: .gray
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ActionButtonContent(title: title, icon: icon, color: color)
        }
        .buttonStyle(ActionButtonStyle())
    }
}

struct ActionButtonContent: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Recent Activity Card
struct RecentActivityCard: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                NavigationLink("See All", destination: HistoryView())
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            LazyVStack(spacing: 8) {
                ForEach(clipboardManager.recentItems.prefix(3)) { item in
                    ClipboardItemRow(item: item, isCompact: true)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Connection Stats Card
struct ConnectionStatsCard: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var clipboardManager: ClipboardManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                
                StatCard(
                    title: "Devices",
                    value: "\(syncService.connectedPeers.count)",
                    icon: "wifi",
                    color: .blue
                )
                
                StatCard(
                    title: "Synced",
                    value: "\(clipboardManager.totalSyncCount)",
                    icon: "arrow.triangle.2.circlepath",
                    color: .green
                )
                
                StatCard(
                    title: "History",
                    value: "\(clipboardManager.recentItems.count)",
                    icon: "clock.fill",
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
}

struct StatCard: View {
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
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    HomeView()
        .environmentObject(SyncService.shared)
        .environmentObject(ClipboardManager.shared)
}
