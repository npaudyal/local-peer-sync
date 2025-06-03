//
//  ClipboardMonitor.swift
//  LocalPeerSync - Simple iOS Version
//

import Foundation
import UIKit
import os.log

class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastContent: String = ""
    private let pasteboard = UIPasteboard.general
    private let syncService = SyncService.shared
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "ClipboardMonitor")
    private var ignoreNextChange = false
    
    func startMonitoring() {
        lastChangeCount = pasteboard.changeCount
        if let content = pasteboard.string {
            lastContent = content
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.checkForChanges()
        }
        
        logger.info("🔍 Started clipboard monitoring")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        logger.info("🛑 Stopped clipboard monitoring")
    }
    
    // Add this method to ClipboardMonitor class
    func setClipboardContentFromNetwork(_ content: String) {
        logger.info("📋 Setting clipboard content from network: \(content.prefix(50))...")
        
        ignoreNextChange = true
        
        // Set clipboard on main thread
        DispatchQueue.main.async {
            UIPasteboard.general.string = content
            self.lastContent = content
            self.lastChangeCount = UIPasteboard.general.changeCount
            
            self.logger.info("✅ Clipboard content set from network")
        }
    }
    
    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            if ignoreNextChange {
                ignoreNextChange = false
                logger.info("🔇 Ignoring clipboard change (set by network)")
                return
            }
            
            if let string = pasteboard.string, string != lastContent {
                lastContent = string
                logger.info("📋 Clipboard changed: \(string.prefix(50))...")
                
                // Only sync if service is running
                if syncService.isRunning {
                    syncService.syncClipboard(string)
                }
            }
        }
    }
    
    func setClipboardContent(_ content: String) {
        logger.info("📋 Setting clipboard content from network: \(content.prefix(50))...")
        
        ignoreNextChange = true
        pasteboard.string = content
        lastContent = content
        lastChangeCount = pasteboard.changeCount
        
        logger.info("✅ Clipboard content set from network")
    }
    
    deinit {
        stopMonitoring()
    }
}
