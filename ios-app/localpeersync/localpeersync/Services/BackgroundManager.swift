//
//  BackgroundManager.swift
//  LocalPeerSync
//
//  Advanced iOS background processing
//

import Foundation
import BackgroundTasks
import UIKit
import os.log

@MainActor
class BackgroundManager: ObservableObject {
    static let shared = BackgroundManager()
    
    // MARK: - Background Task Identifiers
    private let syncTaskIdentifier = "com.localpeersync.ios.sync"
    private let clipboardTaskIdentifier = "com.localpeersync.ios.clipboardcheck"
    
    // MARK: - Published Properties
    @Published var backgroundSyncEnabled: Bool = true
    @Published var lastBackgroundSync: Date?
    @Published var backgroundSyncCount: Int = 0
    @Published var backgroundTasksRegistered: Bool = false
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "BackgroundManager")
    private var backgroundSyncTimer: Timer?
    private var activeBackgroundTasks: Set<UIBackgroundTaskIdentifier> = []
    
    // MARK: - Initialization
    private init() {
        setupBackgroundNotifications()
    }
    
    // MARK: - Public Background Task Handlers (for external registration)
    public func handleBackgroundSync(task: BGAppRefreshTask) async {
        logger.info("🔄 Starting background sync task")
        
        // Schedule next refresh
        scheduleAppRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            self.logger.warning("⏰ Background sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        do {
            // Perform quick sync operations
            await performQuickSync()
            
            // Update last sync time
            lastBackgroundSync = Date()
            backgroundSyncCount += 1
            
            task.setTaskCompleted(success: true)
            logger.info("✅ Background sync completed successfully")
            
            // Send success notification
            await sendBackgroundSyncNotification(success: true)
            
        } catch {
            logger.error("❌ Background sync failed: \(error)")
            task.setTaskCompleted(success: false)
            
            // Send failure notification
            await sendBackgroundSyncNotification(success: false, error: error)
        }
    }

    public func handleClipboardCheck(task: BGProcessingTask) async {
        logger.info("📋 Starting background clipboard check")
        
        // Schedule next processing task
        scheduleProcessingTask()
        
        task.expirationHandler = {
            self.logger.warning("⏰ Clipboard check task expired")
            task.setTaskCompleted(success: false)
        }
        
        do {
            // Check clipboard changes
            ClipboardManager.shared.checkClipboardChanges()
            
            // Perform extended sync operations
            await performExtendedSync()
            
            task.setTaskCompleted(success: true)
            logger.info("✅ Background clipboard check completed")
            
        } catch {
            logger.error("❌ Background clipboard check failed: \(error)")
            task.setTaskCompleted(success: false)
        }
    }
    
    // MARK: - Background Task Registration
    func registerBackgroundTasks() {
        // Register app refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: syncTaskIdentifier,
            using: nil
        ) { task in
            Task {
                await self.handleBackgroundSync(task: task as! BGAppRefreshTask)
            }
        }
        
        // Register processing task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: clipboardTaskIdentifier,
            using: nil
        ) { task in
            Task {
                await self.handleClipboardCheck(task: task as! BGProcessingTask)
            }
        }
        
        // Update this synchronously since we're in init()
        DispatchQueue.main.async {
            self.backgroundTasksRegistered = true
        }
        
        logger.info("📱 Registered background tasks successfully")
    }
    
    // MARK: - Background Task Scheduling
    func scheduleBackgroundTasks() {
        scheduleAppRefresh()
        scheduleProcessingTask()
    }
    
    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("📅 Scheduled background app refresh")
        } catch {
            logger.error("❌ Failed to schedule app refresh: \(error)")
        }
    }
    
    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: clipboardTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("📅 Scheduled background processing task")
        } catch {
            logger.error("❌ Failed to schedule processing task: \(error)")
        }
    }
    
    // MARK: - Background Operations
    private func performQuickSync() async {
        // Quick operations that can complete in ~30 seconds
        
        // 1. Check clipboard changes
        ClipboardManager.shared.checkClipboardChanges()
        
        // 2. Refresh peer connections
        await SyncService.shared.refreshConnections()
        
        // 3. Sync any pending clipboard content
        if SyncService.shared.isRunning {
            await SyncService.shared.refreshStatus()
        }
        
        logger.info("⚡ Quick sync operations completed")
    }
    
    private func performExtendedSync() async {
        // Extended operations for processing task
        
        // 1. Full peer discovery
        await SyncService.shared.scanForDevices()
        
        // 2. Sync clipboard history
        await syncClipboardHistory()
        
        // 3. Clean up old data
        await cleanupOldData()
        
        // 4. Update statistics
        await updateStatistics()
        
        logger.info("🔄 Extended sync operations completed")
    }
    
    private func syncClipboardHistory() async {
        // Sync recent clipboard items that might have been missed
        let recentItems = ClipboardManager.shared.recentItems.prefix(5)
        
        for item in recentItems {
            if SyncService.shared.isRunning {
                SyncService.shared.syncClipboard(item.content)
                
                // Small delay between syncs
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }
    
    private func cleanupOldData() async {
        // Clean up old clipboard items
        let oldItemsThreshold = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days
        
        let oldItems = ClipboardManager.shared.allItems.filter { item in
            item.timestamp < oldItemsThreshold && !item.isFavorite
        }
        
        for item in oldItems {
            ClipboardManager.shared.deleteItem(item)
        }
        
        if !oldItems.isEmpty {
            logger.info("🧹 Cleaned up \(oldItems.count) old clipboard items")
        }
    }
    
    private func updateStatistics() async {
        // Update app statistics and save state
        ClipboardManager.shared.saveCurrentState()
        
        // Log statistics
        logger.info("📊 Background statistics update completed")
    }
    
    // MARK: - Foreground Background Tasks
    func beginBackgroundTask(name: String, completion: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
            completion()
            // Use the actual task ID instead of accessing a non-existent property
            if let validTaskId = self.activeBackgroundTasks.first {
                self.endBackgroundTask(taskId: validTaskId)
            }
        }
        
        activeBackgroundTasks.insert(taskId)
        logger.info("🎯 Started background task: \(name)")
        
        return taskId
    }

    func endBackgroundTask(taskId: UIBackgroundTaskIdentifier) {
        guard taskId != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(taskId)
        activeBackgroundTasks.remove(taskId)
        
        logger.info("✅ Ended background task")
    }
    
    func endAllBackgroundTasks() {
        for taskId in activeBackgroundTasks {
            UIApplication.shared.endBackgroundTask(taskId)
        }
        activeBackgroundTasks.removeAll()
        
        logger.info("🛑 Ended all background tasks")
    }
    
    // MARK: - Notifications
    private func sendBackgroundSyncNotification(success: Bool, error: Error? = nil) async {
        guard UserDefaults.standard.bool(forKey: "backgroundNotificationsEnabled") else { return }
        
        let content = UNMutableNotificationContent()
        
        if success {
            content.title = "Background Sync Complete"
            content.body = "Your clipboard has been synced with \(SyncService.shared.connectedPeers.count) devices"
            content.sound = .default
        } else {
            content.title = "Background Sync Failed"
            content.body = error?.localizedDescription ?? "An unknown error occurred"
            content.sound = .defaultCritical
        }
        
        let request = UNNotificationRequest(
            identifier: "background-sync-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - App Lifecycle
    private func setupBackgroundNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("📱 App entered background - scheduling tasks")
        scheduleBackgroundTasks()
        
        // Start a background task to finish any pending operations
        let taskId = beginBackgroundTask(name: "EnterBackground") {
            // Completion handler
        }
        
        Task { @MainActor in
            // Save current state
            ClipboardManager.shared.saveCurrentState()
            
            // Give sync service a chance to finish pending operations
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            endBackgroundTask(taskId: taskId)
        }
    }

    @objc private func appWillEnterForeground() {
        logger.info("📱 App will enter foreground")
        
        // Cancel any pending background tasks if we're about to be active
        BGTaskScheduler.shared.cancelAllTaskRequests()
        
        // End any active background tasks immediately (since we're already on MainActor)
        endAllBackgroundTasks()
        
        // Refresh app state asynchronously
        Task {
            await SyncService.shared.refreshStatus()
            ClipboardManager.shared.checkClipboardChanges()
        }
    }
    
    // MARK: - Debug Methods
    func simulateBackgroundSync() {
        Task {
            logger.info("🧪 Simulating background sync")
            await performQuickSync()
            await sendBackgroundSyncNotification(success: true)
        }
    }
    
    func getBackgroundTaskStatus() -> String {
        return """
        Background Tasks Registered: \(backgroundTasksRegistered)
        Active Background Tasks: \(activeBackgroundTasks.count)
        Last Background Sync: \(lastBackgroundSync?.timeAgoDisplay ?? "Never")
        Background Sync Count: \(backgroundSyncCount)
        """
    }
    
    deinit {
        logger.info("🧹 BackgroundManager deinitializing")
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Background Task Errors
enum BackgroundTaskError: LocalizedError {
    case taskExpired
    case networkUnavailable
    case syncServiceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .taskExpired:
            return "Background task expired before completion"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .syncServiceUnavailable:
            return "Sync service is not running"
        }
    }
}
