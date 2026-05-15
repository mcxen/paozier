import Foundation
import AppKit

actor SolrService {
    static let shared = SolrService()
    private let baseURL = "http://localhost:8983/solr/paozier"

    func search(query: String, rows: Int = 20, proximity: Int? = nil, useRegex: Bool = false) async throws -> [SearchResult] {
        var q: String
        if useRegex {
            q = "/\(query)/"
        } else if let dist = proximity, dist > 0 {
            let terms = query.split(separator: " ").map(String.init)
            if terms.count >= 2 {
                q = "\"\(terms.joined(separator: " "))\"~\(dist)"
            } else {
                q = query
            }
        } else {
            // Support excluded words (-term) and quoted strings natively in Solr
            q = query
        }
        guard var components = URLComponents(string: "\(baseURL)/select") else { throw SolrError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "rows", value: "\(rows)"),
            URLQueryItem(name: "hl", value: "true"),
            URLQueryItem(name: "hl.fl", value: "content,title,file_name"),
            URLQueryItem(name: "hl.snippets", value: "5"),
            URLQueryItem(name: "hl.fragsize", value: "300"),
            URLQueryItem(name: "fl", value: "id,file_path,file_name,title,author,file_size,content"),
            URLQueryItem(name: "wt", value: "json")
        ]
        guard let url = components.url else { throw SolrError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let response = json["response"] as? [String: Any] ?? [:]
        let docs = response["docs"] as? [[String: Any]] ?? []
        let highlighting = json["highlighting"] as? [String: [String: [String]]] ?? [:]

        return docs.map { doc in
            let id = doc["id"] as? String ?? UUID().uuidString
            let hlSnippets = highlighting[id]?["content"] ?? highlighting[id]?["title"] ?? []
            let snippet = hlSnippets.joined(separator: " ... ")

            return SearchResult(
                id: id,
                filePath: doc["file_path"] as? String ?? "",
                fileName: (doc["file_name"] as? String) ?? (doc["file_path"] as? String)?.components(separatedBy: "/").last ?? "",
                title: (doc["title"] as? String) ?? "",
                author: (doc["author"] as? String) ?? "",
                snippet: snippet,
                content: (doc["content"] as? String) ?? "",
                fileSize: (doc["file_size"] as? Int64) ?? 0,
                lastModified: nil
            )
        }
    }

    func indexPDF(at fileURL: URL) async throws {
        try await indexFile(at: fileURL)
    }

    func indexFile(at fileURL: URL) async throws {
        if let content = try Self.extractCleanText(from: fileURL) {
            try await indexExtractedText(at: fileURL, content: content)
            return
        }
        try await indexWithTika(at: fileURL)
    }

    private func indexWithTika(at fileURL: URL) async throws {
        let id = fileURL.path.data(using: .utf8)!.base64EncodedString()
        let fileName = fileURL.lastPathComponent
        let filePath = fileURL.path
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        guard var components = URLComponents(string: "\(baseURL)/update/extract") else { throw SolrError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "literal.id", value: id),
            URLQueryItem(name: "literal.file_path", value: filePath),
            URLQueryItem(name: "literal.file_name", value: fileName),
            URLQueryItem(name: "literal.file_size", value: "\(fileSize)"),
            URLQueryItem(name: "commit", value: "false"),
            URLQueryItem(name: "wt", value: "json")
        ]
        guard let url = components.url else { throw SolrError.invalidURL }

        let fileData = try Data(contentsOf: fileURL)
        let mimeType = Self.mimeType(for: fileURL.pathExtension)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 else {
            throw SolrError.indexFailed
        }
    }

    private func indexExtractedText(at fileURL: URL, content: String) async throws {
        let cleanedContent = Self.normalizeText(content)
        guard !cleanedContent.isEmpty else { throw SolrError.indexFailed }

        let id = fileURL.path.data(using: .utf8)!.base64EncodedString()
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let title = fileURL.deletingPathExtension().lastPathComponent
        let doc: [String: Any] = [
            "id": id,
            "file_path": fileURL.path,
            "file_name": fileURL.lastPathComponent,
            "title": title,
            "content": cleanedContent,
            "file_size": fileSize
        ]

        guard var components = URLComponents(string: "\(baseURL)/update") else { throw SolrError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "commit", value: "false"),
            URLQueryItem(name: "wt", value: "json")
        ]
        guard let url = components.url else { throw SolrError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [doc])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 else {
            throw SolrError.indexFailed
        }
    }

    private static func extractCleanText(from fileURL: URL) throws -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "txt", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm":
            return try readTextFile(fileURL)
        case "rtf":
            return try readRTF(fileURL)
        case "docx":
            return try extractDocxText(from: fileURL)
        case "pptx":
            return try extractPPTXText(from: fileURL)
        case "xlsx":
            return try extractXLSXText(from: fileURL)
        case "odt", "ods", "odp":
            return try extractODFText(from: fileURL)
        case "epub":
            return try extractEPUBText(from: fileURL)
        default:
            return nil
        }
    }

    private static func readTextFile(_ fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let raw = decodeText(data) ?? ""
        switch fileURL.pathExtension.lowercased() {
        case "html", "htm":
            return stripMarkup(raw)
        case "xml":
            return XMLTextParser.parse(data).isEmpty ? stripMarkup(raw) : XMLTextParser.parse(data)
        default:
            return raw
        }
    }

    private static func readRTF(_ fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        if let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return attributed.string
        }
        return decodeText(data) ?? ""
    }

    private static func extractDocxText(from fileURL: URL) throws -> String {
        let entries = try unzipEntries(in: fileURL)
            .filter { entry in
                entry == "word/document.xml"
                    || entry.hasPrefix("word/header")
                    || entry.hasPrefix("word/footer")
                    || entry == "word/footnotes.xml"
                    || entry == "word/endnotes.xml"
                    || entry == "word/comments.xml"
            }
            .filter { $0.hasSuffix(".xml") }
            .sorted()

        let sections = entries.compactMap { entry -> String? in
            guard let data = try? unzipData(from: fileURL, entry: entry) else { return nil }
            let text = XMLTextParser.parse(data, textElements: ["w:t", "t"])
            return text.isEmpty ? nil : text
        }
        guard !sections.isEmpty else { throw SolrError.indexFailed }
        return sections.joined(separator: "\n\n")
    }

    private static func extractPPTXText(from fileURL: URL) throws -> String {
        let entries = try unzipEntries(in: fileURL)
            .filter { entry in
                (entry.hasPrefix("ppt/slides/slide") || entry.hasPrefix("ppt/notesSlides/notesSlide"))
                    && entry.hasSuffix(".xml")
            }
            .sorted { lhs, rhs in
                let leftKey = entrySortKey(lhs)
                let rightKey = entrySortKey(rhs)
                return leftKey == rightKey ? lhs < rhs : leftKey < rightKey
            }

        let slides = entries.compactMap { entry -> String? in
            guard let xmlData = try? unzipData(from: fileURL, entry: entry) else { return nil }
            let text = PPTXTextParser.parse(xmlData)
            return text.isEmpty ? nil : text
        }

        guard !slides.isEmpty else { throw SolrError.indexFailed }
        return slides.joined(separator: "\n\n")
    }

    private static func extractXLSXText(from fileURL: URL) throws -> String {
        let entries = try unzipEntries(in: fileURL)
        let sharedStrings: [String] = {
            guard entries.contains("xl/sharedStrings.xml"),
                  let data = try? unzipData(from: fileURL, entry: "xl/sharedStrings.xml") else { return [] }
            return XMLTextParser.fragments(data, textElements: ["t"])
        }()

        let sheetEntries = entries
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { entryNumber($0) < entryNumber($1) }

        let sheets = sheetEntries.compactMap { entry -> String? in
            guard let data = try? unzipData(from: fileURL, entry: entry),
                  let raw = decodeText(data) else { return nil }

            let inlineText = XMLTextParser.fragments(data, textElements: ["t"])
            let cellText = extractXLSXCellText(from: raw, sharedStrings: sharedStrings)

            let text = (cellText + inlineText)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return text.isEmpty ? nil : text
        }

        guard !sheets.isEmpty else { throw SolrError.indexFailed }
        return sheets.joined(separator: "\n\n")
    }

    private static func extractODFText(from fileURL: URL) throws -> String {
        guard let data = try? unzipData(from: fileURL, entry: "content.xml") else { throw SolrError.indexFailed }
        let text = XMLTextParser.parse(data)
        guard !text.isEmpty else { throw SolrError.indexFailed }
        return text
    }

    private static func extractEPUBText(from fileURL: URL) throws -> String {
        let entries = try unzipEntries(in: fileURL)
            .filter { entry in
                let lower = entry.lowercased()
                return lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm")
            }
            .sorted()

        let sections = entries.compactMap { entry -> String? in
            guard let data = try? unzipData(from: fileURL, entry: entry) else { return nil }
            let text = XMLTextParser.parse(data)
            return text.isEmpty ? nil : text
        }
        guard !sections.isEmpty else { throw SolrError.indexFailed }
        return sections.joined(separator: "\n\n")
    }

    private static func unzipEntries(in fileURL: URL) throws -> [String] {
        let data = try runUnzip(arguments: ["-Z1", fileURL.path])
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private static func unzipData(from fileURL: URL, entry: String) throws -> Data {
        try runUnzip(arguments: ["-p", fileURL.path, entry])
    }

    private static func runUnzip(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw SolrError.indexFailed }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private static func entryNumber(_ entry: String) -> Int {
        let digits = entry.reversed().drop { !$0.isNumber }.prefix { $0.isNumber }.reversed()
        return Int(String(digits)) ?? Int.max
    }

    private static func entrySortKey(_ entry: String) -> (Int, Int) {
        let priority = entry.hasPrefix("ppt/slides/slide") ? 0 : 1
        return (entryNumber(entry), priority)
    }

    private static func decodeText(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .unicode, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    private static func stripMarkup(_ text: String) -> String {
        let withoutScripts = regexReplace(text, pattern: "<script\\b[^>]*>.*?</script>", with: " ", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let withoutStyles = regexReplace(withoutScripts, pattern: "<style\\b[^>]*>.*?</style>", with: " ", options: [.caseInsensitive, .dotMatchesLineSeparators])
        return regexReplace(withoutStyles, pattern: "<[^>]+>", with: " ")
            .replacing("&nbsp;", with: " ")
            .replacing("&amp;", with: "&")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&quot;", with: "\"")
    }

    private static func normalizeText(_ text: String) -> String {
        let normalizedNewlines = regexReplace(text, pattern: "\\r\\n?", with: "\n")
        let normalizedSpaces = regexReplace(normalizedNewlines, pattern: "[ \\t\\u{00a0}]+", with: " ")
        return regexReplace(normalizedSpaces, pattern: "\\n{3,}", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractXLSXCellText(from raw: String, sharedStrings: [String]) -> [String] {
        regexCaptureGroups(raw, pattern: "<c([^>]*)>\\s*<v>([^<]+)</v>\\s*</c>", options: [.dotMatchesLineSeparators])
            .compactMap { groups -> String? in
                guard groups.count == 2 else { return nil }
                let attributes = groups[0]
                let value = groups[1]
                if attributes.contains("t=\"s\""), let idx = Int(value), sharedStrings.indices.contains(idx) {
                    return sharedStrings[idx]
                }
                return value
            }
    }

    private static func regexReplace(_ text: String, pattern: String, with replacement: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func regexCaptureGroups(_ text: String, pattern: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (1..<match.numberOfRanges).compactMap { idx in
                guard let range = Range(match.range(at: idx), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "rtf": return "application/rtf"
        case "html", "htm": return "text/html"
        case "xml": return "application/xml"
        case "json": return "application/json"
        case "csv", "tsv": return "text/csv"
        case "epub": return "application/epub+zip"
        case "odt": return "application/vnd.oasis.opendocument.text"
        case "ods": return "application/vnd.oasis.opendocument.spreadsheet"
        case "odp": return "application/vnd.oasis.opendocument.presentation"
        case "md", "markdown": return "text/markdown"
        default: return "text/plain"
        }
    }

    func commit() async throws {
        let urlStr = "\(baseURL)/update?commit=true&wt=json"
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        _ = try await URLSession.shared.data(for: request)
    }

    func docCount() async throws -> Int {
        let urlStr = "\(baseURL)/select?q=*:*&rows=0&wt=json"
        guard let url = URL(string: urlStr) else { return 0 }
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let response = json["response"] as? [String: Any] ?? [:]
        return response["numFound"] as? Int ?? 0
    }

    func deleteAll() async throws {
        let urlStr = "\(baseURL)/update?commit=true&wt=json"
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"delete\":{\"query\":\"*:*\"}}".data(using: .utf8)
        _ = try await URLSession.shared.data(for: request)
    }

    func deleteFolder(path: String) async throws {
        let paths = try await documentPaths(inFolder: path)
        guard !paths.isEmpty else { return }

        let query = paths
            .map { "file_path:\"\(Self.escapeQueryPhrase($0))\"" }
            .joined(separator: " OR ")
        let body: [String: Any] = [
            "delete": [
                "query": query
            ]
        ]

        guard var components = URLComponents(string: "\(baseURL)/update") else { throw SolrError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "commit", value: "true"),
            URLQueryItem(name: "wt", value: "json")
        ]
        guard let url = components.url else { throw SolrError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: request)
        try await commit()
    }

    private func documentPaths(inFolder path: String) async throws -> [String] {
        let normalized = path.hasSuffix("/") ? path : "\(path)/"
        guard var components = URLComponents(string: "\(baseURL)/select") else { throw SolrError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "q", value: "*:*"),
            URLQueryItem(name: "rows", value: "100000"),
            URLQueryItem(name: "fl", value: "id,file_path"),
            URLQueryItem(name: "wt", value: "json")
        ]
        guard let url = components.url else { throw SolrError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let response = json["response"] as? [String: Any] ?? [:]
        let docs = response["docs"] as? [[String: Any]] ?? []
        return docs.compactMap { doc in
            guard let filePath = doc["file_path"] as? String,
                  filePath.hasPrefix(normalized) else { return nil }
            return filePath
        }
    }

    private static func escapeQueryPhrase(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum SolrError: Error, LocalizedError {
    case invalidURL
    case indexFailed
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 Solr URL"
        case .indexFailed: return "索引失败"
        case .commandFailed(let message): return message.isEmpty ? "Solr 命令失败" : message
        }
    }

}

private final class PPTXTextParser: NSObject, XMLParserDelegate {
    private var isInTextRun = false
    private var currentText = ""
    private var fragments: [String] = []

    static func parse(_ data: Data) -> String {
        let delegate = PPTXTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "a:t" || elementName == "t" {
            isInTextRun = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInTextRun {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "a:t" || elementName == "t" {
            fragments.append(currentText)
            currentText = ""
            isInTextRun = false
        }
    }
}

private final class XMLTextParser: NSObject, XMLParserDelegate {
    private let textElements: Set<String>
    private var isInTextElement = false
    private var currentText = ""
    private var values: [String] = []

    init(textElements: Set<String> = []) {
        self.textElements = textElements
    }

    static func parse(_ data: Data, textElements: Set<String> = []) -> String {
        fragments(data, textElements: textElements).joined(separator: " ")
    }

    static func fragments(_ data: Data, textElements: Set<String> = []) -> [String] {
        let delegate = XMLTextParser(textElements: textElements)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if !textElements.isEmpty && textElements.contains(elementName) {
            isInTextElement = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if textElements.isEmpty {
            values.append(string)
        } else if isInTextElement {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !textElements.isEmpty && textElements.contains(elementName) {
            values.append(currentText)
            currentText = ""
            isInTextElement = false
        }
    }
}
