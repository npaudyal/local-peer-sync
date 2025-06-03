//
//  SimpleWidgetProvider.swift
//  LocalPeerSyncWidget
//

import WidgetKit
import SwiftUI

struct SimpleWidgetProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> SimpleWidgetEntry {
        SimpleWidgetEntry(
            date: Date(),
            isRunning: false,
            deviceCount: 0,
            deviceName: "LocalPeerSync"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleWidgetEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleWidgetEntry>) -> Void) {
        let entry = createEntry()
        
        // Refresh every 30 seconds when running, every 5 minutes when off
        let refreshInterval: TimeInterval = entry.isRunning ? 30.0 : 300.0
        let nextUpdate = Date().addingTimeInterval(refreshInterval)
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func createEntry() -> SimpleWidgetEntry {
        let data = SimpleWidgetManager.shared.loadData()
        
        return SimpleWidgetEntry(
            date: Date(),
            isRunning: data.isRunning,
            deviceCount: data.deviceCount,
            deviceName: data.deviceName
        )
    }
}
