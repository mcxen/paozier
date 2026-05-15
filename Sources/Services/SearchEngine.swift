import Foundation
import DFSearchKit
import DSFFullTextSearchIndex
import PDFKit

/// Dual-engine search: Apple SearchKit (relevance ranking) + SQLite FTS5 (CJK)
actor SearchEngine {
    static let shared = SearchEngine()

    private var skIndex: DFSearchIndex.File?
    private let ftsIndex = DSFFullTextSearchIndex()
    private let dataDir: URL
    private let skPath: URL
    private let ftsPath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = appSupport.appendingPathComponent("Paozier", isDirectory: true)
        skPath = dataDir.appendingPathComponent("searchkit.index")
        ftsPath = dataDir.appendingPathComponent("fts.db")
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    func open() {
        // SearchKit index
        if FileManager.default.fileExists(atPath: skPath.path) {
            skIndex = DFSearchIndex.File.Open(fileURL: skPath, writable: true)
        }
        if skIndex == nil {
            skIndex = DFSearchIndex.File.Create(fileURL: skPath)
        }

        // FTS index
        if FileManager.default.fileExists(atPath: ftsPath.path) {
            _ = ftsIndex.open(filePath: ftsPath.path)
        } else {
            _ = ftsIndex.create(filePath: ftsPath.path)
        }
    }

    func close() {
        skIndex?.save()
        skIndex?.close()
        skIndex = nil
        ftsIndex.close()
    }

    // MARK: - Indexing

    func indexFile(at fileURL: URL) throws {
        let content = try extractText(from: fileURL)
        guard !content.isEmpty else { return }

        // SearchKit
        _ = skIndex?.add(fileURL, text: content)

        // FTS
        _ = ftsIndex.add(url: fileURL, text: content)
    }

    func commit() {
        skIndex?.flush()
    }

    func removeFile(at fileURL: URL) {
        _ = skIndex?.remove(url: fileURL)
        _ = ftsIndex.remove(url: fileURL)
    }

    func removeAll() {
        close()
        try? FileManager.default.removeItem(at: skPath)
        try? FileManager.default.removeItem(at: ftsPath)
        open()
    }

    var documentCount: Int {
        Int(ftsIndex.count())
    }

    // MARK: - Search (fused results)

    func search(query: String, limit: Int = 30) -> [SearchResult] {
        var scoreMap: [String: (score: Double, url: URL)] = [:]

        // SearchKit results
        if let skResults = skIndex?.search(query, limit: limit) {
            for (i, item) in skResults.enumerated() {
                let path = item.url.path
                let score = Double(skResults.count - i) / Double(max(skResults.count, 1)) * 0.6
                scoreMap[path] = (score: score, url: item.url)
            }
        }

        // FTS results
        if let ftsResults = ftsIndex.search(text: query) {
            for (i, url) in ftsResults.enumerated() {
                let path = url.path
                let ftsScore = Double(ftsResults.count - i) / Double(max(ftsResults.count, 1)) * 0.4
                if let existing = scoreMap[path] {
                    scoreMap[path] = (score: existing.score + ftsScore, url: existing.url)
                } else {
                    scoreMap[path] = (score: ftsScore, url: url)
                }
            }
        }

        let sorted = scoreMap.values.sorted { $0.score > $1.score }.prefix(limit)

        return sorted.map { item in
            let path = item.url.path
            let fileName = item.url.lastPathComponent
            return SearchResult(
                id: path,
                filePath: path,
                fileName: fileName,
                title: fileName,
                author: "",
                snippet: extractSnippet(path: path, query: query),
                content: "",
                fileSize: fileSize(at: path),
                lastModified: nil
            )
        }
    }

    // MARK: - Text Extraction

    private func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return extractPDFText(from: url)
        case "rtf":
            let data = try Data(contentsOf: url)
            let attr = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return attr.string
        default:
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    private func extractPDFText(from url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var text = ""
        for i in 0..<doc.pageCount {
            text += doc.page(at: i)?.string ?? ""
            text += "\n"
        }
        return text
    }

    private func extractSnippet(path: String, query: String) -> String {
        let url = URL(fileURLWithPath: path)
        let content: String
        if url.pathExtension.lowercased() == "pdf" {
            content = extractPDFText(from: url)
        } else {
            content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }
        guard !content.isEmpty else { return "" }

        let lower = content.lowercased()
        let terms = query.lowercased().split(separator: " ").map(String.init)
        for term in terms {
            if let range = lower.range(of: term) {
                let start = content.index(range.lowerBound, offsetBy: -60, limitedBy: content.startIndex) ?? content.startIndex
                let end = content.index(range.upperBound, offsetBy: 140, limitedBy: content.endIndex) ?? content.endIndex
                return String(content[start..<end]).replacingOccurrences(of: "\n", with: " ")
            }
        }
        return String(content.prefix(200))
    }

    private func fileSize(at path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }
}
