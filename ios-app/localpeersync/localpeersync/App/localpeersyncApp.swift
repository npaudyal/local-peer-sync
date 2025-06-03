//
//  LocalPeerSyncApp.swift
//  LocalPeerSync
//

import SwiftUI
import UserNotifications
import os.log

@main
struct LocalPeerSyncApp: App {
    private let logger = Logger(subsystem: "com.nischal.ios.localpeersync", category: "App")
    
    init() {
        logger.info("🚀 LocalPeerSync iOS Starting...")
        
        // Request notification permissions for feedback
        requestNotificationPermissions()
        
        // Initialize widget with current state
        updateWidgetFromService()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SyncService.shared)
                .onAppear {
                    updateWidgetFromService()
                }
                .onOpenURL { url in
                    handleWidgetAction(url)
                }
        }
    }
    
    // MARK: - Widget Integration
    
    private func handleWidgetAction(_ url: URL) {
        guard url.scheme == "localpeersync" else { return }
        
        switch url.host {
        case "toggle":
            toggleSyncService()
        default:
            logger.warning("⚠️ Unknown widget action: \(url)")
        }
    }
    
    private func toggleSyncService() {
        let syncService = SyncService.shared
        
        logger.info("🔄 Widget toggle requested - Current state: \(syncService.isRunning)")
        
        if syncService.isRunning {
            // Turn OFF
            syncService.stopSync()
            logger.info("🛑 Service stopped via widget")
            
            // Update widget
            SimpleWidgetManager.shared.updateServiceStatus(
                isRunning: false,
                deviceCount: 0,
                deviceName: syncService.deviceName
            )
            
            // User feedback
            showToggleFeedback(message: "LocalPeerSync stopped", isOn: false)
            
        } else {
            // Turn ON
            syncService.startSync()
            logger.info("▶️ Service started via widget")
            
            // Update widget immediately, then again after connection
            SimpleWidgetManager.shared.updateServiceStatus(
                isRunning: true,
                deviceCount: 0, // Will update when devices connect
                deviceName: syncService.deviceName
            )
            
            // User feedback
            showToggleFeedback(message: "LocalPeerSync started", isOn: true)
            
            // Update widget with device count after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.updateWidgetFromService()
            }
        }
    }
    
    private func updateWidgetFromService() {
        let syncService = SyncService.shared
        
        SimpleWidgetManager.shared.updateServiceStatus(
            isRunning: syncService.isRunning,
            deviceCount: syncService.peers.count,
            deviceName: syncService.deviceName
        )
        
        logger.info("📱 Widget updated: Running=\(syncService.isRunning), Devices=\(syncService.peers.count)")
    }
    
    private func showToggleFeedback(message: String, isOn: Bool) {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: isOn ? .heavy : .light)
        impactFeedback.impactOccurred()
        
        // Brief local notification
        let content = UNMutableNotificationContent()
        content.title = "LocalPeerSync"
        content.body = message
        content.sound = nil // Silent
        
        let request = UNNotificationRequest(
            identifier: "toggle_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
        
        logger.info("📢 Toggle feedback: \(message)")
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { granted, error in
            if granted {
                self.logger.info("✅ Notification permissions granted")
            } else {
                self.logger.info("❌ Notification permissions denied")
            }
        }
    }
}
