//
//  ClipboardItem.swift
//  LocalPeerSync
//
//  Comprehensive clipboard item model
//

import Foundation
import UIKit

// MARK: - Clipboard Item
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let type: ClipboardItemType
    let size: Int
    let timestamp: Date
    let sourceDevice: String
    var isRead: Bool
    var isFavorite: Bool
    var tags: [String]
    var imageData: Data?
    var metadata: ClipboardMetadata?
    
    // MARK: - Initialization
    init(
        content: String,
        type: ClipboardItemType,
        size: Int,
        timestamp: Date,
        sourceDevice: String,
        isRead: Bool = false,
        isFavorite: Bool = false,
        tags: [String] = [],
        imageData: Data? = nil,
        metadata: ClipboardMetadata? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.type = type
        self.size = size
        self.timestamp = timestamp
        self.sourceDevice = sourceDevice
        self.isRead = isRead
        self.isFavorite = isFavorite
        self.tags = tags
        self.imageData = imageData
        self.metadata = metadata ?? ClipboardMetadata.generate(for: content, type: type)
    }
    
    // MARK: - Computed Properties
    var displayContent: String {
        switch type {
        case .text:
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        case .url:
            return content
        case .image:
            return "Image (\(formattedSize))"
        case .file:
            return "File: \(extractFileName())"
        case .richText:
            return stripHTMLTags(from: content)
        }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    var isLarge: Bool {
        size > 1024 * 1024 // 1MB
    }
    
    var ageDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var contentPreview: String {
        let maxLength = 100
        let preview = displayContent
        return preview.count > maxLength ? String(preview.prefix(maxLength)) + "..." : preview
    }
    
    // MARK: - Helper Methods
    private func extractFileName() -> String {
        // Extract filename from file path or URL
        if let url = URL(string: content) {
            return url.lastPathComponent
        }
        return content.components(separatedBy: "/").last ?? "Unknown"
    }
    
    private func stripHTMLTags(from html: String) -> String {
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
    
    // MARK: - Validation
    func isValid() -> Bool {
        return !content.isEmpty && size > 0
    }
    
    func containsSearchTerm(_ term: String) -> Bool {
        let lowercasedTerm = term.lowercased()
        return content.lowercased().contains(lowercasedTerm) ||
               sourceDevice.lowercased().contains(lowercasedTerm) ||
               tags.contains { $0.lowercased().contains(lowercasedTerm) }
    }
    
    // MARK: - Actions
    mutating func markAsRead() {
        isRead = true
    }
    
    mutating func toggleFavorite() {
        isFavorite.toggle()
    }
    
    mutating func addTag(_ tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty && !tags.contains(trimmedTag) {
            tags.append(trimmedTag)
        }
    }
    
    mutating func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    // MARK: - Export/Import
    func exportData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "content": content,
            "type": type.rawValue,
            "size": size,
            "timestamp": timestamp.ISO8601String(),
            "sourceDevice": sourceDevice,
            "isRead": isRead,
            "isFavorite": isFavorite,
            "tags": tags
        ]
        
        if let imageData = imageData {
            data["imageData"] = imageData.base64EncodedString()
        }
        
        if let metadata = metadata {
            data["metadata"] = metadata.exportData()
        }
        
        return data
    }
    
    static func importData(_ data: [String: Any]) -> ClipboardItem? {
        guard let content = data["content"] as? String,
              let typeRaw = data["type"] as? String,
              let type = ClipboardItemType(rawValue: typeRaw),
              let size = data["size"] as? Int,
              let timestampString = data["timestamp"] as? String,
              let timestamp = Date.fromISO8601String(timestampString),
              let sourceDevice = data["sourceDevice"] as? String else {
            return nil
        }
        
        let isRead = data["isRead"] as? Bool ?? false
        let isFavorite = data["isFavorite"] as? Bool ?? false
        let tags = data["tags"] as? [String] ?? []
        
        var imageData: Data?
        if let imageDataString = data["imageData"] as? String {
            imageData = Data(base64Encoded: imageDataString)
        }
        
        var metadata: ClipboardMetadata?
        if let metadataData = data["metadata"] as? [String: Any] {
            metadata = ClipboardMetadata.importData(metadataData)
        }
        
        return ClipboardItem(
            content: content,
            type: type,
            size: size,
            timestamp: timestamp,
            sourceDevice: sourceDevice,
            isRead: isRead,
            isFavorite: isFavorite,
            tags: tags,
            imageData: imageData,
            metadata: metadata
        )
    }
}

// MARK: - Clipboard Item Type
enum ClipboardItemType: String, CaseIterable, Codable {
    case text
    case url
    case image
    case file
    case richText
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL"
        case .image: return "Image"
        case .file: return "File"
        case .richText: return "Rich Text"
        }
    }
    
    var iconName: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .richText: return "doc.richtext"
        }
    }
    
    var color: UIColor {
        switch self {
        case .text: return .systemBlue
        case .url: return .systemPurple
        case .image: return .systemGreen
        case .file: return .systemOrange
        case .richText: return .systemPink
        }
    }
}

// MARK: - Clipboard Metadata
struct ClipboardMetadata: Codable, Hashable {
    let wordCount: Int
    let characterCount: Int
    let lineCount: Int
    let hasEmoji: Bool
    let detectedLanguage: String?
    let mimeType: String?
    let encoding: String
    let createdAt: Date
    
    static func generate(for content: String, type: ClipboardItemType) -> ClipboardMetadata {
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let characterCount = content.count
        let lineCount = content.components(separatedBy: .newlines).count
        let hasEmoji = content.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        
        let mimeType: String?
        switch type {
        case .text:
            mimeType = "text/plain"
        case .url:
            mimeType = "text/uri-list"
        case .image:
            mimeType = "image/png"
        case .file:
            mimeType = "application/octet-stream"
        case .richText:
            mimeType = "text/html"
        }
        
        return ClipboardMetadata(
            wordCount: wordCount,
            characterCount: characterCount,
            lineCount: lineCount,
            hasEmoji: hasEmoji,
            detectedLanguage: detectLanguage(content),
            mimeType: mimeType,
            encoding: "UTF-8",
            createdAt: Date()
        )
    }
    
    private static func detectLanguage(_ text: String) -> String? {
        guard text.count > 10 else { return nil }
        
        let recognizer = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        recognizer.string = text
        
        return recognizer.dominantLanguage
    }
    
    func exportData() -> [String: Any] {
        var data: [String: Any] = [
            "wordCount": wordCount,
            "characterCount": characterCount,
            "lineCount": lineCount,
            "hasEmoji": hasEmoji,
            "encoding": encoding,
            "createdAt": createdAt.ISO8601String()
        ]
        
        if let detectedLanguage = detectedLanguage {
            data["detectedLanguage"] = detectedLanguage
        }
        
        if let mimeType = mimeType {
            data["mimeType"] = mimeType
        }
        
        return data
    }
    
    static func importData(_ data: [String: Any]) -> ClipboardMetadata? {
        guard let wordCount = data["wordCount"] as? Int,
              let characterCount = data["characterCount"] as? Int,
              let lineCount = data["lineCount"] as? Int,
              let hasEmoji = data["hasEmoji"] as? Bool,
              let encoding = data["encoding"] as? String,
              let createdAtString = data["createdAt"] as? String,
              let createdAt = Date.fromISO8601String(createdAtString) else {
            return nil
        }
        
        return ClipboardMetadata(
            wordCount: wordCount,
            characterCount: characterCount,
            lineCount: lineCount,
            hasEmoji: hasEmoji,
            detectedLanguage: data["detectedLanguage"] as? String,
            mimeType: data["mimeType"] as? String,
            encoding: encoding,
            createdAt: createdAt
        )
    }
}

// MARK: - Extensions
extension Date {
    func ISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
    
    static func fromISO8601String(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
    
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
