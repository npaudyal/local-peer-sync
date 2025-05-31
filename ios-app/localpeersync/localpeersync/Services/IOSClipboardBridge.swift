//  IOSClipboardBridge.swift
//  LocalPeerSync
//
//  ENHANCED iOS clipboard bridge with proper linking

import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ClipboardBridge")

/// Get current clipboard text - OVERRIDE Rust stub
@_cdecl("ios_get_clipboard_text")
func ios_get_clipboard_text() -> UnsafeMutablePointer<CChar>? {
    logger.info("📋 Swift: ios_get_clipboard_text called")
    
    guard let text = UIPasteboard.general.string else {
        logger.info("📋 Swift: No clipboard text available")
        return nil
    }
    
    logger.info("📋 Swift: Returning clipboard text: \(text.prefix(50))...")
    return strdup(text)
}

/// Set clipboard text - OVERRIDE Rust stub
@_cdecl("ios_set_clipboard_text")
func ios_set_clipboard_text(_ text: UnsafePointer<CChar>) -> Int32 {
    let swiftText = String(cString: text)
    logger.info("📋 Swift: Setting clipboard text: \(swiftText.prefix(50))...")
    
    UIPasteboard.general.string = swiftText
    
    // Notify clipboard manager but prevent infinite loop
    DispatchQueue.main.async {
        ClipboardManager.shared.handleRustClipboardUpdate(swiftText, source: "network")
    }
    
    logger.info("📋 Swift: Successfully set clipboard text")
    return 1
}

/// Set clipboard image - OVERRIDE Rust stub
@_cdecl("ios_set_clipboard_image")
func ios_set_clipboard_image(_ data: UnsafePointer<UInt8>, _ len: Int, _ width: UInt32, _ height: UInt32) -> Int32 {
    logger.info("📋 Swift: Setting clipboard image: \(width)x\(height), \(len) bytes")
    
    let imageData = Data(bytes: data, count: len)
    
    guard let image = UIImage(data: imageData) else {
        logger.error("📋 Swift: Failed to create UIImage from data")
        return 0
    }
    
    UIPasteboard.general.image = image
    
    // Notify clipboard manager
    DispatchQueue.main.async {
        ClipboardManager.shared.handleRustImageUpdate(image, source: "network")
    }
    
    logger.info("📋 Swift: Successfully set clipboard image")
    return 1
}

/// Set clipboard URL - OVERRIDE Rust stub
@_cdecl("ios_set_clipboard_url")
func ios_set_clipboard_url(_ url: UnsafePointer<CChar>) -> Int32 {
    let urlString = String(cString: url)
    logger.info("📋 Swift: Setting clipboard URL: \(urlString)")
    
    guard let nsurl = URL(string: urlString) else {
        logger.error("📋 Swift: Invalid URL: \(urlString)")
        return 0
    }
    
    UIPasteboard.general.url = nsurl
    
    // Notify clipboard manager
    DispatchQueue.main.async {
        ClipboardManager.shared.handleRustURLUpdate(urlString, source: "network")
    }
    
    logger.info("📋 Swift: Successfully set clipboard URL")
    return 1
}

/// Free string allocated by iOS - OVERRIDE Rust stub
@_cdecl("ios_free_string")
func ios_free_string(_ ptr: UnsafeMutablePointer<CChar>) {
    free(ptr)
}
