//
//  ClipboardMonitor.swift
//  LocalPeerSync
//
//  Monitors clipboard changes and syncs them
//

import Foundation
import AppKit
import os.log

class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastContent: String = ""
    private let pasteboard = NSPasteboard.general
    private let syncService = SyncService.shared
    private let logger = Logger(subsystem: "com.localpeersync.macos", category: "ClipboardMonitor")
    
    func startMonitoring() {
        lastChangeCount = pasteboard.changeCount
        if let content = pasteboard.string(forType: .string) {
            lastContent = content
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            self.checkForChanges()
        }
        
        logger.info("🔍 Started clipboard monitoring")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        logger.info("🛑 Stopped clipboard monitoring")
    }
    
    private func checkForChanges() {
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            if let string = pasteboard.string(forType: .string), string != lastContent {
                lastContent = string
                logger.info("📋 Clipboard changed: \(string.prefix(50))...")
                
                // Only sync if service is running
                if syncService.isRunning {
                    syncService.syncClipboard(string)
                }
            }
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
