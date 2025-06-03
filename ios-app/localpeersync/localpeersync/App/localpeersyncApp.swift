//
//  LocalPeerSyncApp.swift
//  LocalPeerSync - Background Ready App (PRODUCTION)
//

import SwiftUI
import os.log
import BackgroundTasks

@main
struct LocalPeerSyncApp: App {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "App")
    @StateObject private var notificationManager = BackgroundNotificationManager.shared
    
    init() {
        logger.info("🚀 LocalPeerSync iOS - Background Ready Edition")
        testRustIntegration()
        setupBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SyncService.shared)
                .environmentObject(notificationManager)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didFinishLaunchingNotification)) { _ in
                    handleAppLaunch()
                }
        }
    }
    
    private func testRustIntegration() {
        logger.info("🧪 Testing Rust integration...")
        
        let result = rust_test_connection()
        if result == 42 {
            logger.info("✅ Rust integration test PASSED!")
        } else {
            logger.error("❌ Rust integration test FAILED!")
        }
        
        if let stringPtr = rust_test_string() {
            let rustString = String(cString: stringPtr)
            rust_sync_free_string(stringPtr)
            
            if rustString == "Hello from Rust!" {
                logger.info("✅ Rust string test PASSED!")
            } else {
                logger.error("❌ Rust string test FAILED!")
            }
        }
    }
    
    private func setupBackgroundTasks() {
        // Register background task identifier
        let result = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.localpeersync.sync",
            using: nil
        ) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
        
        if result {
            logger.info("✅ Background task registered successfully")
        } else {
            logger.error("❌ Failed to register background task")
        }
    }
    
    private func handleAppLaunch() {
        logger.info("📱 App launched - checking for background clipboard changes")
        
        // Request notification permissions on first launch
        Task { @MainActor in
            notificationManager.requestPermissions()
        }
        
        // Check if app was launched by background task
        scheduleBackgroundRefresh()
    }
    
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        logger.info("🔄 Handling background app refresh task")
        
        task.expirationHandler = {
            self.logger.warning("⏰ Background sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            // Quick background sync check
            await SyncService.shared.performBackgroundSync()
            
            // Schedule next refresh
            self.scheduleBackgroundRefresh()
            
            task.setTaskCompleted(success: true)
            self.logger.info("✅ Background sync completed")
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.localpeersync.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("✅ Background refresh scheduled")
        } catch {
            logger.error("❌ Failed to schedule background refresh: \(error)")
        }
    }
}

// Import test functions from Rust
@_silgen_name("test_rust_connection")
func rust_test_connection() -> Int32

@_silgen_name("test_rust_string")
func rust_test_string() -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_free_string")
func rust_sync_free_string(_ ptr: UnsafeMutablePointer<CChar>)
