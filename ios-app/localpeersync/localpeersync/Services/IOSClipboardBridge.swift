//
//  IOSClipboardBridge.swift
//  LocalPeerSync - DEBUG VERSION
//

import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ClipboardBridge")

/// DEBUG: Test function to verify FFI is working
@_cdecl("ios_test_bridge")
func ios_test_bridge() -> Int32 {
    logger.info("🧪 DEBUG: ios_test_bridge called successfully!")
    print("🧪 DEBUG: ios_test_bridge called successfully!")
    return 42
}

/// Get current clipboard text
@_cdecl("ios_get_clipboard_text")
func ios_get_clipboard_text() -> UnsafeMutablePointer<CChar>? {
    logger.info("📋 DEBUG: ios_get_clipboard_text called")
    print("📋 DEBUG: ios_get_clipboard_text called")
    
    guard let text = UIPasteboard.general.string, !text.isEmpty else {
        logger.info("📋 DEBUG: No clipboard text available")
        return nil
    }
    
    logger.info("📋 DEBUG: Returning clipboard text: \(text.prefix(50))...")
    return strdup(text)
}

/// Set clipboard text - ULTRA SIMPLE DEBUG VERSION
@_cdecl("ios_set_clipboard_text")
func ios_set_clipboard_text(_ text: UnsafePointer<CChar>) -> Int32 {
    let swiftText = String(cString: text)
    
    // ALWAYS log to both logger and print
    logger.info("📋 DEBUG: ios_set_clipboard_text called!")
    logger.info("📋 DEBUG: Text to set: '\(swiftText.prefix(50))...'")
    logger.info("📋 DEBUG: Thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
    
    print("📋 DEBUG: ios_set_clipboard_text called!")
    print("📋 DEBUG: Text to set: '\(swiftText.prefix(50))...'")
    print("📋 DEBUG: Thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
    
    // Try to set clipboard on main thread
    if Thread.isMainThread {
        print("📋 DEBUG: Already on main thread")
        UIPasteboard.general.string = swiftText
        
        // Verify
        let verification = UIPasteboard.general.string
        if verification == swiftText {
            print("📋 DEBUG: ✅ SUCCESS - Clipboard set and verified")
            logger.info("📋 DEBUG: ✅ SUCCESS - Clipboard set and verified")
            return 1
        } else {
            print("📋 DEBUG: ❌ FAILED - Verification failed")
            logger.error("📋 DEBUG: ❌ FAILED - Verification failed")
            return 0
        }
    } else {
        print("📋 DEBUG: Dispatching to main thread...")
        
        // Use semaphore for synchronous operation
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        DispatchQueue.main.async {
            print("📋 DEBUG: Now on main thread, setting clipboard...")
            UIPasteboard.general.string = swiftText
            
            // Verify
            let verification = UIPasteboard.general.string
            if verification == swiftText {
                print("📋 DEBUG: ✅ SUCCESS - Clipboard set and verified on main thread")
                success = true
            } else {
                print("📋 DEBUG: ❌ FAILED - Verification failed on main thread")
            }
            
            semaphore.signal()
        }
        
        // Wait for completion
        let result = semaphore.wait(timeout: .now() + 3.0)
        
        if result == .timedOut {
            print("📋 DEBUG: ❌ TIMEOUT - Main thread dispatch timed out")
            logger.error("📋 DEBUG: ❌ TIMEOUT - Main thread dispatch timed out")
            return 0
        }
        
        if success {
            print("📋 DEBUG: ✅ FINAL SUCCESS")
            logger.info("📋 DEBUG: ✅ FINAL SUCCESS")
            return 1
        } else {
            print("📋 DEBUG: ❌ FINAL FAILURE")
            logger.error("📋 DEBUG: ❌ FINAL FAILURE")
            return 0
        }
    }
}

/// Free string allocated by iOS
@_cdecl("ios_free_string")
func ios_free_string(_ ptr: UnsafeMutablePointer<CChar>) {
    free(ptr)
}
