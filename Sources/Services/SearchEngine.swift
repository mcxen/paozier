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

    // Settings cache (updated from AppSettings on main actor)
    var _settingsLimit: Int = 30
    var _settingsSKWeight: Double = 0.6
    var _settingsFTSWeight: Double = 0.4
    var _searchFilenames: Bool = true

    func updateSettings(limit: Int, skWeight: Double, ftsWeight: Double, searchFilenames: Bool = true) {
        _settingsLimit = limit
        _settingsSKWeight = skWeight
        _settingsFTSWeight = ftsWeight
        _searchFilenames = searchFilenames
    }

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

    func removeFiles(at fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        skIndex?.remove(urls: fileURLs)
        _ = ftsIndex.remove(urls: fileURLs)
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

    func search(query: String, limit: Int = 0, skWeight: Double = 0, ftsWeight: Double = 0) -> [SearchResult] {
        let effectiveLimit = limit > 0 ? limit : _settingsLimit
        let wSK = skWeight > 0 ? skWeight : _settingsSKWeight
        let wFTS = ftsWeight > 0 ? ftsWeight : _settingsFTSWeight
        var scoreMap: [String: (score: Double, url: URL)] = [:]

        // SearchKit results
        if let skResults = skIndex?.search(query, limit: effectiveLimit) {
            for (i, item) in skResults.enumerated() {
                let path = item.url.path
                let score = Double(skResults.count - i) / Double(max(skResults.count, 1)) * wSK
                scoreMap[path] = (score: score, url: item.url)
            }
        }

        // FTS results
        if let ftsResults = ftsIndex.search(text: query) {
            for (i, url) in ftsResults.enumerated() {
                let path = url.path
                let ftsScore = Double(ftsResults.count - i) / Double(max(ftsResults.count, 1)) * wFTS
                if let existing = scoreMap[path] {
                    scoreMap[path] = (score: existing.score + ftsScore, url: existing.url)
                } else {
                    scoreMap[path] = (score: ftsScore, url: url)
                }
            }
        }

        let sorted = scoreMap.values.sorted { $0.score > $1.score }.prefix(effectiveLimit)

        // Filename matching: add results where filename matches but content didn't
        var filenameMatches: [(score: Double, url: URL)] = []
        if _searchFilenames {
            let queryLower = query.lowercased()
            let terms = queryLower.split(separator: " ").map(String.init)
            // Check all indexed docs via FTS index URLs
            if let allResults = ftsIndex.search(text: "*") {
                for url in allResults {
                    let path = url.path
                    guard scoreMap[path] == nil else { continue }
                    let name = url.lastPathComponent.lowercased()
                    if terms.contains(where: { name.contains($0) }) {
                        filenameMatches.append((score: 0.3, url: url))
                    }
                }
            }
        }
        let combined = Array(sorted) + filenameMatches.prefix(effectiveLimit / 3)

        return combined.prefix(effectiveLimit).map { item in
            let path = item.url.path
            let fileName = item.url.lastPathComponent
            let content = (try? extractText(from: item.url)) ?? ""
            let snippet: String
            if item.score <= 0.3 && _searchFilenames {
                snippet = "文件名匹配: \(fileName)"
            } else {
                snippet = extractSnippet(path: path, query: query)
            }
            return SearchResult(
                id: path,
                filePath: path,
                fileName: fileName,
                title: fileName,
                author: "",
                snippet: snippet,
                content: content,
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
        case "docx":
            return try extractOfficeXMLText(from: url, prefixes: ["word/document", "word/header", "word/footer", "word/footnotes", "word/endnotes", "word/comments"])
        case "pptx":
            return try extractOfficeXMLText(from: url, prefixes: ["ppt/slides/slide", "ppt/notesSlides/notesSlide"])
        case "xlsx":
            return try extractXLSXText(from: url)
        case "rtf":
            let data = try Data(contentsOf: url)
            let attr = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return attr.string
        case "html", "htm", "xml":
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return stripMarkup(raw)
        default:
            return decodeText(try Data(contentsOf: url)) ?? ""
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

    private func extractOfficeXMLText(from url: URL, prefixes: [String]) throws -> String {
        let entries = try unzipEntries(in: url)
            .filter { entry in
                entry.hasSuffix(".xml") && prefixes.contains { entry.hasPrefix($0) }
            }
            .sorted()
        let parts = entries.compactMap { entry -> String? in
            guard let data = try? unzipData(from: url, entry: entry) else { return nil }
            let text = XMLTextParser.parse(data)
            return text.isEmpty ? nil : text
        }
        return parts.joined(separator: "\n\n")
    }

    private func extractXLSXText(from url: URL) throws -> String {
        let entries = try unzipEntries(in: url)
        let sharedStrings: [String] = {
            guard entries.contains("xl/sharedStrings.xml"),
                  let data = try? unzipData(from: url, entry: "xl/sharedStrings.xml") else { return [] }
            return XMLTextParser.fragments(data)
        }()

        let sheets = entries
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
            .compactMap { entry -> String? in
                guard let data = try? unzipData(from: url, entry: entry),
                      let raw = decodeText(data) else { return nil }
                let inline = XMLTextParser.fragments(data)
                let shared = regexCaptureGroups(raw, pattern: #"<c([^>]*)>\s*<v>([^<]+)</v>\s*</c>"#)
                    .compactMap { groups -> String? in
                        guard groups.count == 2 else { return nil }
                        if groups[0].contains("t=\"s\""), let idx = Int(groups[1]), sharedStrings.indices.contains(idx) {
                            return sharedStrings[idx]
                        }
                        return groups[1]
                    }
                let text = (shared + inline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
                return text.isEmpty ? nil : text
            }
        return sheets.joined(separator: "\n\n")
    }

    private func extractSnippet(path: String, query: String) -> String {
        let url = URL(fileURLWithPath: path)
        let content: String
        if url.pathExtension.lowercased() == "pdf" {
            content = extractPDFText(from: url)
        } else {
            content = (try? extractText(from: url)) ?? ""
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

    private func unzipEntries(in fileURL: URL) throws -> [String] {
        let data = try runUnzip(arguments: ["-Z1", fileURL.path])
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }

    private func unzipData(from fileURL: URL, entry: String) throws -> Data {
        try runUnzip(arguments: ["-p", fileURL.path, entry])
    }

    private func runUnzip(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return Data() }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private func decodeText(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .unicode, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private func stripMarkup(_ text: String) -> String {
        let noScripts = regexReplace(text, pattern: "<script\\b[^>]*>.*?</script>", with: " ", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let noStyles = regexReplace(noScripts, pattern: "<style\\b[^>]*>.*?</style>", with: " ", options: [.caseInsensitive, .dotMatchesLineSeparators])
        return regexReplace(noStyles, pattern: "<[^>]+>", with: " ")
    }

    private func regexReplace(_ text: String, pattern: String, with replacement: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: replacement)
    }

    private func regexCaptureGroups(_ text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { idx in
                guard let range = Range(match.range(at: idx), in: text) else { return nil }
                return String(text[range])
            }
        }
    }
}

private final class XMLTextParser: NSObject, XMLParserDelegate {
    private var values: [String] = []

    static func parse(_ data: Data) -> String {
        fragments(data).joined(separator: " ")
    }

    static func fragments(_ data: Data) -> [String] {
        let delegate = XMLTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        values.append(string)
    }
}
