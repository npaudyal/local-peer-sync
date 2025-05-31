//
//  LocalPeerSyncApp.swift
//  LocalPeerSync
//
//  The world's best clipboard sync for iOS
//

import SwiftUI
import BackgroundTasks
import UserNotifications

@_silgen_name("test_rust_connection")
func rust_test_connection() -> Int32

@_silgen_name("test_rust_string")
func rust_test_string() -> UnsafeMutablePointer<CChar>?

@_silgen_name("sync_free_string")
func rust_sync_free_string(_ ptr: UnsafeMutablePointer<CChar>)

@main
struct LocalPeerSyncApp: App {
    @StateObject private var syncService = SyncService.shared
    @StateObject private var clipboardManager = ClipboardManager.shared
    @StateObject private var backgroundManager = BackgroundManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    init() {
        print("🚀 LocalPeerSync iOS initializing...")
        
        // Configure app appearance
        configureAppearance()
        
        // Register background tasks early, but not through StateObject
        registerBackgroundTasksEarly()
        
        print("✅ Background tasks registered during app launch")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .environmentObject(clipboardManager)
                .environmentObject(backgroundManager)
                .environmentObject(notificationManager)
                .onAppear {
                    setupAppAfterLaunch()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    handleAppBecameActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    handleAppWillResignActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    handleAppDidEnterBackground()
                }
        }
    }
    
    // MARK: - Early Background Task Registration
    private func registerBackgroundTasksEarly() {
        let syncTaskIdentifier = "com.localpeersync.ios.sync"
        let clipboardTaskIdentifier = "com.localpeersync.ios.clipboardcheck"
        
        // Register app refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: syncTaskIdentifier,
            using: nil
        ) { task in
            Task {
                await BackgroundManager.shared.handleBackgroundSync(task: task as! BGAppRefreshTask)
            }
        }
        
        // Register processing task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: clipboardTaskIdentifier,
            using: nil
        ) { task in
            Task {
                await BackgroundManager.shared.handleClipboardCheck(task: task as! BGProcessingTask)
            }
        }
        
        print("📱 Registered background tasks successfully")
    }
    
    // MARK: - Post-Launch Setup
    private func setupAppAfterLaunch() {
        print("🚀 LocalPeerSync iOS post-launch setup...")
        
        testRustIntegration()

        
        // Mark background tasks as registered in the manager
        Task { @MainActor in
            backgroundManager.backgroundTasksRegistered = true
        }
        
        // Request permissions (can happen after launch)
        notificationManager.requestPermissions()
        
        // Initialize services (can happen after launch)
        Task {
            await syncService.initialize()
        }
        
        print("✅ LocalPeerSync iOS post-launch setup complete")
    }
    
    private func testRustIntegration() {
        print("🧪 Testing Rust integration...")
        
        // Test 1: Simple integer return
        let result = rust_test_connection()
        print("🧪 Rust test result: \(result)")
        
        if result == 42 {
            print("✅ Rust integer test PASSED!")
        } else {
            print("❌ Rust integer test FAILED! Expected 42, got \(result)")
        }
        
        // Test 2: String return
        if let stringPtr = rust_test_string() {
            let rustString = String(cString: stringPtr)
            print("🧪 Rust string result: '\(rustString)'")
            
            // Free the string
            rust_sync_free_string(stringPtr)
            
            if rustString == "Hello from Rust!" {
                print("✅ Rust string test PASSED!")
            } else {
                print("❌ Rust string test FAILED! Expected 'Hello from Rust!', got '\(rustString)'")
            }
        } else {
            print("❌ Rust string test FAILED! Got null pointer")
        }
    }
    
    // MARK: - App Lifecycle
    private func handleAppBecameActive() {
        print("📱 App became active")
        clipboardManager.checkClipboardChanges()
        
        Task {
            await syncService.refreshStatus()
        }
    }
    
    private func handleAppWillResignActive() {
        print("📱 App will resign active")
        clipboardManager.saveCurrentState()
    }
    
    private func handleAppDidEnterBackground() {
        print("📱 App entered background")
        backgroundManager.scheduleBackgroundTasks()
    }
    
    // MARK: - App Appearance
    private func configureAppearance() {
        // Configure navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.systemBackground
        navBarAppearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        
        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}
