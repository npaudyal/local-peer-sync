//
//  BackgroundNotificationManager.swift
//  LocalPeerSync - Background Notifications (FIXED ACTOR ISSUES)
//

import Foundation
import UserNotifications
import UIKit
import os.log

@MainActor
class BackgroundNotificationManager: NSObject, ObservableObject {
    static let shared = BackgroundNotificationManager()
    
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "BackgroundNotifications")
    private let notificationCenter = UNUserNotificationCenter.current()
    
    @Published var notificationsEnabled = false
    @Published var lastNotificationTime: Date?
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        notificationCenter.delegate = self
        requestPermissions()
    }
    
    func requestPermissions() {
        logger.info("🔔 Requesting notification permissions")
        
        Task {
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    self.notificationsEnabled = granted
                    self.logger.info("✅ Notification permissions: \(granted)")
                }
            } catch {
                await MainActor.run {
                    self.logger.error("❌ Failed to request notification permissions: \(error)")
                }
            }
        }
    }
    
    func notifyClipboardReceived(preview: String) {
        guard notificationsEnabled else { return }
        guard UIApplication.shared.applicationState != .active else { return }
        
        logger.info("🔔 Sending clipboard received notification")
        
        let content = UNMutableNotificationContent()
        content.title = "Clipboard Synced"
        content.body = "📋 \(preview)"
        content.sound = .default
        content.badge = 1
        
        // Add action buttons
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View",
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: "CLIPBOARD_SYNC",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
        content.categoryIdentifier = "CLIPBOARD_SYNC"
        
        let request = UNNotificationRequest(
            identifier: "clipboard_sync_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        Task {
            do {
                try await notificationCenter.add(request)
                await MainActor.run {
                    self.lastNotificationTime = Date()
                    self.logger.info("✅ Notification sent successfully")
                }
            } catch {
                self.logger.error("❌ Failed to send notification: \(error)")
            }
        }
    }
    
    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension BackgroundNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.info("🔔 User tapped notification: \(response.actionIdentifier)")
        
        if response.actionIdentifier == "VIEW_ACTION" {
            // App will come to foreground automatically
        }
        
        clearBadge()
        completionHandler()
    }
}
