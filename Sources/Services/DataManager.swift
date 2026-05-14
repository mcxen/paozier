import Foundation
import AppKit

@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()

    @Published var compendium = Compendium()
    @Published var history: [SearchHistoryItem] = []
    @Published var bookmarks: [SearchBookmark] = []

    private let dataDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = appSupport.appendingPathComponent("Paozier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Compendium

    func addToCompendium(result: SearchResult, query: String) {
        let entry = CompendiumEntry(result: result, query: query)
        compendium.entries.append(entry)
        compendium.updatedAt = Date()
        save()
    }

    func removeFromCompendium(id: String) {
        compendium.entries.removeAll { $0.id == id }
        compendium.updatedAt = Date()
        save()
    }

    func clearCompendium() {
        compendium = Compendium()
        save()
    }

    func exportCompendium() -> String {
        var text = "# \(compendium.name)\n\n"
        text += "生成时间: \(compendium.updatedAt.formatted())\n"
        text += "共 \(compendium.entries.count) 条摘录\n\n---\n\n"
        for entry in compendium.entries {
            text += "## \(entry.fileName)\n"
            text += "路径: \(entry.filePath)\n"
            text += "搜索词: \(entry.query)\n\n"
            text += "> \(entry.excerpt)\n\n---\n\n"
        }
        return text
    }

    func exportCompendiumToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(compendium.name).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? exportCompendium().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - History

    func addHistory(query: String, resultCount: Int) {
        let item = SearchHistoryItem(query: query, resultCount: resultCount)
        history.insert(item, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    // MARK: - Bookmarks

    func addBookmark(name: String, query: String) {
        bookmarks.append(SearchBookmark(name: name, query: query))
        save()
    }

    func removeBookmark(id: String) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    // MARK: - Export Highlighted Document

    func exportHighlighted(result: SearchResult, terms: [String]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(result.fileName)_highlighted.txt"
        if panel.runModal() == .OK, let url = panel.url {
            var text = result.content
            for term in terms where !term.isEmpty {
                text = text.replacingOccurrences(
                    of: term,
                    with: "【\(term)】",
                    options: .caseInsensitive
                )
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        try? encoder.encode(compendium).write(to: dataDir.appendingPathComponent("compendium.json"))
        try? encoder.encode(history).write(to: dataDir.appendingPathComponent("history.json"))
        try? encoder.encode(bookmarks).write(to: dataDir.appendingPathComponent("bookmarks.json"))
    }

    private func load() {
        let decoder = JSONDecoder()
        if let d = try? Data(contentsOf: dataDir.appendingPathComponent("compendium.json")) {
            compendium = (try? decoder.decode(Compendium.self, from: d)) ?? Compendium()
        }
        if let d = try? Data(contentsOf: dataDir.appendingPathComponent("history.json")) {
            history = (try? decoder.decode([SearchHistoryItem].self, from: d)) ?? []
        }
        if let d = try? Data(contentsOf: dataDir.appendingPathComponent("bookmarks.json")) {
            bookmarks = (try? decoder.decode([SearchBookmark].self, from: d)) ?? []
        }
    }
}
