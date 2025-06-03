//
//  LocalPeerSyncApp.swift
//  LocalPeerSync - Simple iOS Version
//

import SwiftUI
import os.log

@main
struct LocalPeerSyncApp: App {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "App")
    
    init() {
        logger.info("🚀 LocalPeerSync iOS Starting...")
        testRustIntegration()

    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SyncService.shared)
                .onAppear {
                                    // Move the delayed call here
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        self.testClipboardPermissions()
                                    }
                                }
        }
    }
    
    private func testClipboardPermissions() {
        logger.info("📋 Testing clipboard permissions...")
        
        let testText = "Permission test \(Date().timeIntervalSince1970)"
        
        // Test direct access
        UIPasteboard.general.string = testText
        
        if UIPasteboard.general.string == testText {
            logger.info("✅ Clipboard permissions - GRANTED")
            
            // Test our bridge function
            let cString = testText.cString(using: .utf8)!
            let result = ios_set_clipboard_text(cString)
            
            if result == 1 {
                logger.info("✅ Clipboard bridge function - WORKING")
            } else {
                logger.error("❌ Clipboard bridge function - FAILED")
            }
        } else {
            logger.error("❌ Clipboard permissions - DENIED")
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
    }
    
    private func requestClipboardPermissions() {
        logger.info("📋 Requesting clipboard permissions...")
        
        // Request clipboard access by doing a test operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let testString = "permission_request_\(Int.random(in: 1000...9999))"
            UIPasteboard.general.string = testString
            
            if UIPasteboard.general.string == testString {
                self.logger.info("✅ Clipboard permissions granted")
            } else {
                self.logger.error("❌ Clipboard permissions denied")
            }
        }
    }
}

// Import test functions from Rust
@_silgen_name("test_rust_connection")
func rust_test_connection() -> Int32
