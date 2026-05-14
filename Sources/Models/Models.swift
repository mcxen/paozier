import Foundation

struct SearchResult: Identifiable, Hashable {
    let id: String
    let filePath: String
    let fileName: String
    let title: String
    let author: String
    let snippet: String
    let content: String
    let fileSize: Int64
    let lastModified: Date?
}

struct IndexedFolder: Identifiable, Codable {
    let id: String
    var path: String
    var fileCount: Int
    var lastIndexed: Date?

    init(path: String) {
        self.id = UUID().uuidString
        self.path = path
        self.fileCount = 0
        self.lastIndexed = nil
    }
}

// MARK: - Compendium

struct CompendiumEntry: Identifiable, Codable, Hashable {
    let id: String
    let filePath: String
    let fileName: String
    let excerpt: String
    let query: String
    let addedAt: Date

    init(result: SearchResult, query: String) {
        self.id = UUID().uuidString
        self.filePath = result.filePath
        self.fileName = result.fileName
        self.excerpt = result.snippet.isEmpty ? String(result.content.prefix(500)) : result.snippet
        self.query = query
        self.addedAt = Date()
    }

    // Codable conformance for persistence
    enum CodingKeys: String, CodingKey {
        case id, filePath, fileName, excerpt, query, addedAt
    }
}

struct Compendium: Codable {
    var name: String
    var entries: [CompendiumEntry]
    var createdAt: Date
    var updatedAt: Date

    init(name: String = "新报告") {
        self.name = name
        self.entries = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Search History & Bookmarks

struct SearchHistoryItem: Identifiable, Codable {
    let id: String
    let query: String
    let resultCount: Int
    let date: Date

    init(query: String, resultCount: Int) {
        self.id = UUID().uuidString
        self.query = query
        self.resultCount = resultCount
        self.date = Date()
    }
}

struct SearchBookmark: Identifiable, Codable {
    let id: String
    var name: String
    let query: String
    let createdAt: Date

    init(name: String, query: String) {
        self.id = UUID().uuidString
        self.name = name
        self.query = query
        self.createdAt = Date()
    }
}
