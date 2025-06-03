//
//  IOSClipboardBridge.swift
//  LocalPeerSync - COMPLETELY FIXED
//

import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ClipboardBridge")

/// Get current clipboard text - OVERRIDE Rust stub
@_cdecl("ios_get_clipboard_text")
func ios_get_clipboard_text() -> UnsafeMutablePointer<CChar>? {
    logger.info("📋 Swift: ios_get_clipboard_text called")
    
    // FIXED: Ensure main thread access with better error handling
    let text: String? = {
        if Thread.isMainThread {
            return UIPasteboard.general.string
        } else {
            var result: String?
            DispatchQueue.main.sync {
                result = UIPasteboard.general.string
            }
            return result
        }
    }()
    
    guard let text = text, !text.isEmpty else {
        logger.info("📋 Swift: No clipboard text available")
        return nil
    }
    
    logger.info("📋 Swift: Returning clipboard text: \(text.prefix(50))...")
    return strdup(text)
}

/// Set clipboard text - OVERRIDE Rust stub - COMPLETELY FIXED
@_cdecl("ios_set_clipboard_text")
func ios_set_clipboard_text(_ text: UnsafePointer<CChar>) -> Int32 {
    let swiftText = String(cString: text)
    logger.info("📋 Swift: Setting clipboard text: \(swiftText.prefix(50))...")
    
    // FIXED: Comprehensive main thread handling with detailed logging
    var success = false
    var errorMessage = ""
    
    if Thread.isMainThread {
        logger.info("📋 Swift: Already on main thread")
        do {
            UIPasteboard.general.string = swiftText
            
            // Verify the clipboard was actually set
            if let verifyText = UIPasteboard.general.string, verifyText == swiftText {
                success = true
                logger.info("📋 Swift: ✅ Clipboard verification successful")
            } else {
                errorMessage = "Clipboard verification failed"
                logger.error("📋 Swift: ❌ Clipboard verification failed")
            }
            
            // Update ClipboardManager on main actor
            Task { @MainActor in
                ClipboardManager.shared.setClipboardContentFromNetwork(swiftText)
            }
            
        } catch {
            errorMessage = "Exception setting clipboard: \(error)"
            logger.error("📋 Swift: ❌ Exception setting clipboard: \(error)")
        }
    } else {
        logger.info("📋 Swift: Dispatching to main thread")
        DispatchQueue.main.sync {
            do {
                UIPasteboard.general.string = swiftText
                
                // Verify the clipboard was actually set
                if let verifyText = UIPasteboard.general.string, verifyText == swiftText {
                    success = true
                    logger.info("📋 Swift: ✅ Clipboard verification successful (dispatched)")
                } else {
                    errorMessage = "Clipboard verification failed (dispatched)"
                    logger.error("📋 Swift: ❌ Clipboard verification failed (dispatched)")
                }
                
                Task { @MainActor in
                    ClipboardManager.shared.setClipboardContentFromNetwork(swiftText)
                }
                
            } catch {
                errorMessage = "Exception setting clipboard (dispatched): \(error)"
                logger.error("📋 Swift: ❌ Exception setting clipboard (dispatched): \(error)")
            }
        }
    }
    
    if success {
        logger.info("📋 Swift: ✅ Successfully set clipboard text")
        
        // Send notification
        Task { @MainActor in
            BackgroundNotificationManager.shared.notifyClipboardReceived(preview: String(swiftText.prefix(50)))
        }
        
        return 1
    } else {
        logger.error("📋 Swift: ❌ Failed to set clipboard text: \(errorMessage)")
        return 0
    }
}

/// Set clipboard image - OVERRIDE Rust stub - FIXED
@_cdecl("ios_set_clipboard_image")
func ios_set_clipboard_image(_ data: UnsafePointer<UInt8>, _ len: Int, _ width: UInt32, _ height: UInt32) -> Int32 {
    logger.info("📋 Swift: Setting clipboard image: \(width)x\(height), \(len) bytes")
    
    let imageData = Data(bytes: data, count: len)
    var success = false
    
    if Thread.isMainThread {
        guard let image = UIImage(data: imageData) else {
            logger.error("📋 Swift: Failed to create UIImage from data")
            return 0
        }
        
        UIPasteboard.general.image = image
        
        // Verify the image was set
        if UIPasteboard.general.image != nil {
            success = true
            logger.info("📋 Swift: ✅ Image verification successful")
        } else {
            logger.error("📋 Swift: ❌ Image verification failed")
        }
        
        let imageDescription = "Image (\(width)x\(height)) - \(len) bytes"
        Task { @MainActor in
            ClipboardManager.shared.setClipboardContentFromNetwork(imageDescription)
        }
        
    } else {
        DispatchQueue.main.sync {
            guard let image = UIImage(data: imageData) else {
                logger.error("📋 Swift: Failed to create UIImage from data")
                return
            }
            
            UIPasteboard.general.image = image
            
            // Verify the image was set
            if UIPasteboard.general.image != nil {
                success = true
                logger.info("📋 Swift: ✅ Image verification successful (dispatched)")
            } else {
                logger.error("📋 Swift: ❌ Image verification failed (dispatched)")
            }
            
            let imageDescription = "Image (\(width)x\(height)) - \(len) bytes"
            Task { @MainActor in
                ClipboardManager.shared.setClipboardContentFromNetwork(imageDescription)
            }
        }
    }
    
    if success {
        logger.info("📋 Swift: ✅ Successfully set clipboard image")
        
        Task { @MainActor in
            BackgroundNotificationManager.shared.notifyClipboardReceived(preview: "Image received")
        }
        
        return 1
    } else {
        return 0
    }
}

/// Set clipboard URL - OVERRIDE Rust stub - FIXED
@_cdecl("ios_set_clipboard_url")
func ios_set_clipboard_url(_ url: UnsafePointer<CChar>) -> Int32 {
    let urlString = String(cString: url)
    logger.info("📋 Swift: Setting clipboard URL: \(urlString)")
    
    var success = false
    
    if Thread.isMainThread {
        guard let nsurl = URL(string: urlString) else {
            logger.error("📋 Swift: Invalid URL: \(urlString)")
            return 0
        }
        
        UIPasteboard.general.url = nsurl
        
        // Verify the URL was set
        if UIPasteboard.general.url != nil {
            success = true
            logger.info("📋 Swift: ✅ URL verification successful")
        } else {
            logger.error("📋 Swift: ❌ URL verification failed")
        }
        
        Task { @MainActor in
            ClipboardManager.shared.setClipboardContentFromNetwork(urlString)
        }
        
    } else {
        DispatchQueue.main.sync {
            guard let nsurl = URL(string: urlString) else {
                logger.error("📋 Swift: Invalid URL: \(urlString)")
                return
            }
            
            UIPasteboard.general.url = nsurl
            
            // Verify the URL was set
            if UIPasteboard.general.url != nil {
                success = true
                logger.info("📋 Swift: ✅ URL verification successful (dispatched)")
            } else {
                logger.error("📋 Swift: ❌ URL verification failed (dispatched)")
            }
            
            Task { @MainActor in
                ClipboardManager.shared.setClipboardContentFromNetwork(urlString)
            }
        }
    }
    
    if success {
        logger.info("📋 Swift: ✅ Successfully set clipboard URL")
        
        Task { @MainActor in
            BackgroundNotificationManager.shared.notifyClipboardReceived(preview: urlString)
        }
        
        return 1
    } else {
        return 0
    }
}

/// Free string allocated by iOS - OVERRIDE Rust stub
@_cdecl("ios_free_string")
func ios_free_string(_ ptr: UnsafeMutablePointer<CChar>) {
    free(ptr)
}
