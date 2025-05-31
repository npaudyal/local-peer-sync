//
//  ClipboardItemPreview.swift
//  LocalPeerSync
//
//  Detailed preview of clipboard items
//

import SwiftUI

struct ClipboardItemPreview: View {
    let item: ClipboardItem
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    ItemHeaderView(item: item)
                    
                    // Content Preview
                    ContentPreviewView(item: item)
                    
                    // Metadata
                    MetadataView(item: item)
                    
                    // Actions
                    ActionButtonsView(item: item, showingShareSheet: $showingShareSheet)
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            clipboardManager.copyItem(item)
                            presentationMode.wrappedValue.dismiss()
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
                            showingShareSheet = true
                        }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            clipboardManager.deleteItem(item)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [item.content])
        }
    }
}

struct ItemHeaderView: View {
    let item: ClipboardItem
    
    var body: some View {
        HStack(spacing: 16) {
            ItemTypeIcon(type: item.type, size: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.type.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("From \(item.sourceDevice)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(item.timestamp.timeAgoDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                
                Text(item.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct ContentPreviewView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content")
                .font(.headline)
                .fontWeight(.semibold)
            
            Group {
                switch item.type {
                case .text, .richText:
                    TextContentView(content: item.content)
                case .url:
                    URLContentView(url: item.content)
                case .image:
                    ImageContentView(item: item)
                case .file:
                    FileContentView(content: item.content)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

struct TextContentView: View {
    let content: String
    @State private var isExpanded = false
    
    private var shouldTruncate: Bool {
        content.count > 300
    }
    
    private var displayContent: String {
        if shouldTruncate && !isExpanded {
            return String(content.prefix(300)) + "..."
        }
        return content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayContent)
                .font(.body)
                .textSelection(.enabled)
            
            if shouldTruncate {
                Button(isExpanded ? "Show Less" : "Show More") {
                    withAnimation(.smooth) {
                        isExpanded.toggle()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
    }
}

struct URLContentView: View {
    let url: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(url, destination: URL(string: url) ?? URL(string: "https://example.com")!)
                .font(.body)
                .foregroundColor(.blue)
            
            if let urlObject = URL(string: url) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Host: \(urlObject.host ?? "Unknown")", systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let scheme = urlObject.scheme {
                        Label("Protocol: \(scheme.uppercased())", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct ImageContentView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 100)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("Image Preview Unavailable")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            Label("Image • \(item.formattedSize)", systemImage: "photo")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct FileContentView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(extractFileName(from: content))
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text("File Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text(content)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
    
    private func extractFileName(from path: String) -> String {
        return path.components(separatedBy: "/").last ?? "Unknown File"
    }
}

struct MetadataView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                MetadataRow(label: "Type", value: item.type.displayName)
                MetadataRow(label: "Size", value: item.formattedSize)
                MetadataRow(label: "Created", value: item.timestamp.shortDateDisplay)
                MetadataRow(label: "Source", value: item.sourceDevice)
                
                if let metadata = item.metadata {
                    MetadataRow(label: "Characters", value: "\(metadata.characterCount)")
                    if metadata.wordCount > 0 {
                        MetadataRow(label: "Words", value: "\(metadata.wordCount)")
                    }
                    if metadata.lineCount > 1 {
                        MetadataRow(label: "Lines", value: "\(metadata.lineCount)")
                                            }
                                            if metadata.hasEmoji {
                                                MetadataRow(label: "Contains", value: "Emoji 😊")
                                            }
                                            if let language = metadata.detectedLanguage {
                                                MetadataRow(label: "Language", value: language.uppercased())
                                            }
                                        }
                                        
                                        if !item.tags.isEmpty {
                                            MetadataRow(label: "Tags", value: item.tags.joined(separator: ", "))
                                        }
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.regularMaterial)
                                    )
                                }
                            }
                        }

                        struct MetadataRow: View {
                            let label: String
                            let value: String
                            
                            var body: some View {
                                HStack {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(minWidth: 80, alignment: .leading)
                                    
                                    Spacer()
                                    
                                    Text(value)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        struct ActionButtonsView: View {
                            let item: ClipboardItem
                            @Binding var showingShareSheet: Bool
                            @EnvironmentObject var clipboardManager: ClipboardManager
                            
                            var body: some View {
                                VStack(spacing: 12) {
                                    HStack(spacing: 12) {
                                        Button(action: {
                                            clipboardManager.copyItem(item)
                                            HapticFeedback.success()
                                        }) {
                                            HStack {
                                                Image(systemName: "doc.on.clipboard")
                                                Text("Copy")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                        }
                                        
                                        Button(action: {
                                            clipboardManager.toggleFavorite(item)
                                            HapticFeedback.light()
                                        }) {
                                            HStack {
                                                Image(systemName: item.isFavorite ? "heart.slash" : "heart")
                                                Text(item.isFavorite ? "Unfavorite" : "Favorite")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(item.isFavorite ? Color.red : Color.orange)
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                        }
                                    }
                                    
                                    Button(action: {
                                        showingShareSheet = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(.regularMaterial)
                                        .foregroundColor(.primary)
                                        .cornerRadius(12)
                                    }
                                }
                            }
                        }

                        // MARK: - Share Sheet
                        struct ShareSheet: UIViewControllerRepresentable {
                            let items: [Any]
                            
                            func makeUIViewController(context: Context) -> UIActivityViewController {
                                let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
                                return controller
                            }
                            
                            func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
                        }

                        #Preview {
                            ClipboardItemPreview(item: ClipboardItem(
                                content: "This is a sample clipboard item with some content to preview.",
                                type: .text,
                                size: 64,
                                timestamp: Date(),
                                sourceDevice: "iPhone"
                            ))
                            .environmentObject(ClipboardManager.shared)
                        }
