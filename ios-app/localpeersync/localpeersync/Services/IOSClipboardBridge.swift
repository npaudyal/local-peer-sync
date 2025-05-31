//
//  IOSClipboardBridge.swift
//  LocalPeerSync
//
//  iOS clipboard bridge for Rust integration
//

import Foundation
import UIKit
import os.log

// MARK: - iOS Clipboard Functions for Rust

/// Get current clipboard text
@_silgen_name("ios_get_clipboard_text")
func ios_get_clipboard_text() -> UnsafeMutablePointer<CChar>? {
    guard let text = UIPasteboard.general.string else {
        return nil
    }
    
    return strdup(text)
}

/// Set clipboard text
@_silgen_name("ios_set_clipboard_text")
func ios_set_clipboard_text(_ text: UnsafePointer<CChar>) -> Int32 {
    let swiftText = String(cString: text)
    UIPasteboard.general.string = swiftText
    
    // Notify clipboard manager but prevent infinite loop
    DispatchQueue.main.async {
        ClipboardManager.shared.handleRustClipboardUpdate(swiftText, source: "rust")
    }
    
    return 1
}

/// Set clipboard image
@_silgen_name("ios_set_clipboard_image")
func ios_set_clipboard_image(_ data: UnsafePointer<UInt8>, _ len: Int, _ width: UInt32, _ height: UInt32) -> Int32 {
    let imageData = Data(bytes: data, count: len)
    
    guard let image = UIImage(data: imageData) else {
        return 0
    }
    
    UIPasteboard.general.image = image
    
    // Notify clipboard manager
    DispatchQueue.main.async {
        ClipboardManager.shared.handleRustImageUpdate(image, source: "rust")
    }
    
    return 1
}

/// Set clipboard URL
@_silgen_name("ios_set_clipboard_url")
func ios_set_clipboard_url(_ url: UnsafePointer<CChar>) -> Int32 {
    let urlString = String(cString: url)
    
    guard let nsurl = URL(string: urlString) else {
        return 0
    }
    
    UIPasteboard.general.url = nsurl
    
    // Notify clipboard manager
    DispatchQueue.main.async {
        ClipboardManager.shared.handleRustURLUpdate(urlString, source: "rust")
    }
    
    return 1
}

/// Free string allocated by iOS
@_silgen_name("ios_free_string")
func ios_free_string(_ ptr: UnsafeMutablePointer<CChar>) {
    free(ptr)
}

// Note: ClipboardContentType enum is now in RustTestBridge.swift to avoid conflicts
