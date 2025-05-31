//
//  SettingsView.swift
//  LocalPeerSync
//
//  Comprehensive settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var clipboardManager: ClipboardManager
    @EnvironmentObject var notificationManager: NotificationManager
    @AppStorage("autoStartSync") private var autoStartSync = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("compressionEnabled") private var compressionEnabled = true
    @AppStorage("historyLimit") private var historyLimit = 100
    
    var body: some View {
        NavigationView {
            List {
                // Device Section
                Section("Device") {
                    DeviceInfoCard()
                }
                
                // Sync Settings
                Section("Synchronization") {
                    SyncSettingsCard()
                }
                
                // Privacy & Security
                Section("Privacy & Security") {
                    PrivacySettingsCard()
                }
                
                // Notifications
                Section("Notifications") {
                    NotificationSettingsCard()
                }
                
                // Advanced
                Section("Advanced") {
                    AdvancedSettingsCard()
                }
                
                // About
                Section("About") {
                    AboutCard()
                }
                
                // Support
                Section("Support") {
                    SupportCard()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Device Info Card
struct DeviceInfoCard: View {
    @EnvironmentObject var syncService: SyncService
    @State private var showingDeviceRename = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DeviceIcon(deviceType: .iPhone, isConnected: true, isCurrentDevice: true)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncService.deviceName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(syncService.deviceModel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Edit") {
                    showingDeviceRename = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRowView(label: "Device ID", value: syncService.deviceId.prefix(8) + "...")
                InfoRowView(label: "iOS Version", value: UIDevice.current.systemVersion)
                InfoRowView(label: "App Version", value: Bundle.main.appVersion)
                InfoRowView(label: "Local IP", value: syncService.localIPAddress)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showingDeviceRename) {
            DeviceRenameView()
        }
    }
}

// MARK: - Sync Settings Card
struct SyncSettingsCard: View {
    @EnvironmentObject var syncService: SyncService
    @AppStorage("autoStartSync") private var autoStartSync = true
    @AppStorage("syncImages") private var syncImages = true
    @AppStorage("syncFiles") private var syncFiles = true
    @AppStorage("compressionEnabled") private var compressionEnabled = true
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsToggle(
                title: "Auto-start Sync",
                description: "Automatically start syncing when app launches",
                isOn: $autoStartSync,
                icon: "play.circle"
            )
            
            SettingsToggle(
                title: "Sync Images",
                description: "Include images in clipboard synchronization",
                isOn: $syncImages,
                icon: "photo"
            )
            
            SettingsToggle(
                title: "Sync Files",
                description: "Include files in clipboard synchronization",
                isOn: $syncFiles,
                icon: "doc"
            )
            
            SettingsToggle(
                title: "Compression",
                description: "Compress large content for faster transfer",
                isOn: $compressionEnabled,
                icon: "arrow.up.and.down.and.arrow.left.and.right"
            )
            
            Divider()
            
            NavigationLink(destination: TrustedDevicesView()) {
                SettingsRow(
                    title: "Trusted Devices",
                    description: "\(syncService.trustedDevices.count) devices",
                    icon: "checkmark.shield"
                )
            }
        }
    }
}

// MARK: - Privacy Settings Card
struct PrivacySettingsCard: View {
    @AppStorage("encryptionEnabled") private var encryptionEnabled = true
    @AppStorage("localNetworkOnly") private var localNetworkOnly = true
    @AppStorage("autoTrustDevices") private var autoTrustDevices = false
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsToggle(
                title: "Encryption",
                description: "Encrypt all data transfers (recommended)",
                isOn: $encryptionEnabled,
                icon: "lock.shield"
            )
            .disabled(true) // Always enabled for security
            
            SettingsToggle(
                title: "Local Network Only",
                description: "Only sync with devices on same WiFi network",
                isOn: $localNetworkOnly,
                icon: "wifi"
            )
            .disabled(true) // Always enabled for privacy
            
            SettingsToggle(
                title: "Auto-trust Devices",
                description: "Automatically trust new discovered devices",
                isOn: $autoTrustDevices,
                icon: "hand.raised"
            )
            
            Divider()
            
            NavigationLink(destination: SecurityLogView()) {
                SettingsRow(
                    title: "Security Log",
                    description: "View connection and sync history",
                    icon: "list.clipboard"
                )
            }
        }
    }
}

// MARK: - Notification Settings Card
struct NotificationSettingsCard: View {
    @EnvironmentObject var notificationManager: NotificationManager
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("syncNotifications") private var syncNotifications = true
    @AppStorage("deviceNotifications") private var deviceNotifications = true
    @AppStorage("errorNotifications") private var errorNotifications = true
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsToggle(
                title: "Enable Notifications",
                description: "Receive notifications for sync events",
                isOn: $notificationsEnabled,
                icon: "bell"
            )
            
            if notificationsEnabled {
                Group {
                    SettingsToggle(
                        title: "Sync Notifications",
                        description: "When clipboard content is synced",
                        isOn: $syncNotifications,
                        icon: "arrow.triangle.2.circlepath"
                    )
                    
                    SettingsToggle(
                        title: "Device Notifications",
                        description: "When devices connect or disconnect",
                        isOn: $deviceNotifications,
                        icon: "wifi"
                    )
                    
                    SettingsToggle(
                        title: "Error Notifications",
                        description: "When sync errors occur",
                        isOn: $errorNotifications,
                        icon: "exclamationmark.triangle"
                    )
                }
                .transition(.opacity)
            }
            
            if !notificationManager.hasPermission {
                Button("Enable in Settings") {
                    notificationManager.openSettings()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .animation(.easeInOut, value: notificationsEnabled)
    }
}

// MARK: - Advanced Settings Card
struct AdvancedSettingsCard: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @AppStorage("historyLimit") private var historyLimit = 100
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("debugMode") private var debugMode = false
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsSlider(
                title: "History Limit",
                description: "Maximum number of items to keep in history",
                value: $historyLimit,
                range: 10...500,
                step: 10,
                icon: "clock"
            )
            
            SettingsToggle(
                title: "Haptic Feedback",
                description: "Vibrate for user interactions",
                isOn: $hapticFeedback,
                icon: "iphone.radiowaves.left.and.right"
            )
            
            SettingsToggle(
                title: "Debug Mode",
                description: "Enable detailed logging for troubleshooting",
                isOn: $debugMode,
                icon: "ladybug"
            )
            
            Divider()
            
            Button("Export Settings") {
                exportSettings()
            }
            .buttonStyle(.bordered)
            
            Button("Reset to Defaults") {
                resetSettings()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
    }
    
    private func exportSettings() {
        // Implementation for exporting settings
        HapticFeedback.success()
    }
    
    private func resetSettings() {
        // Implementation for resetting settings
        HapticFeedback.medium()
    }
}

// MARK: - About Card
struct AboutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("LocalPeerSync")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Version \(Bundle.main.appVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Build \(Bundle.main.buildNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text("The world's best clipboard synchronization app. Seamlessly sync clipboard content across all your devices on the same local network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
        }
    }
}

// MARK: - Support Card
struct SupportCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Button("Contact Support") {
                openSupportEmail()
            }
            .buttonStyle(.bordered)
            
            Button("Report a Bug") {
                reportBug()
            }
            .buttonStyle(.bordered)
            
            Button("Feature Request") {
                requestFeature()
            }
            .buttonStyle(.bordered)
            
            Button("Rate App") {
                rateApp()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func openSupportEmail() {
        if let url = URL(string: "mailto:support@localpeersync.com") {
            UIApplication.shared.open(url)
        }
    }
    
    private func reportBug() {
        if let url = URL(string: "https://github.com/localpeersync/issues") {
            UIApplication.shared.open(url)
        }
    }
    
    private func requestFeature() {
        if let url = URL(string: "https://github.com/localpeersync/discussions") {
            UIApplication.shared.open(url)
        }
    }
    
    private func rateApp() {
        if let url = URL(string: "https://apps.apple.com/app/localpeersync/id123456789?action=write-review") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Settings Components
struct SettingsToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct SettingsRow: View {
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsSlider: View {
    let title: String
    let description: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(value)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .accentColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct InfoRowView: View {
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
    SettingsView()
        .environmentObject(SyncService.shared)
        .environmentObject(ClipboardManager.shared)
        .environmentObject(NotificationManager.shared)
}
