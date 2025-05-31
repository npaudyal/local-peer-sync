//
//  ContentView.swift
//  LocalPeerSync
//
//  Main tabbed interface
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            DevicesView()
                .tabItem {
                    Label("Devices", systemImage: "wifi")
                }
                .badge(syncService.connectedPeers.count)
                .tag(1)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .badge(clipboardManager.unreadCount)
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .accentColor(.blue)
        .onAppear {
            configureTabBar()
        }
    }
    
    private func configureTabBar() {
        UITabBar.appearance().backgroundColor = UIColor.systemBackground
        UITabBar.appearance().barTintColor = UIColor.systemBackground
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncService.shared)
        .environmentObject(ClipboardManager.shared)
        .environmentObject(BackgroundManager.shared)
        .environmentObject(NotificationManager.shared)
}
