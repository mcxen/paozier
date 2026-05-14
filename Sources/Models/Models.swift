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
