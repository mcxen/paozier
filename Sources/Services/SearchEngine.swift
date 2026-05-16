import Foundation
import DFSearchKit
import DSFFullTextSearchIndex
import PDFKit
import Vision

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

        let normalized = Self.normalizeForSearch(content)

        // SearchKit
        _ = skIndex?.add(fileURL, text: normalized)

        // FTS
        _ = ftsIndex.add(url: fileURL, text: normalized)
    }

    /// Normalize unicode variants (dashes, quotes, whitespace) to ASCII equivalents for consistent search matching
    static func normalizeForSearch(_ text: String) -> String {
        var result = text
        // Normalize dashes: en-dash, em-dash, figure dash, horizontal bar → hyphen
        for dash in ["\u{2013}", "\u{2014}", "\u{2012}", "\u{2015}", "\u{2010}", "\u{2011}"] {
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        // Normalize quotes
        for q in ["\u{2018}", "\u{2019}", "\u{201A}", "\u{2039}", "\u{203A}"] {
            result = result.replacingOccurrences(of: q, with: "'")
        }
        for q in ["\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}"] {
            result = result.replacingOccurrences(of: q, with: "\"")
        }
        return result
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

    func search(options: SearchOptions, limit: Int = 0, skWeight: Double = 0, ftsWeight: Double = 0) -> [SearchResult] {
        if options.usesRegex {
            return regexSearch(options: options, limit: limit)
        }

        let query = Self.normalizeForSearch(options.trimmedQuery)
        let effectiveLimit = limit > 0 ? limit : _settingsLimit
        let engineLimit = options.folderPaths.isEmpty ? effectiveLimit : max(effectiveLimit * 8, 200)
        let wSK = skWeight > 0 ? skWeight : _settingsSKWeight
        let wFTS = ftsWeight > 0 ? ftsWeight : _settingsFTSWeight
        let allowedExtensions = options.allowedExtensions
        var scoreMap: [String: (score: Double, url: URL)] = [:]

        // Parse query for engine-specific formats
        let skQuery: String
        let ftsQuery: String
        if QueryParser.isAdvanced(query) {
            let tokens = QueryParser.parse(query)
            skQuery = QueryParser.toSearchKit(tokens)
            ftsQuery = QueryParser.toFTS5(tokens)
        } else {
            skQuery = query
            ftsQuery = query
        }

        // SearchKit results
        if let skResults = skIndex?.search(skQuery, limit: engineLimit) {
            for (i, item) in skResults.enumerated() {
                let path = item.url.path
                let score = Double(skResults.count - i) / Double(max(skResults.count, 1)) * wSK
                scoreMap[path] = (score: score, url: item.url)
            }
        }

        // FTS results
        if let ftsResults = ftsIndex.search(text: ftsQuery) {
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

        let filtered: [String: (score: Double, url: URL)]
        filtered = scoreMap.filter { _, item in
            fileAllowed(item.url, extensions: allowedExtensions, folderPaths: options.folderPaths)
        }

        let sorted = filtered.values.sorted { $0.score > $1.score }.prefix(effectiveLimit)

        // Filename matching: add results where filename matches but content didn't
        var filenameMatches: [(score: Double, url: URL)] = []
        if _searchFilenames {
            let terms = options.highlightTerms.map { $0.lowercased() }
            // Check all indexed docs via FTS index URLs
            for url in allIndexedURLs() {
                let path = url.path
                guard filtered[path] == nil else { continue }
                guard fileAllowed(url, extensions: allowedExtensions, folderPaths: options.folderPaths) else { continue }
                let name = url.lastPathComponent.lowercased()
                if terms.contains(where: { name.contains($0) }) {
                    filenameMatches.append((score: 0.3, url: url))
                }
            }
        }
        var combined = Array(sorted) + filenameMatches.prefix(effectiveLimit / 3)

        if options.fuzzySpaces, options.highlightTerms.count > 1 {
            let existing = Set(combined.map { $0.url.path })
            let fuzzyMatches = fuzzyContentMatches(options: options, excluding: existing, limit: max(effectiveLimit / 2, 10))
            combined += fuzzyMatches
        }

        return combined.prefix(effectiveLimit).map { item in
            let path = item.url.path
            let fileName = item.url.lastPathComponent
            let content = Self.normalizeForSearch((try? extractText(from: item.url)) ?? "")
            let snippet: String
            if item.score <= 0.3 && _searchFilenames {
                snippet = "文件名匹配: \(fileName)"
            } else {
                snippet = extractSnippet(path: path, options: options)
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

    func search(query: String, limit: Int = 0, skWeight: Double = 0, ftsWeight: Double = 0, fileTypeFilter: FileTypeFilter = .all) -> [SearchResult] {
        var options = SearchOptions(query: query)
        options.selectedFileTypes = fileTypeFilter == .all ? [] : [fileTypeFilter]
        return search(options: options, limit: limit, skWeight: skWeight, ftsWeight: ftsWeight)
    }

    func isIndexed(path: String) -> Bool {
        let normalized = normalizedPath(path)
        return allIndexedURLs().contains { normalizedPath($0.path) == normalized }
    }

    private func regexSearch(options: SearchOptions, limit: Int) -> [SearchResult] {
        let effectiveLimit = limit > 0 ? limit : _settingsLimit
        let query = options.trimmedQuery
        guard !query.isEmpty,
              let regex = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else {
            return []
        }

        var matches: [SearchResult] = []
        for url in allIndexedURLs() {
            guard fileAllowed(url, extensions: options.allowedExtensions, folderPaths: options.folderPaths) else { continue }
            let content = Self.normalizeForSearch((try? extractText(from: url)) ?? "")
            let searchable = _searchFilenames ? "\(url.lastPathComponent)\n\(content)" : content
            let range = NSRange(searchable.startIndex..<searchable.endIndex, in: searchable)
            guard let match = regex.firstMatch(in: searchable, range: range) else { continue }

            matches.append(SearchResult(
                id: url.path,
                filePath: url.path,
                fileName: url.lastPathComponent,
                title: url.lastPathComponent,
                author: "",
                snippet: snippet(in: searchable, around: match.range),
                content: content,
                fileSize: fileSize(at: url.path),
                lastModified: nil
            ))
            if matches.count >= effectiveLimit { break }
        }
        return matches
    }

    private func fuzzyContentMatches(options: SearchOptions, excluding existing: Set<String>, limit: Int) -> [(score: Double, url: URL)] {
        let terms = options.highlightTerms.map { $0.lowercased() }
        guard terms.count > 1 else { return [] }

        var matches: [(score: Double, url: URL)] = []
        for url in allIndexedURLs() {
            if existing.contains(url.path) { continue }
            guard fileAllowed(url, extensions: options.allowedExtensions, folderPaths: options.folderPaths) else { continue }
            let content = ((try? extractText(from: url)) ?? "").lowercased()
            guard containsTermsInOrder(terms, in: content) else { continue }
            matches.append((score: 0.25, url: url))
            if matches.count >= limit { break }
        }
        return matches
    }

    private func containsTermsInOrder(_ terms: [String], in text: String) -> Bool {
        var searchStart = text.startIndex
        for term in terms {
            guard let range = text.range(of: term, range: searchStart..<text.endIndex) else { return false }
            searchStart = range.upperBound
        }
        return true
    }

    private func allIndexedURLs() -> [URL] {
        ftsIndex.search(text: "*") ?? []
    }

    private func fileAllowed(_ url: URL, extensions: Set<String>?, folderPaths: Set<String>) -> Bool {
        if let extensions, !extensions.contains(url.pathExtension.lowercased()) {
            return false
        }
        guard !folderPaths.isEmpty else { return true }
        let filePath = normalizedPath(url.path)
        return folderPaths.contains { folderPath in
            let folder = normalizedPath(folderPath)
            return filePath == folder || filePath.hasPrefix(folder + "/")
        }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    // MARK: - Text Extraction

    private func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return extractPDFText(from: url)
        case "docx":
            return try extractDocxText(from: url)
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
            guard let page = doc.page(at: i) else { continue }
            let pageText = page.string ?? ""
            if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text += pageText + "\n"
            } else {
                // OCR fallback for image-based pages
                text += ocrPage(page) + "\n"
            }
        }
        return text
    }

    private func ocrPage(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return "" }
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let cgImage = context.makeImage() else { return "" }

        let semaphore = DispatchSemaphore(value: 0)
        var ocrText = ""
        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            ocrText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            semaphore.signal()
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        semaphore.wait()
        return ocrText
    }

    private func extractDocxText(from url: URL) throws -> String {
        let entries = try unzipEntries(in: url)
        var parts: [String] = []

        // Extract metadata from docProps/core.xml
        if entries.contains("docProps/core.xml"),
           let data = try? unzipData(from: url, entry: "docProps/core.xml") {
            let meta = DocxMetadataParser.parse(data)
            if !meta.isEmpty { parts.append(meta) }
        }

        // Extract body text
        let contentPrefixes = ["word/document", "word/header", "word/footer", "word/footnotes", "word/endnotes"]
        let contentEntries = entries
            .filter { entry in entry.hasSuffix(".xml") && contentPrefixes.contains(where: { entry.hasPrefix($0) }) }
            .sorted()
        for entry in contentEntries {
            guard let data = try? unzipData(from: url, entry: entry) else { continue }
            let text = DocxBodyParser.parse(data)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: "\n\n")
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

    private func extractSnippet(path: String, options: SearchOptions) -> String {
        let url = URL(fileURLWithPath: path)
        let content: String
        if url.pathExtension.lowercased() == "pdf" {
            content = extractPDFText(from: url)
        } else {
            content = (try? extractText(from: url)) ?? ""
        }
        guard !content.isEmpty else { return "" }

        let lower = content.lowercased()
        let terms = options.highlightTerms.map { $0.lowercased() }
        for term in terms {
            if let range = lower.range(of: term) {
                return snippet(in: content, around: NSRange(range, in: content))
            }
        }
        return String(content.prefix(200))
    }

    private func snippet(in content: String, around nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: content) else {
            return String(content.prefix(200)).replacingOccurrences(of: "\n", with: " ")
        }
        let start = content.index(range.lowerBound, offsetBy: -60, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: 140, limitedBy: content.endIndex) ?? content.endIndex
        return String(content[start..<end]).replacingOccurrences(of: "\n", with: " ")
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
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return Data() }
        return data
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

/// Parses docProps/core.xml for title, subject, creator, keywords, description
private final class DocxMetadataParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""
    private var metadata: [String: String] = [:]
    private static let metaElements: Set<String> = ["dc:title", "dc:subject", "dc:creator", "cp:keywords", "dc:description", "cp:category"]

    static func parse(_ data: Data) -> String {
        let delegate = DocxMetadataParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.metadata.values.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = element
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if Self.metaElements.contains(element) {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { metadata[element] = trimmed }
        }
    }
}

/// Parses word/document.xml preserving paragraph structure
private final class DocxBodyParser: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var currentParagraph = ""
    private var inParagraph = false

    static func parse(_ data: Data) -> String {
        let delegate = DocxBodyParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.paragraphs.joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = element.split(separator: ":").last.map(String.init) ?? element
        if local == "p" { inParagraph = true; currentParagraph = "" }
        // w:tab and w:br insert spacing
        if inParagraph && (local == "tab" || local == "br") { currentParagraph += " " }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inParagraph { currentParagraph += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let local = element.split(separator: ":").last.map(String.init) ?? element
        if local == "p" {
            let trimmed = currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { paragraphs.append(trimmed) }
            inParagraph = false
        }
    }
}
