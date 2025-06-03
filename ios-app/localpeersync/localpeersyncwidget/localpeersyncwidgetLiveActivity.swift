//
//  localpeersyncwidgetLiveActivity.swift
//  localpeersyncwidget
//
//  Created by Nischal Paudyal on 6/3/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct localpeersyncwidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct localpeersyncwidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: localpeersyncwidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension localpeersyncwidgetAttributes {
    fileprivate static var preview: localpeersyncwidgetAttributes {
        localpeersyncwidgetAttributes(name: "World")
    }
}

extension localpeersyncwidgetAttributes.ContentState {
    fileprivate static var smiley: localpeersyncwidgetAttributes.ContentState {
        localpeersyncwidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: localpeersyncwidgetAttributes.ContentState {
         localpeersyncwidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: localpeersyncwidgetAttributes.preview) {
   localpeersyncwidgetLiveActivity()
} contentStates: {
    localpeersyncwidgetAttributes.ContentState.smiley
    localpeersyncwidgetAttributes.ContentState.starEyes
}
