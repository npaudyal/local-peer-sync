//
//  BackgroundManager.swift
//  LocalPeerSync
//
//  ENHANCED iOS background processing - FIXED compilation errors
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
    @Published var backgroundErrors: Int = 0
    @Published var backgroundSuccesses: Int = 0
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "BackgroundManager")
    private var backgroundSyncTimer: Timer?
    private var activeBackgroundTasks: Set<UIBackgroundTaskIdentifier> = []
    private var lastBackgroundError: String?
    
    // MARK: - Initialization
    private init() {
        setupEnhancedBackgroundNotifications()
    }
    
    // MARK: - Enhanced Background Task Handlers
    public func handleBackgroundSync(task: BGAppRefreshTask) async {
        logger.info("🔄 Starting ENHANCED background sync task")
        
        // Schedule next refresh
        scheduleAppRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            self.logger.warning("⏰ ENHANCED background sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        // 🔧 FIXED: Use do-catch for error handling
        do {
            // Perform enhanced sync operations
            try await performEnhancedQuickSync()
            
            // Update metrics
            lastBackgroundSync = Date()
            backgroundSyncCount += 1
            backgroundSuccesses += 1
            
            task.setTaskCompleted(success: true)
            logger.info("✅ ENHANCED background sync completed successfully")
            
            // Send success notification
            await sendBackgroundSyncNotification(success: true)
            
        } catch {
            backgroundErrors += 1
            lastBackgroundError = error.localizedDescription
            logger.error("❌ ENHANCED background sync failed: \(error)")
            task.setTaskCompleted(success: false)
            
            // Send failure notification
            await sendBackgroundSyncNotification(success: false, error: error)
        }
    }

    public func handleClipboardCheck(task: BGProcessingTask) async {
        logger.info("📋 Starting ENHANCED background clipboard check")
        
        // Schedule next processing task
        scheduleProcessingTask()
        
        task.expirationHandler = {
            self.logger.warning("⏰ ENHANCED clipboard check task expired")
            task.setTaskCompleted(success: false)
        }
        
        // 🔧 FIXED: Use do-catch for error handling
        do {
            // Check clipboard changes
            ClipboardManager.shared.checkClipboardChanges()
            
            // Perform extended sync operations
            try await performEnhancedExtendedSync()
            
            task.setTaskCompleted(success: true)
            logger.info("✅ ENHANCED background clipboard check completed")
            
        } catch {
            backgroundErrors += 1
            lastBackgroundError = error.localizedDescription
            logger.error("❌ ENHANCED background clipboard check failed: \(error)")
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
        
        backgroundTasksRegistered = true
        logger.info("📱 ENHANCED background tasks registered successfully")
    }
    
    // MARK: - Background Task Scheduling
    func scheduleBackgroundTasks() {
        scheduleAppRefresh()
        scheduleProcessingTask()
        logger.info("📅 ENHANCED background tasks scheduled")
    }
    
    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("📅 Scheduled ENHANCED background app refresh")
        } catch {
            logger.error("❌ Failed to schedule ENHANCED app refresh: \(error)")
            backgroundErrors += 1
        }
    }
    
    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: clipboardTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("📅 Scheduled ENHANCED background processing task")
        } catch {
            logger.error("❌ Failed to schedule ENHANCED processing task: \(error)")
            backgroundErrors += 1
        }
    }
    
    // MARK: - 🔧 FIXED: Enhanced Background Operations (now throws)
    private func performEnhancedQuickSync() async throws {
        logger.info("⚡ Starting ENHANCED quick sync operations")
        
        // 1. Check clipboard changes with retry
        for attempt in 1...3 {
            do {
                ClipboardManager.shared.checkClipboardChanges()
                logger.info("✅ Clipboard check successful on attempt \(attempt)")
                break
            } catch {
                logger.warning("⚠️ Clipboard check failed on attempt \(attempt): \(error)")
                if attempt == 3 {
                    throw error
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        // 2. Refresh peer connections with validation
        if SyncService.shared.isRunning {
            await SyncService.shared.refreshConnections()
            logger.info("✅ Peer connections refreshed")
        } else {
            logger.info("ℹ️ Sync service not running, attempting restart")
            SyncService.shared.startSync()
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        // 3. Validate sync service health
        await validateSyncServiceHealth()
        
        // 4. Process any pending clipboard syncs
        if SyncService.shared.isRunning {
            await SyncService.shared.refreshStatus()
            logger.info("✅ Sync status refreshed")
        }
        
        logger.info("⚡ ENHANCED quick sync operations completed")
    }
    
    private func performEnhancedExtendedSync() async throws {
        logger.info("🔄 Starting ENHANCED extended sync operations")
        
        // 1. Full peer discovery with retry
        for attempt in 1...2 {
            await SyncService.shared.scanForDevices()
            logger.info("✅ Device scan completed on attempt \(attempt)")
            
            if attempt < 2 {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            }
        }
        
        // 2. Enhanced clipboard history sync
        await syncEnhancedClipboardHistory()
        
        // 3. Clean up old data with metrics
        await cleanupOldDataEnhanced()
        
        // 4. Update enhanced statistics
        await updateEnhancedStatistics()
        
        // 5. Validate overall system health
        await performSystemHealthCheck()
        
        logger.info("🔄 ENHANCED extended sync operations completed")
    }
    
    private func syncEnhancedClipboardHistory() async {
        logger.info("📚 Syncing ENHANCED clipboard history")
        
        let recentItems = ClipboardManager.shared.recentItems.prefix(3)
        
        for (index, item) in recentItems.enumerated() {
            if SyncService.shared.isRunning {
                SyncService.shared.syncClipboard(item.content)
                logger.info("✅ Synced history item \(index + 1)/\(recentItems.count)")
                
                // Small delay between syncs
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            } else {
                logger.warning("⚠️ Sync service not running, stopping history sync")
                break
            }
        }
    }
    
    private func cleanupOldDataEnhanced() async {
        logger.info("🧹 Starting ENHANCED data cleanup")
        
        let oldItemsThreshold = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days
        
        let oldItems = ClipboardManager.shared.allItems.filter { item in
            item.timestamp < oldItemsThreshold && !item.isFavorite
        }
        
        var cleanedCount = 0
        for item in oldItems.prefix(10) {
            ClipboardManager.shared.deleteItem(item)
            cleanedCount += 1
        }
        
        if cleanedCount > 0 {
            logger.info("🧹 ENHANCED cleanup removed \(cleanedCount) old clipboard items")
        }
    }
    
    private func updateEnhancedStatistics() async {
        logger.info("📊 Updating ENHANCED statistics")
        ClipboardManager.shared.saveCurrentState()
        
        let diagnostics = ClipboardManager.shared.getDiagnostics()
        logger.info("📊 ENHANCED statistics: \(diagnostics)")
    }
    
    private func validateSyncServiceHealth() async {
        logger.info("🏥 Validating ENHANCED sync service health")
        
        guard SyncService.shared.isRunning else {
            logger.warning("⚠️ Sync service not running")
            return
        }
        
        if SyncService.shared.localIPAddress.isEmpty || SyncService.shared.localIPAddress == "Unknown" {
            logger.warning("⚠️ No valid network connection")
            return
        }
        
        let peerCount = SyncService.shared.connectedPeers.count + SyncService.shared.discoveredPeers.count
        logger.info("🏥 Health check: \(peerCount) total peers, service running: \(SyncService.shared.isRunning)")
    }
    
    private func performSystemHealthCheck() async {
        logger.info("🔍 Performing ENHANCED system health check")
        
        let healthMetrics = [
            "sync_service_running": SyncService.shared.isRunning,
            "clipboard_monitoring": ClipboardManager.shared.isMonitoring,
            "connected_peers": SyncService.shared.connectedPeers.count,
            "discovered_peers": SyncService.shared.discoveredPeers.count,
            "background_sync_count": backgroundSyncCount,
            "background_error_count": backgroundErrors
        ] as [String : Any]
        
        logger.info("🔍 ENHANCED health metrics: \(healthMetrics)")
    }
    
    // MARK: - Foreground Background Tasks
    func beginBackgroundTask(name: String, completion: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
            completion()
            if let validTaskId = self.activeBackgroundTasks.first {
                self.endBackgroundTask(taskId: validTaskId)
            }
        }
        
        activeBackgroundTasks.insert(taskId)
        logger.info("🎯 Started ENHANCED background task: \(name)")
        
        return taskId
    }

    func endBackgroundTask(taskId: UIBackgroundTaskIdentifier) {
        guard taskId != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(taskId)
        activeBackgroundTasks.remove(taskId)
        
        logger.info("✅ Ended ENHANCED background task")
    }
    
    func endAllBackgroundTasks() {
        for taskId in activeBackgroundTasks {
            UIApplication.shared.endBackgroundTask(taskId)
        }
        activeBackgroundTasks.removeAll()
        
        logger.info("🛑 Ended all ENHANCED background tasks")
    }
    
    // MARK: - Notifications
    private func sendBackgroundSyncNotification(success: Bool, error: Error? = nil) async {
        guard UserDefaults.standard.bool(forKey: "backgroundNotificationsEnabled") else { return }
        
        let content = UNMutableNotificationContent()
        
        if success {
            content.title = "Background Sync Complete"
            content.body = "LocalPeerSync synced with \(SyncService.shared.connectedPeers.count) devices"
            content.sound = .default
        } else {
            content.title = "Background Sync Issue"
            content.body = error?.localizedDescription ?? "Background sync encountered an issue"
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
    private func setupEnhancedBackgroundNotifications() {
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
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("📱 App entered background - ENHANCED handling")
        scheduleBackgroundTasks()
        
        let taskId = beginBackgroundTask(name: "EnhancedEnterBackground") {
            // Completion handler
        }
        
        Task { @MainActor in
            ClipboardManager.shared.saveCurrentState()
            
            if SyncService.shared.isRunning {
                logger.info("🔄 Attempting to maintain discovery in background")
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
            
            endBackgroundTask(taskId: taskId)
        }
    }

    @objc private func appWillEnterForeground() {
        logger.info("📱 App will enter foreground - ENHANCED handling")
        
        BGTaskScheduler.shared.cancelAllTaskRequests()
        endAllBackgroundTasks()
        
        Task {
            if !SyncService.shared.isRunning && backgroundSyncEnabled {
                logger.info("🔄 Restarting sync service from background")
                SyncService.shared.startSync()
            }
            
            await SyncService.shared.refreshStatus()
            ClipboardManager.shared.checkClipboardChanges()
        }
    }
    
    @objc private func appDidBecomeActive() {
        logger.info("📱 App became active - ENHANCED handling")
        
        Task {
            await performSystemHealthCheck()
        }
    }
    
    // MARK: - Debug Methods
    func simulateBackgroundSync() {
        Task {
            logger.info("🧪 Simulating ENHANCED background sync")
            try? await performEnhancedQuickSync()
            await sendBackgroundSyncNotification(success: true)
        }
    }
    
    func getEnhancedBackgroundTaskStatus() -> String {
        return """
        === ENHANCED Background Task Status ===
        Tasks Registered: \(backgroundTasksRegistered)
        Active Tasks: \(activeBackgroundTasks.count)
        Last Background Sync: \(lastBackgroundSync?.timeAgoDisplay ?? "Never")
        Background Sync Count: \(backgroundSyncCount)
        Background Successes: \(backgroundSuccesses)
        Background Errors: \(backgroundErrors)
        Last Error: \(lastBackgroundError ?? "None")
        Sync Enabled: \(backgroundSyncEnabled)
        """
    }
    
    func resetBackgroundMetrics() {
        backgroundSyncCount = 0
        backgroundSuccesses = 0
        backgroundErrors = 0
        lastBackgroundError = nil
        lastBackgroundSync = nil
        logger.info("🔄 Reset ENHANCED background metrics")
    }
    
    deinit {
        logger.info("🧹 ENHANCED BackgroundManager deinitializing")
        NotificationCenter.default.removeObserver(self)
    }
}
