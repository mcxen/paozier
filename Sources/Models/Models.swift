import Foundation

enum FileTypeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case pdf = "PDF"
    case doc = "DOC"
    case xls = "XLS"
    case md = "MD"
    case txt = "TXT"
    case code = "代码"

    var id: String { rawValue }

    var displayName: String { L(rawValue) }

    var extensions: [String]? {
        switch self {
        case .all: return nil
        case .pdf: return ["pdf"]
        case .doc: return ["doc", "docx", "rtf"]
        case .xls: return ["xls", "xlsx", "csv"]
        case .md: return ["md", "markdown"]
        case .txt: return ["txt"]
        case .code: return ["swift", "py", "js", "ts", "java", "c", "cpp", "rs", "go", "html", "htm", "json", "xml"]
        }
    }
}

struct SearchOptions: Hashable {
    var query: String = ""
    var selectedFileTypes: Set<FileTypeFilter> = []
    var folderPaths: Set<String> = []
    var usesRegex: Bool = false
    var fuzzySpaces: Bool = true

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var allowedExtensions: Set<String>? {
        if selectedFileTypes.isEmpty || selectedFileTypes.contains(.all) {
            return nil
        }
        let extensions = selectedFileTypes.flatMap { $0.extensions ?? [] }
        return extensions.isEmpty ? nil : Set(extensions)
    }

    var searchScopeDescription: String {
        folderPaths.isEmpty ? L("全部文件夹") : L("指定文件夹")
    }

    var highlightTerms: [String] {
        guard !usesRegex else { return [trimmedQuery].filter { !$0.isEmpty } }
        return trimmedQuery
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "*", with: "") }
            .filter { !$0.isEmpty && !["AND", "OR", "NOT"].contains($0.uppercased()) && !$0.hasPrefix("-") }
    }
}

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
    var sourceKind: String = "local"
    var sourceName: String = "本地"
    var externalURL: String = ""
    var externalID: String = ""

    var isExternal: Bool {
        sourceKind != "local"
    }
}

struct MemosSourceConfig: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var token: String
    var isEnabled: Bool

    init(id: String = UUID().uuidString, name: String = "", baseURL: String = "", token: String = "", isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.token = token
        self.isEnabled = isEnabled
    }

    func displayName(index: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Memos \(index + 1)" : trimmed
    }
}

struct ExternalSearchResult: Identifiable, Hashable {
    let id: String
    let externalID: String
    let sourceID: String
    let sourceKind: String
    let sourceName: String
    let title: String
    let snippet: String
    let content: String
    let url: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct GrepBatchResult {
    let results: [SearchResult]
    let isFinal: Bool
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

enum FolderIndexPhase: String {
    case idle
    case queued
    case scanning
    case indexing
    case completed
    case failed
}

struct FolderIndexStatus: Equatable {
    var phase: FolderIndexPhase = .idle
    var completedFiles: Int = 0
    var totalFiles: Int = 0
    var failedFiles: Int = 0
    var ocrIndexedFiles: Int = 0
    var queuePosition: Int?
    var statusText: String = ""
    var currentFilePath: String?
    var startedAt: Date?
    var finishedAt: Date?
    var lastErrorDescription: String?

    var progress: Double {
        guard totalFiles > 0 else {
            return phase == .completed ? 1 : 0
        }
        return min(max(Double(completedFiles) / Double(totalFiles), 0), 1)
    }

    var isQueued: Bool {
        phase == .queued
    }

    var isActive: Bool {
        phase == .scanning || phase == .indexing
    }

    var isTerminal: Bool {
        phase == .completed || phase == .failed
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

    init(name: String = L("报告名称")) {
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
    let duration: TimeInterval?

    init(query: String, resultCount: Int, duration: TimeInterval? = nil) {
        self.id = UUID().uuidString
        self.query = query
        self.resultCount = resultCount
        self.duration = duration
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
