//
//  HistoryView.swift
//  LocalPeerSync
//
//  Clipboard history with search and management
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @State private var showingClearAlert = false
    @State private var selectedFilter: HistoryFilter = .all
    
    var filteredItems: [ClipboardItem] {
        var items = clipboardManager.allItems
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .text:
            items = items.filter { $0.type == .text }
        case .images:
            items = items.filter { $0.type == .image }
        case .urls:
            items = items.filter { $0.type == .url }
        case .today:
            items = items.filter { Calendar.current.isDateInToday($0.timestamp) }
        }
        
        // Apply search
        if !searchText.isEmpty {
            items = items.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.sourceDevice.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Filter Tabs
                FilterTabBar(selectedFilter: $selectedFilter)
                    .padding(.horizontal)
                
                // History List
                if filteredItems.isEmpty {
                    EmptyHistoryView(hasItems: !clipboardManager.allItems.isEmpty)
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            ClipboardItemRow(item: item, isCompact: false)
                                .contextMenu {
                                    ContextMenuItems(item: item)
                                }
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Clear All", role: .destructive) {
                            showingClearAlert = true
                        }
                        
                        Button("Export History") {
                            exportHistory()
                        }
                        
                        Button("Import History") {
                            importHistory()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Clear History", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clipboardManager.clearAllHistory()
                }
            } message: {
                Text("Are you sure you want to delete all clipboard history? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Actions
    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            clipboardManager.deleteItem(filteredItems[index])
        }
        HapticFeedback.light()
    }
    
    private func exportHistory() {
        clipboardManager.exportHistory()
        HapticFeedback.success()
    }
    
    private func importHistory() {
        clipboardManager.importHistory()
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    @State private var isEditing = false
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search clipboard history...", text: $text)
                    .onTapGesture {
                        isEditing = true
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            if isEditing {
                Button("Cancel") {
                    text = ""
                    isEditing = false
                    hideKeyboard()
                }
                .foregroundColor(.blue)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}

// MARK: - Filter Tab Bar
struct FilterTabBar: View {
    @Binding var selectedFilter: HistoryFilter
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    FilterTab(
                        filter: filter,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                        HapticFeedback.selection()
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct FilterTab: View {
    let filter: HistoryFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Clipboard Item Row
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isCompact: Bool
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var showingPreview = false
    
    var body: some View {
        Button(action: {
            copyItemToClipboard()
        }) {
            HStack(spacing: 12) {
                // Type Icon
                ItemTypeIcon(type: item.type, size: isCompact ? 24 : 32)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Content Preview
                    Text(item.displayContent)
                        .font(isCompact ? .subheadline : .body)
                        .fontWeight(.medium)
                        .lineLimit(isCompact ? 1 : 2)
                        .foregroundColor(.primary)
                    
                    // Metadata
                    HStack(spacing: 8) {
                        Label(item.sourceDevice, systemImage: "iphone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label(item.timestamp.timeAgoDisplay, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if item.size > 1024 {
                            Label(item.formattedSize, systemImage: "doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Actions
                if !isCompact {
                    VStack(spacing: 8) {
                        Button(action: {
                            showingPreview = true
                        }) {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        if item.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(.vertical, isCompact ? 6 : 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingPreview) {
            ClipboardItemPreview(item: item)
        }
    }
    
    private func copyItemToClipboard() {
        clipboardManager.copyItem(item)
        HapticFeedback.success()
    }
}

// MARK: - Item Type Icon
struct ItemTypeIcon: View {
    let type: ClipboardItemType
    let size: CGFloat
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .frame(width: size, height: size)
            
            Image(systemName: iconName)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(iconColor)
        }
    }
    
    private var iconName: String {
        switch type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        case .richText: return "doc.richtext"
        }
    }
    
    private var backgroundColor: Color {
        switch type {
        case .text: return .blue.opacity(0.2)
        case .image: return .green.opacity(0.2)
        case .url: return .purple.opacity(0.2)
        case .file: return .orange.opacity(0.2)
        case .richText: return .pink.opacity(0.2)
        }
    }
    
    private var iconColor: Color {
        switch type {
        case .text: return .blue
        case .image: return .green
        case .url: return .purple
        case .file: return .orange
        case .richText: return .pink
        }
    }
}

// MARK: - Context Menu Items
struct ContextMenuItems: View {
    let item: ClipboardItem
    @EnvironmentObject var clipboardManager: ClipboardManager
    
    var body: some View {
        Button(action: {
            clipboardManager.copyItem(item)
        }) {
            Label("Copy", systemImage: "doc.on.clipboard")
        }
        
        Button(action: {
            clipboardManager.toggleFavorite(item)
        }) {
            Label(
                item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: item.isFavorite ? "heart.slash" : "heart"
            )
        }
        
        Button(action: {
            clipboardManager.shareItem(item)
        }) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(role: .destructive, action: {
            clipboardManager.deleteItem(item)
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Empty History View
struct EmptyHistoryView: View {
    let hasItems: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: hasItems ? "magnifyingglass" : "clock")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(hasItems ? "No results found" : "No clipboard history")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(hasItems ?
                     "Try adjusting your search or filter criteria." :
                     "Your clipboard history will appear here as you copy and sync content.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
    }
}

// MARK: - Supporting Types
enum HistoryFilter: CaseIterable {
    case all, text, images, urls, today
    
    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .urls: return "URLs"
        case .today: return "Today"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .text: return "doc.text"
        case .images: return "photo"
        case .urls: return "link"
        case .today: return "calendar"
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(ClipboardManager.shared)
}
