//
//  NotificationManager.swift
//  LocalPeerSync
//
//  Comprehensive notification management
//

import Foundation
import UserNotifications
import UIKit
import os.log

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    @Published var hasPermission: Bool = false
    @Published var notificationSettings: UNNotificationSettings?
    @Published var pendingNotifications: [UNNotificationRequest] = []
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "NotificationManager")
    private let center = UNUserNotificationCenter.current()
    
    // MARK: - Notification Categories
    private let syncCategory = "SYNC_CATEGORY"
    private let deviceCategory = "DEVICE_CATEGORY"
    private let errorCategory = "ERROR_CATEGORY"
    
    // MARK: - Initialization
    override init() {
        super.init()
        center.delegate = self
        setupNotificationCategories()
        checkPermissionStatus()
    }
    
    // MARK: - Permission Management
    func requestPermissions() {
        logger.info("📱 Requesting notification permissions")
        
        center.requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { [weak self] granted, error in
            Task { @MainActor in
                if let error = error {
                    self?.logger.error("❌ Notification permission error: \(error)")
                } else {
                    self?.logger.info("📱 Notification permissions granted: \(granted)")
                }
                
                self?.hasPermission = granted
                await self?.updateNotificationSettings()
            }
        }
    }
    
    func checkPermissionStatus() {
        Task {
            await updateNotificationSettings()
        }
    }
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private func updateNotificationSettings() async {
        let settings = await center.notificationSettings()
        notificationSettings = settings
        hasPermission = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        
        logger.info("📱 Notification authorization status: \(settings.authorizationStatus.rawValue)")
    }
    
    // MARK: - Notification Categories Setup
    private func setupNotificationCategories() {
        // Sync notifications with actions
        let copyAction = UNNotificationAction(
            identifier: "COPY_ACTION",
            title: "Copy to Clipboard",
            options: [.foreground]
        )
        
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )
        
        let syncCategory = UNNotificationCategory(
            identifier: self.syncCategory,
            actions: [copyAction, viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Device notifications with actions
        let connectAction = UNNotificationAction(
            identifier: "CONNECT_ACTION",
            title: "Connect",
            options: [.foreground]
        )
        
        let ignoreAction = UNNotificationAction(
            identifier: "IGNORE_ACTION",
            title: "Ignore",
            options: []
        )
        
        let deviceCategory = UNNotificationCategory(
            identifier: self.deviceCategory,
            actions: [connectAction, ignoreAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Error notifications
        let retryAction = UNNotificationAction(
            identifier: "RETRY_ACTION",
            title: "Retry",
            options: [.foreground]
        )
        
        let errorCategory = UNNotificationCategory(
            identifier: self.errorCategory,
            actions: [retryAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([syncCategory, deviceCategory, errorCategory])
        logger.info("📱 Notification categories configured")
    }
    
    // MARK: - Sync Notifications
    func sendSyncNotification(content: String) {
        guard hasPermission && UserDefaults.standard.bool(forKey: "syncNotifications") else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Clipboard Synced"
        
        let preview = String(content.prefix(50))
        notificationContent.body = preview.count < content.count ? "\(preview)..." : preview
        
        notificationContent.sound = .default
        notificationContent.categoryIdentifier = syncCategory
        notificationContent.badge = 1
        
        // Add custom data
        notificationContent.userInfo = [
            "type": "sync",
            "content": content,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: "sync-\(UUID().uuidString)",
            content: notificationContent,
            trigger: nil
        )
        
        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Failed to send sync notification: \(error)")
            } else {
                self?.logger.info("📤 Sent sync notification")
            }
        }
    }
    
    func sendClipboardUpdateNotification(content: String, sourceDevice: String) {
        guard hasPermission else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Clipboard Updated"
        notificationContent.body = "From \(sourceDevice): \(String(content.prefix(40)))..."
        notificationContent.sound = .default
        notificationContent.categoryIdentifier = syncCategory
        
        notificationContent.userInfo = [
            "type": "clipboard_update",
            "content": content,
            "sourceDevice": sourceDevice,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: "clipboard-update-\(UUID().uuidString)",
            content: notificationContent,
            trigger: nil
        )
        
        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Failed to send clipboard update notification: \(error)")
            }
        }
    }
    
    // MARK: - Device Notifications
    func sendDeviceConnectedNotification(deviceName: String) {
        guard hasPermission && UserDefaults.standard.bool(forKey: "deviceNotifications") else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Device Connected"
        notificationContent.body = "\(deviceName) has connected to LocalPeerSync"
        notificationContent.sound = .default
        notificationContent.categoryIdentifier = deviceCategory
        
        notificationContent.userInfo = [
            "type": "device_connected",
            "deviceName": deviceName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendNotification(request: UNNotificationRequest(
            identifier: "device-connected-\(UUID().uuidString)",
            content: notificationContent,
            trigger: nil
        ))
    }
    
    func sendDeviceDisconnectedNotification(deviceName: String) {
        guard hasPermission && UserDefaults.standard.bool(forKey: "deviceNotifications") else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Device Disconnected"
        notificationContent.body = "\(deviceName) has disconnected from LocalPeerSync"
        notificationContent.sound = .default
        
        notificationContent.userInfo = [
            "type": "device_disconnected",
            "deviceName": deviceName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendNotification(request: UNNotificationRequest(
            identifier: "device-disconnected-\(UUID().uuidString)",
            content: notificationContent,
            trigger: nil
        ))
    }
    
    func sendNewDeviceDiscoveredNotification(deviceName: String) {
        guard hasPermission else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "New Device Found"
        notificationContent.body = "\(deviceName) is available to connect"
        notificationContent.sound = .default
        notificationContent.categoryIdentifier = deviceCategory
        
        notificationContent.userInfo = [
            "type": "device_discovered",
            "deviceName": deviceName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        sendNotification(request: UNNotificationRequest(
            identifier: "device-discovered-\(UUID().uuidString)",
            content: notificationContent,
            trigger: nil
        ))
    }
    
    // MARK: - Error Notifications
    func sendErrorNotification(title: String, message: String, error: Error? = nil) {
        guard hasPermission && UserDefaults.standard.bool(forKey: "errorNotifications") else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = message
        notificationContent.sound = .defaultCritical
        notificationContent.categoryIdentifier = errorCategory
        
        var userInfo: [String: Any] = [
            "type": "error",
            "title": title,
            "message": message,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let error = error {
            userInfo["error"] = error.localizedDescription
        }
        
        notificationContent.userInfo = userInfo
        
        sendNotification(request: UNNotificationRequest(
            identifier: "error-\(UUID().uuidString)",
            content: notificationContent,
            trigger: nil
        ))
    }
    
    func sendSyncFailedNotification(reason: String) {
        sendErrorNotification(
            title: "Sync Failed",
            message: "Unable to sync clipboard: \(reason)"
        )
    }
    
    func sendConnectionErrorNotification(deviceName: String, error: Error) {
        sendErrorNotification(
            title: "Connection Error",
            message: "Failed to connect to \(deviceName): \(error.localizedDescription)",
            error: error
        )
    }
    
    // MARK: - Scheduled Notifications
    func scheduleReminderNotification(content: String, delay: TimeInterval) {
        guard hasPermission else { return }
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Clipboard Reminder"
        notificationContent.body = "You have unsent clipboard content: \(String(content.prefix(40)))..."
        notificationContent.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "reminder-\(UUID().uuidString)",
            content: notificationContent,
            trigger: trigger
        )
        
        sendNotification(request: request)
    }
    
    // MARK: - Notification Management
    private func sendNotification(request: UNNotificationRequest) {
        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Failed to send notification: \(error)")
            } else {
                self?.logger.info("📤 Sent notification: \(request.identifier)")
            }
        }
    }
    
    func clearAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        logger.info("🧹 Cleared all notifications")
    }
    
    func clearNotifications(withIdentifierPrefix prefix: String) {
        center.getPendingNotificationRequests { requests in
            let idsToRemove = requests.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        }
        
        center.getDeliveredNotifications { notifications in
            let idsToRemove = notifications.filter { $0.request.identifier.hasPrefix(prefix) }.map { $0.request.identifier }
            self.center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
        }
    }
    
    func updateBadgeCount(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
    }
    
    // MARK: - Notification Testing
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "LocalPeerSync Test"
        content.body = "This is a test notification to verify everything is working correctly."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        sendNotification(request: request)
    }
    
    // MARK: - Analytics
    func getNotificationStats() -> NotificationStats {
        return NotificationStats(
            hasPermission: hasPermission,
            authorizationStatus: notificationSettings?.authorizationStatus.rawValue ?? 0,
            alertSetting: notificationSettings?.alertSetting.rawValue ?? 0,
            soundSetting: notificationSettings?.soundSetting.rawValue ?? 0,
            badgeSetting: notificationSettings?.badgeSetting.rawValue ?? 0
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response)
        completionHandler()
    }
    
    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        logger.info("📱 Handling notification action: \(actionIdentifier)")
        
        switch actionIdentifier {
        case "COPY_ACTION":
            if let content = userInfo["content"] as? String {
                ClipboardManager.shared.setClipboardContent(content, source: "notification")
                HapticFeedback.success()
            }
            
        case "VIEW_ACTION":
            // Open app to history view
            openAppToHistory()
            
        case "CONNECT_ACTION":
            if let deviceName = userInfo["deviceName"] as? String {
                // Handle device connection
                handleDeviceConnection(deviceName: deviceName)
            }
            
        case "RETRY_ACTION":
            // Retry the failed operation
            handleRetryAction()
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification (not an action button)
            openAppToRelevantScreen(userInfo: userInfo)
            
        default:
            break
        }
    }
    
    private func openAppToHistory() {
        // This would typically use a deep link or notification to navigate
        logger.info("📱 Opening app to history view")
    }
    
    private func handleDeviceConnection(deviceName: String) {
        Task {
            // Find and connect to the device
            logger.info("🤝 Attempting to connect to device: \(deviceName)")
        }
    }
    
    private func handleRetryAction() {
        Task {
            // Retry the last failed operation
            await SyncService.shared.refreshStatus()
            logger.info("🔄 Retrying last operation")
        }
    }
    
    private func openAppToRelevantScreen(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        
        switch type {
        case "sync", "clipboard_update":
            // Open to home screen
            break
        case "device_connected", "device_disconnected", "device_discovered":
            // Open to devices screen
            break
        case "error":
            // Open to settings or support screen
            break
        default:
            break
        }
        
        logger.info("📱 Opening app for notification type: \(type)")
    }
}

// MARK: - Supporting Types
struct NotificationStats {
    let hasPermission: Bool
    let authorizationStatus: Int
    let alertSetting: Int
    let soundSetting: Int
    let badgeSetting: Int
}
