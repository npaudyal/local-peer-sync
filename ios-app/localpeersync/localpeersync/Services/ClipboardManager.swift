//
//  ClipboardManager.swift
//  LocalPeerSync
//
//  ENHANCED iOS clipboard management - FIXED compilation errors
//

import Foundation
import UIKit
import UserNotifications
import UniformTypeIdentifiers
import os.log

@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    // MARK: - Published Properties
    @Published var allItems: [ClipboardItem] = []
    @Published var recentItems: [ClipboardItem] = []
    @Published var favoriteItems: [ClipboardItem] = []
    @Published var unreadCount: Int = 0
    @Published var totalSyncCount: Int = 0
    @Published var lastClipboardContent: String = ""
    @Published var isMonitoring: Bool = false
    @Published var rustClipboardEnabled: Bool = true
    @Published var syncSuccessCount: Int = 0
    @Published var syncFailureCount: Int = 0
    
    // MARK: - Private Properties
    private let pasteboard = UIPasteboard.general
    private var lastChangeCount: Int = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ClipboardManager")
    private let maxHistorySize = 200
    private var ignoreNextChange = false
    private var isHandlingRustUpdate = false
    private var lastSyncAttempt: Date?
    
    // MARK: - Enhanced Properties
    private var clipboardCheckTimer: Timer?
    private var syncRetryQueue: [String] = []
    private var maxRetries = 3
    
    // MARK: - Storage
    private let userDefaults = UserDefaults.standard
    private let historyKey = "ClipboardHistory"
    private let statsKey = "ClipboardStats"
    
    // MARK: - Initialization
    private init() {
        loadStoredHistory()
        setupEnhancedClipboardMonitoring()
        loadStatistics()
        setupSyncRetryMechanism()
    }
    
    // MARK: - Enhanced Setup
    private func setupEnhancedClipboardMonitoring() {
        lastChangeCount = pasteboard.changeCount
        if let content = pasteboard.string {
            lastClipboardContent = content
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        logger.info("🔍 ENHANCED clipboard monitoring setup complete")
    }
    
    private func setupSyncRetryMechanism() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processSyncRetryQueue()
            }
        }
    }
    
    // MARK: - Public Methods
    func syncServiceDidStart() {
        startEnhancedMonitoring()
    }
    
    func syncServiceDidStop() {
        stopEnhancedMonitoring()
    }
    
    private func startEnhancedMonitoring() {
        guard !isMonitoring else { return }
        
        lastChangeCount = pasteboard.changeCount
        if let content = pasteboard.string {
            lastClipboardContent = content
        }
        
        clipboardCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboardChanges()
            }
        }
        
        isMonitoring = true
        logger.info("🔍 Started ENHANCED clipboard monitoring")
    }
    
    private func stopEnhancedMonitoring() {
        guard isMonitoring else { return }
        
        clipboardCheckTimer?.invalidate()
        clipboardCheckTimer = nil
        
        NotificationCenter.default.removeObserver(self)
        isMonitoring = false
        logger.info("🛑 Stopped ENHANCED clipboard monitoring")
    }
    
    func checkClipboardChanges() {
        guard !isHandlingRustUpdate else { return }
        
        let currentChangeCount = pasteboard.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        
        lastChangeCount = currentChangeCount
        
        if let newContent = getCurrentClipboardContent(),
           newContent.content != lastClipboardContent,
           !ignoreNextChange {
            
            lastClipboardContent = newContent.content
            processNewClipboardContent(newContent)
        }
        
        ignoreNextChange = false
    }
    
    func saveCurrentState() {
        saveHistoryToStorage()
        saveEnhancedStatistics()
    }
    
    // MARK: - Enhanced Rust Integration
    
    func handleRustClipboardUpdate(_ content: String, source: String) {
        isHandlingRustUpdate = true
        defer { isHandlingRustUpdate = false }
        
        logger.info("📋 Handling ENHANCED Rust clipboard update from \(source)")
        
        lastClipboardContent = content
        lastChangeCount = pasteboard.changeCount
        
        let clipboardContent = ClipboardContent(
            content: content,
            type: .text,
            size: content.utf8.count,
            timestamp: Date(),
            sourceDevice: source
        )
        
        processNewClipboardContent(clipboardContent)
        
        logger.info("📋 ENHANCED Rust clipboard update processed: \(content.prefix(50))...")
    }
    
    func handleRustImageUpdate(_ image: UIImage, source: String) {
        isHandlingRustUpdate = true
        defer { isHandlingRustUpdate = false }
        
        lastChangeCount = pasteboard.changeCount
        
        let clipboardContent = ClipboardContent(
            content: "Image (\(Int(image.size.width))x\(Int(image.size.height)))",
            type: .image,
            size: Int(image.size.width * image.size.height * 4),
            timestamp: Date(),
            sourceDevice: source,
            imageData: image.pngData()
        )
        
        processNewClipboardContent(clipboardContent)
        
        logger.info("📋 ENHANCED Rust image update processed from \(source)")
    }
    
    func handleRustURLUpdate(_ url: String, source: String) {
        isHandlingRustUpdate = true
        defer { isHandlingRustUpdate = false }
        
        lastClipboardContent = url
        lastChangeCount = pasteboard.changeCount
        
        let clipboardContent = ClipboardContent(
            content: url,
            type: .url,
            size: url.utf8.count,
            timestamp: Date(),
            sourceDevice: source
        )
        
        processNewClipboardContent(clipboardContent)
        
        logger.info("📋 ENHANCED Rust URL update processed: \(url)")
    }
    
    // MARK: - 🔧 FIXED: Enhanced Sync Mechanism
    
    private func notifyRustOfClipboardChange(_ content: String, type: ClipboardContentType = .text) {
        guard rustClipboardEnabled else { return }
        
        lastSyncAttempt = Date()
        
        Task {
            // Check if sync service is running
            guard SyncService.shared.isRunning else {
                logger.info("📋 Sync service not running, queuing for retry...")
                addToSyncRetryQueue(content)
                return
            }
            
            let success = await SyncService.shared.notifyClipboardChange(content: content, type: type)
            
            await MainActor.run {
                if success {
                    self.syncSuccessCount += 1
                    self.logger.info("✅ ENHANCED clipboard sync successful")
                } else {
                    self.syncFailureCount += 1
                    self.logger.error("❌ ENHANCED clipboard sync failed, queuing for retry")
                    self.addToSyncRetryQueue(content)
                }
            }
        }
    }
    
    private func addToSyncRetryQueue(_ content: String) {
        if syncRetryQueue.count < 10 {
            syncRetryQueue.append(content)
            logger.info("📋 Added to sync retry queue: \(self.syncRetryQueue.count) items")
        }
    }
    
    private func processSyncRetryQueue() async {
        // Check if we have items to retry and service is running
        guard !syncRetryQueue.isEmpty && SyncService.shared.isRunning else { return }
        
        let contentToRetry = syncRetryQueue.removeFirst()
        logger.info("📋 Retrying sync from queue: \(contentToRetry.prefix(30))...")
        
        let success = await SyncService.shared.notifyClipboardChange(content: contentToRetry, type: .text)
        
        if success {
            syncSuccessCount += 1
            logger.info("✅ Retry sync successful")
        } else {
            syncFailureCount += 1
            logger.error("❌ Retry sync failed")
            
            if syncRetryQueue.count < 5 {
                syncRetryQueue.append(contentToRetry)
            }
        }
    }
    
    // MARK: - Clipboard Operations
    func copyItem(_ item: ClipboardItem) {
        setClipboardContent(item.content, source: "history")
        markItemAsRead(item)
        HapticFeedback.success()
        
        logger.info("📋 Copied item from history: \(item.displayContent.prefix(50))")
    }
    
    func setClipboardContent(_ content: String, source: String = "network") {
        ignoreNextChange = true
        
        pasteboard.string = content
        lastClipboardContent = content
        lastChangeCount = pasteboard.changeCount
        
        logger.info("📋 Set clipboard content from \(source): \(content.prefix(50))...")
    }
    
    func addTextToClipboard(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        pasteboard.string = trimmedText
        
        let clipboardContent = ClipboardContent(
            content: trimmedText,
            type: .text,
            size: trimmedText.utf8.count,
            timestamp: Date(),
            sourceDevice: UIDevice.current.name
        )
        
        processNewClipboardContent(clipboardContent)
        notifyRustOfClipboardChange(trimmedText, type: .text)
        
        HapticFeedback.success()
        logger.info("📝 Added text to clipboard manually")
    }
    
    // MARK: - History Management
    func deleteItem(_ item: ClipboardItem) {
        allItems.removeAll { $0.id == item.id }
        recentItems.removeAll { $0.id == item.id }
        favoriteItems.removeAll { $0.id == item.id }
        
        saveHistoryToStorage()
        HapticFeedback.light()
        
        logger.info("🗑️ Deleted clipboard item")
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        if let index = allItems.firstIndex(where: { $0.id == item.id }) {
            allItems[index].isFavorite.toggle()
            
            if allItems[index].isFavorite {
                favoriteItems.append(allItems[index])
            } else {
                favoriteItems.removeAll { $0.id == item.id }
            }
            
            saveHistoryToStorage()
            HapticFeedback.light()
        }
    }
    
    func markItemAsRead(_ item: ClipboardItem) {
        if let index = allItems.firstIndex(where: { $0.id == item.id }) {
            if !allItems[index].isRead {
                allItems[index].isRead = true
                unreadCount = max(0, unreadCount - 1)
                saveHistoryToStorage()
            }
        }
    }
    
    func clearAllHistory() {
        allItems.removeAll()
        recentItems.removeAll()
        favoriteItems.removeAll()
        unreadCount = 0
        
        saveHistoryToStorage()
        
        logger.info("🧹 Cleared all clipboard history")
    }
    
    func shareItem(_ item: ClipboardItem) {
        let activityVC = UIActivityViewController(
            activityItems: [item.content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
    
    func exportHistory() {
        let historyData = allItems.map { item in
            [
                "content": item.content,
                "type": item.type.rawValue,
                "timestamp": item.timestamp.ISO8601String(),
                "sourceDevice": item.sourceDevice,
                "isFavorite": item.isFavorite
            ]
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: historyData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            
            let activityVC = UIActivityViewController(
                activityItems: [jsonString],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        }
    }
    
    func importHistory() {
        logger.info("📥 Import history requested")
    }
    
    // MARK: - Enhanced Diagnostics
    
    func getDiagnostics() -> [String: Any] {
        return [
            "monitoring": isMonitoring,
            "total_items": allItems.count,
            "sync_success_count": syncSuccessCount,
            "sync_failure_count": syncFailureCount,
            "retry_queue_size": syncRetryQueue.count,
            "last_sync_attempt": lastSyncAttempt?.timeIntervalSince1970 ?? 0,
            "rust_enabled": rustClipboardEnabled,
            "last_change_count": lastChangeCount
        ]
    }
    
    // MARK: - Private Methods
    
    @objc private func appDidBecomeActive() {
        checkClipboardChanges()
        
        Task {
            await processSyncRetryQueue()
        }
    }
    
    @objc private func appWillResignActive() {
        scheduleBackgroundClipboardCheck()
    }
    
    private func scheduleBackgroundClipboardCheck() {
        let currentTask = backgroundTask
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ClipboardCheck") { [weak self] in
            self?.endBackgroundTask()
        }
        
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkClipboardChanges()
                self?.endBackgroundTask()
            }
        }
    }
    
    nonisolated private func endBackgroundTask() {
        Task { @MainActor in
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }
    
    private func getCurrentClipboardContent() -> ClipboardContent? {
        // Try different content types
        
        // 1. Images
        if let image = pasteboard.image {
            if let imageData = image.pngData() {
                return ClipboardContent(
                    content: "Image (\(Int(image.size.width))x\(Int(image.size.height)))",
                    type: .image,
                    size: imageData.count,
                    timestamp: Date(),
                    sourceDevice: UIDevice.current.name,
                    imageData: imageData
                )
            }
        }
        
        // 2. URLs
        if let url = pasteboard.url {
            return ClipboardContent(
                content: url.absoluteString,
                type: .url,
                size: url.absoluteString.utf8.count,
                timestamp: Date(),
                sourceDevice: UIDevice.current.name
            )
        }
        
        // 3. Plain text
        if let text = pasteboard.string, !text.isEmpty {
            let type: ClipboardItemType = isURL(text) ? .url : .text
            return ClipboardContent(
                content: text,
                type: type,
                size: text.utf8.count,
                timestamp: Date(),
                sourceDevice: UIDevice.current.name
            )
        }
        
        return nil
    }
    
    func processNewClipboardContent(_ content: ClipboardContent) {
        let clipboardItem = ClipboardItem(
            content: content.content,
            type: content.type,
            size: content.size,
            timestamp: content.timestamp,
            sourceDevice: content.sourceDevice,
            imageData: content.imageData
        )
        
        // Add to collections
        allItems.insert(clipboardItem, at: 0)
        recentItems.insert(clipboardItem, at: 0)
        
        // Maintain size limits
        if allItems.count > maxHistorySize {
            allItems.removeLast()
        }
        
        if recentItems.count > 10 {
            recentItems.removeLast()
        }
        
        // Update counters
        if !clipboardItem.isRead {
            unreadCount += 1
        }
        totalSyncCount += 1
        
        // Save to storage
        saveHistoryToStorage()
        
        // Notify Rust if this is a local change
        if content.sourceDevice == UIDevice.current.name && !isHandlingRustUpdate {
            let contentType = determineContentType(content.content, type: content.type)
            notifyRustOfClipboardChange(content.content, type: contentType)
        }
        
        // Send notification if app is in background
        if UIApplication.shared.applicationState == .background {
            sendClipboardNotification(content: content.content)
        }
        
        logger.info("📋 ENHANCED clipboard content processed: \(clipboardItem.type.rawValue)")
    }
    
    private func determineContentType(_ content: String, type: ClipboardItemType) -> ClipboardContentType {
        switch type {
        case .url:
            return .url
        case .image:
            return .image
        default:
            return .text
        }
    }
    
    private func isURL(_ text: String) -> Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)
        return detector?.firstMatch(in: text, options: [], range: range) != nil
    }
    
    private func sendClipboardNotification(content: String) {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Clipboard Updated"
        notificationContent.body = "New content: \(String(content.prefix(50)))..."
        notificationContent.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Storage
    private func saveHistoryToStorage() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(allItems)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            logger.error("Failed to save clipboard history: \(error)")
        }
    }
    
    private func loadStoredHistory() {
        guard let data = userDefaults.data(forKey: historyKey) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            allItems = try decoder.decode([ClipboardItem].self, from: data)
            
            recentItems = Array(allItems.prefix(10))
            favoriteItems = allItems.filter { $0.isFavorite }
            unreadCount = allItems.filter { !$0.isRead }.count
            
        } catch {
            logger.error("Failed to load clipboard history: \(error)")
        }
    }
    
    private func saveEnhancedStatistics() {
        let stats = [
            "totalSyncCount": totalSyncCount,
            "totalItems": allItems.count,
            "favoriteItems": favoriteItems.count,
            "syncSuccessCount": syncSuccessCount,
            "syncFailureCount": syncFailureCount,
            "retryQueueSize": syncRetryQueue.count
        ]
        userDefaults.set(stats, forKey: statsKey)
    }
    
    private func loadStatistics() {
        if let stats = userDefaults.dictionary(forKey: statsKey) {
            totalSyncCount = stats["totalSyncCount"] as? Int ?? 0
            syncSuccessCount = stats["syncSuccessCount"] as? Int ?? 0
            syncFailureCount = stats["syncFailureCount"] as? Int ?? 0
        }
    }
    
    deinit {
        logger.info("🧹 ENHANCED ClipboardManager deinitializing")
        clipboardCheckTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        Task {
            await self.endBackgroundTask()
        }
    }
}

// MARK: - Supporting Types
struct ClipboardContent {
    let content: String
    let type: ClipboardItemType
    let size: Int
    let timestamp: Date
    let sourceDevice: String
    let imageData: Data?
    
    init(content: String, type: ClipboardItemType, size: Int, timestamp: Date, sourceDevice: String, imageData: Data? = nil) {
        self.content = content
        self.type = type
        self.size = size
        self.timestamp = timestamp
        self.sourceDevice = sourceDevice
        self.imageData = imageData
    }
}
