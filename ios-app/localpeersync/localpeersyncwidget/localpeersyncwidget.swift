//
//  localpeersyncwidget.swift
//  localpeersyncwidget
//

import WidgetKit
import SwiftUI

@main
struct LocalPeerSyncWidget: Widget {
    let kind: String = "LocalPeerSyncWidget2"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimpleWidgetProvider()) { entry in
            SimpleWidgetView(entry: entry)
        }
        .configurationDisplayName("LocalPeerSync")
        .description("Toggle clipboard sync service on/off. Tap to start or stop syncing.")
        .supportedFamilies([.systemSmall, .systemMedium]) // ✅ ONLY small widgets
        .contentMarginsDisabled()
    }
}

// ✅ CLEAN PREVIEW - Only small widgets
#Preview(as: .systemSmall) {
    LocalPeerSyncWidget()
} timeline: {
    SimpleWidgetEntry(
        date: Date(),
        isRunning: false,
        deviceCount: 0,
        deviceName: "LocalPeerSync"
    )
    SimpleWidgetEntry(
        date: Date().addingTimeInterval(300),
        isRunning: true,
        deviceCount: 2,
        deviceName: "LocalPeerSync"
    )
}
