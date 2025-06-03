//
//  SimpleWidgetView.swift
//  LocalPeerSyncWidget
//

import SwiftUI
import WidgetKit

struct SimpleWidgetView: View {
    let entry: SimpleWidgetEntry
    
    var body: some View {
        // ✅ ONLY small widget view - no size switching needed
        VStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .symbolEffect(.pulse, isActive: entry.isRunning)
            
            Text("LocalPeerSync")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(statusText)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            
            if entry.isRunning && entry.deviceCount > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(entry.deviceCount, 4), id: \.self) { _ in
                        Circle()
                            .fill(.white.opacity(0.8))
                            .frame(width: 4, height: 4)
                    }
                    if entry.deviceCount > 4 {
                        Text("+")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "localpeersync://toggle"))
    }
    
    private var iconName: String {
        if entry.isRunning {
            return entry.deviceCount > 0 ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark"
        } else {
            return "power"
        }
    }
    
    private var statusText: String {
        if entry.isRunning {
            if entry.deviceCount > 0 {
                return "\(entry.deviceCount) device\(entry.deviceCount == 1 ? "" : "s")"
            } else {
                return "Searching..."
            }
        } else {
            return "Tap to start"
        }
    }
    
    private var backgroundColors: [Color] {
        if entry.isRunning {
            return entry.deviceCount > 0 ? [.green, .blue] : [.orange, .yellow]
        } else {
            return [.gray, .gray.opacity(0.7)]
        }
    }
}
