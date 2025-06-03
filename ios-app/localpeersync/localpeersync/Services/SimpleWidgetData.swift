//
//  SimpleWidgetData.swift
//  LocalPeerSync
//

import Foundation
import WidgetKit

// Simple data structure for widget
struct SimpleWidgetData: Codable {
    let isRunning: Bool
    let deviceCount: Int
    let deviceName: String
    let lastToggleTime: Date
    
    static let `default` = SimpleWidgetData(
        isRunning: false,
        deviceCount: 0,
        deviceName: "LocalPeerSync",
        lastToggleTime: Date()
    )
}

// Widget timeline entry
struct SimpleWidgetEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let deviceCount: Int
    let deviceName: String
}

// Simple widget manager
class SimpleWidgetManager {
    static let shared = SimpleWidgetManager()
    
    private let suiteName = "group.com.nischal.ios.localpeersync.shared"
    private let dataKey = "simple_widget_data"
    
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
    private init() {}
    
    func saveData(_ data: SimpleWidgetData) {
        do {
            let encoded = try JSONEncoder().encode(data)
            userDefaults?.set(encoded, forKey: dataKey)
            userDefaults?.synchronize()
            
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            
            print("✅ Widget data saved: Running=\(data.isRunning), Devices=\(data.deviceCount)")
        } catch {
            print("❌ Failed to save widget data: \(error)")
        }
    }
    
    func loadData() -> SimpleWidgetData {
        guard let data = userDefaults?.data(forKey: dataKey) else {
            return .default
        }
        
        do {
            return try JSONDecoder().decode(SimpleWidgetData.self, from: data)
        } catch {
            print("❌ Failed to load widget data: \(error)")
            return .default
        }
    }
    
    func updateServiceStatus(isRunning: Bool, deviceCount: Int, deviceName: String) {
        let data = SimpleWidgetData(
            isRunning: isRunning,
            deviceCount: deviceCount,
            deviceName: deviceName,
            lastToggleTime: Date()
        )
        saveData(data)
    }
}
