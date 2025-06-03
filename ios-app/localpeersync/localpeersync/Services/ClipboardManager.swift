//
//  ClipboardManager.swift
//  LocalPeerSync - Background Ready (FIXED ACTOR ISSUES)
//

import Foundation
import UIKit
import os.log
import BackgroundTasks

@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    // MARK: - Published Properties
    @Published var currentContent: String = ""
    @Published var lastSyncTime: Date?
    @Published var syncCount: Int = 0
    @Published var isMonitoring: Bool = false
    @Published var backgroundSyncCount: Int = 0
    
    // MARK: - Private Properties
    private let pasteboard = UIPasteboard.general
    private var lastChangeCount: Int = 0
    private var monitoringTimer: Timer?
    private var ignoreNextChange = false
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ClipboardManager")
    
    // MARK: - Background Support
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastBackgroundSync: Date = Date()
    private var pendingClipboardChanges: [String] = []
    
    private init() {
        setupInitialState()
        setupBackgroundObservers()
    }
    
    // MARK: - Background Setup
    
    private func setupBackgroundObservers() {
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
        logger.info("📱 App entering background - starting extended background task")
        startBackgroundTask()
        
        // Cache current state for background processing
        if !currentContent.isEmpty {
            pendingClipboardChanges.append(currentContent)
        }
    }
    
    @objc private func appWillEnterForeground() {
        logger.info("📱 App entering foreground - processing pending changes")
        endBackgroundTask()
        
        // Process any pending changes
        processPendingChanges()
    }
    
    @objc private func appDidBecomeActive() {
        logger.info("📱 App became active - refreshing clipboard state")
        
        // Check for clipboard changes that happened while backgrounded
        checkForBackgroundClipboardChanges()
    }
    
    // FIXED: Make background task methods nonisolated
    nonisolated private func startBackgroundTask() {
        Task { @MainActor in
            await _startBackgroundTask()
        }
    }
    
    private func _startBackgroundTask() async {
        endBackgroundTaskSync() // End any existing task
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ClipboardSync") { [weak self] in
            self?.logger.warning("⏰ Background task expiring")
            Task { @MainActor in
                await self?._endBackgroundTask()
            }
        }
        
        if backgroundTask != .invalid {
            logger.info("✅ Background task started: \(self.backgroundTask.rawValue)")
        }
    }
    
    // FIXED: Make this nonisolated for deinit
    nonisolated private func endBackgroundTask() {
        Task { @MainActor in
            await _endBackgroundTask()
        }
    }
    
    // FIXED: Synchronous version for deinit
    private func endBackgroundTaskSync() {
        if backgroundTask != .invalid {
            logger.info("🛑 Ending background task: \(self.backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func _endBackgroundTask() async {
        endBackgroundTaskSync()
    }
    
    private func processPendingChanges() {
        guard !pendingClipboardChanges.isEmpty else { return }
        
        logger.info("🔄 Processing \(self.pendingClipboardChanges.count) pending clipboard changes")
        
        for change in pendingClipboardChanges {
            Task {
                let success = await SyncService.shared.syncClipboard(change)
                if success {
                    await MainActor.run {
                        self.backgroundSyncCount += 1
                    }
                }
            }
        }
        
        pendingClipboardChanges.removeAll()
    }
    
    private func checkForBackgroundClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            logger.info("📋 Clipboard changed while app was backgrounded")
            
            if let content = pasteboard.string, !content.isEmpty, content != currentContent {
                currentContent = content
                lastChangeCount = currentChangeCount
                
                Task {
                    let success = await SyncService.shared.syncClipboard(content)
                    if success {
                        await MainActor.run {
                            self.syncCount += 1
                            self.lastSyncTime = Date()
                        }
                    }
                }
            }
        }
    }
    
    private func requestClipboardPermission() async -> Bool {
        // For iOS 16+, we need to check clipboard access
        if #available(iOS 16.0, *) {
            // Test clipboard access by attempting to read
            let testString = "clipboard_test_\(UUID().uuidString)"
            
            // Try to write test string
            UIPasteboard.general.string = testString
            
            // Try to read it back
            if UIPasteboard.general.string == testString {
                logger.info("✅ Clipboard permission granted")
                return true
            } else {
                logger.error("❌ Clipboard permission denied")
                
                // Show user an alert to grant permission
                await MainActor.run {
                    // You could show an alert here explaining clipboard permission
                }
                return false
            }
        }
        
        return true // Older iOS versions don't need explicit permission
    }
    
    // MARK: - Clipboard Permission Check

    private func checkClipboardPermissions() -> Bool {
        // iOS 16+ requires permission for clipboard access
        if #available(iOS 16.0, *) {
            // Test clipboard access
            let testWrite = "test"
            UIPasteboard.general.string = testWrite
            
            if UIPasteboard.general.string == testWrite {
                logger.info("✅ Clipboard permissions granted")
                return true
            } else {
                logger.error("❌ Clipboard permissions denied")
                return false
            }
        } else {
            return true
        }
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() async {
        guard !isMonitoring else { return }
            
            // Check clipboard permission first
            let hasPermission = await requestClipboardPermission()
            guard hasPermission else {
                logger.error("❌ Cannot start monitoring - no clipboard permission")
                return
            }
            
            logger.info("🔍 Starting clipboard monitoring with background support")
        
        lastChangeCount = pasteboard.changeCount
        if let content = pasteboard.string {
            currentContent = content
        }
        
        // Start monitoring timer with background-aware interval
        let interval: TimeInterval = UIApplication.shared.applicationState == .active ? 0.5 : 2.0
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForClipboardChanges()
            }
        }
        
        isMonitoring = true
        logger.info("✅ Clipboard monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        logger.info("🛑 Stopping clipboard monitoring")
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        endBackgroundTask()
        
        logger.info("✅ Clipboard monitoring stopped")
    }
    
    /// Set clipboard content from network (called by FFI bridge)
    func setClipboardContentFromNetwork(_ content: String) {
        logger.info("📋 Setting clipboard content from network: \(content.prefix(50))...")
        
        ignoreNextChange = true
        pasteboard.string = content
        currentContent = content
        lastChangeCount = pasteboard.changeCount
        
        logger.info("✅ Clipboard content set from network")
        
        // Update stats
        backgroundSyncCount += 1
        lastSyncTime = Date()
    }
    
    /// Set clipboard content manually
    func setClipboardContent(_ content: String, source: String = "manual") {
        logger.info("📋 Setting clipboard content from \(source): \(content.prefix(50))...")
        
        ignoreNextChange = true
        pasteboard.string = content
        currentContent = content
        lastChangeCount = pasteboard.changeCount
        
        logger.info("✅ Clipboard content set successfully")
    }
    
    func syncCurrentContent() async -> Bool {
        guard !currentContent.isEmpty else {
            logger.warning("⚠️ No content to sync")
            return false
        }
        
        logger.info("📤 Manually syncing current clipboard content")
        
        // Start background task for sync operation
        startBackgroundTask()
        
        let success = await SyncService.shared.syncClipboard(currentContent)
        
        if success {
            syncCount += 1
            lastSyncTime = Date()
            logger.info("✅ Manual sync successful")
        } else {
            logger.error("❌ Manual sync failed")
        }
        
        endBackgroundTask()
        return success
    }
    
    // MARK: - Private Methods
    
    private func setupInitialState() {
        lastChangeCount = pasteboard.changeCount
        if let content = pasteboard.string {
            currentContent = content
        }
        logger.info("📋 Clipboard manager initialized with background support")
    }
    
    private func checkForClipboardChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        
        lastChangeCount = currentChangeCount
        
        if ignoreNextChange {
            ignoreNextChange = false
            logger.info("🔇 Ignoring clipboard change (set by network)")
            return
        }
        
        guard let newContent = pasteboard.string, !newContent.isEmpty else {
            logger.info("📋 Clipboard cleared or empty")
            currentContent = ""
            return
        }
        
        guard newContent != currentContent else { return }
        
        logger.info("📋 Clipboard changed: \(newContent.prefix(50))...")
        currentContent = newContent
        
        // Handle sync with background support
        if UIApplication.shared.applicationState == .active {
            // App is active - sync immediately
            Task {
                let success = await SyncService.shared.syncClipboard(newContent)
                
                await MainActor.run {
                    if success {
                        self.syncCount += 1
                        self.lastSyncTime = Date()
                        self.logger.info("✅ Clipboard sync successful")
                    } else {
                        self.logger.error("❌ Clipboard sync failed")
                    }
                }
            }
        } else {
            // App is backgrounded - queue for later
            logger.info("📱 App backgrounded - queuing clipboard change")
            pendingClipboardChanges.append(newContent)
            
            // Try immediate sync if we have background time
            if backgroundTask != .invalid {
                Task {
                    let success = await SyncService.shared.syncClipboard(newContent)
                    if success {
                        await MainActor.run {
                            self.backgroundSyncCount += 1
                            self.lastSyncTime = Date()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func getStats() -> ClipboardStats {
        return ClipboardStats(
            syncCount: syncCount,
            backgroundSyncCount: backgroundSyncCount,
            lastSyncTime: lastSyncTime,
            isMonitoring: isMonitoring,
            currentContentLength: currentContent.count
        )
    }
    
    func resetStats() {
        syncCount = 0
        backgroundSyncCount = 0
        lastSyncTime = nil
        logger.info("📊 Clipboard statistics reset")
    }
    
    func getCurrentContentPreview(maxLength: Int = 100) -> String {
        if currentContent.isEmpty {
            return "No content"
        }
        
        if currentContent.count <= maxLength {
            return currentContent
        }
        
        return String(currentContent.prefix(maxLength)) + "..."
    }
    
    func copyText(_ text: String) {
        setClipboardContent(text, source: "manual")
    }
    
    func clearClipboard() {
        pasteboard.string = ""
        currentContent = ""
        lastChangeCount = pasteboard.changeCount
        logger.info("🗑️ Clipboard cleared")
    }
    
    func cleanup() {
        stopMonitoring()
        endBackgroundTask()
        NotificationCenter.default.removeObserver(self)
    }
    
    // FIXED: Remove main actor calls from deinit
    deinit {
        monitoringTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        
        // FIXED: Use nonisolated cleanup
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        
        logger.info("🧹 ClipboardManager deinitialized")
    }
}

// MARK: - Supporting Types

struct ClipboardStats {
    let syncCount: Int
    let backgroundSyncCount: Int
    let lastSyncTime: Date?
    let isMonitoring: Bool
    let currentContentLength: Int
    
    var description: String {
        var info = ["=== Clipboard Stats ==="]
        info.append("Monitoring: \(isMonitoring ? "Active" : "Inactive")")
        info.append("Sync Count: \(syncCount)")
        info.append("Background Syncs: \(backgroundSyncCount)")
        info.append("Content Length: \(currentContentLength) characters")
        
        if let lastSync = lastSyncTime {
            info.append("Last Sync: \(lastSync.formatted(.dateTime))")
        } else {
            info.append("Last Sync: Never")
        }
        
        return info.joined(separator: "\n")
    }
}
