import SwiftUI
import PDFKit
import QuickLookUI

struct PDFPreviewView: View {
    let filePath: String
    var searchTerms: [String] = []
    var primaryNavigationStep: Int = 0
    var secondarySearchTerms: [String] = []
    var secondaryNavigationStep: Int = 0

    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    private var isTextFile: Bool {
        ["txt", "md", "markdown", "json", "xml", "csv", "tsv", "html", "htm", "rtf", "log", "yaml", "yml", "toml", "ini", "conf", "sh", "py", "js", "swift", "java", "c", "h", "cpp"].contains(fileExtension)
    }

    var body: some View {
        let url = URL(fileURLWithPath: filePath)
        if isTextFile {
            TextFilePreviewNS(
                filePath: filePath,
                searchTerms: searchTerms,
                primaryNavigationStep: primaryNavigationStep,
                secondarySearchTerms: secondarySearchTerms,
                secondaryNavigationStep: secondaryNavigationStep
            )
        } else if fileExtension == "docx" {
            DocxPreviewNS(
                filePath: filePath,
                searchTerms: searchTerms,
                primaryNavigationStep: primaryNavigationStep,
                secondarySearchTerms: secondarySearchTerms,
                secondaryNavigationStep: secondaryNavigationStep
            )
        } else if fileExtension == "pdf", let doc = PDFDocument(url: url) {
            PDFKitView(
                document: doc,
                searchTerms: searchTerms,
                primaryNavigationStep: primaryNavigationStep,
                secondarySearchTerms: secondarySearchTerms,
                secondaryNavigationStep: secondaryNavigationStep
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if FileManager.default.fileExists(atPath: filePath) {
            QuickLookPreview(fileURL: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("无法加载文件")
                    .foregroundStyle(.secondary)
                Text(filePath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TextFilePreview: View {
    let filePath: String

    private var content: String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return "无法读取文件内容" }
        for encoding in [String.Encoding.utf8, .unicode, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return "无法识别文本编码"
    }

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// NSTextView-based text preview with keyword highlight and auto-scroll
struct TextFilePreviewNS: NSViewRepresentable {
    let filePath: String
    let searchTerms: [String]
    var primaryNavigationStep: Int = 0
    var secondarySearchTerms: [String] = []
    var secondaryNavigationStep: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        let content = loadContent()
        let storage = NSMutableAttributedString(string: content, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ])

        let primaryRanges = ranges(for: searchTerms, in: content)
        let secondaryRanges = ranges(for: secondarySearchTerms, in: content)

        for nsRange in primaryRanges {
            storage.addAttribute(.backgroundColor, value: NSColor.yellow, range: nsRange)
        }
        for nsRange in secondaryRanges {
            storage.addAttribute(.backgroundColor, value: NSColor.systemCyan.withAlphaComponent(0.55), range: nsRange)
            storage.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
        }

        textView.textStorage?.setAttributedString(storage)

        let targetRanges = secondarySearchTerms.isEmpty ? primaryRanges : secondaryRanges
        if !targetRanges.isEmpty {
            let step = secondarySearchTerms.isEmpty ? primaryNavigationStep : secondaryNavigationStep
            let idx = ((step % targetRanges.count) + targetRanges.count) % targetRanges.count
            let range = targetRanges[idx]
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }

    private func ranges(for terms: [String], in content: String) -> [NSRange] {
        var found: [NSRange] = []
        for term in terms where !term.isEmpty {
            let lower = content.lowercased()
            let termLower = term.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: termLower, range: searchStart..<lower.endIndex) {
                let nsRange = NSRange(range, in: content)
                found.append(nsRange)
                searchStart = range.upperBound
            }
        }
        return found.sorted { $0.location < $1.location }
    }

    private func loadContent() -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return "无法读取文件内容" }
        for encoding in [String.Encoding.utf8, .unicode, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return "无法识别文本编码"
    }
}

/// Word .docx preview with keyword highlight and auto-scroll
struct DocxPreviewNS: NSViewRepresentable {
    let filePath: String
    let searchTerms: [String]
    var primaryNavigationStep: Int = 0
    var secondarySearchTerms: [String] = []
    var secondaryNavigationStep: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        let content = extractDocxContent()
        let storage = NSMutableAttributedString(string: content, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.textColor
        ])

        let primaryRanges = ranges(for: searchTerms, in: content)
        let secondaryRanges = ranges(for: secondarySearchTerms, in: content)

        for nsRange in primaryRanges {
            storage.addAttribute(.backgroundColor, value: NSColor.yellow, range: nsRange)
        }
        for nsRange in secondaryRanges {
            storage.addAttribute(.backgroundColor, value: NSColor.systemCyan.withAlphaComponent(0.55), range: nsRange)
            storage.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
        }

        textView.textStorage?.setAttributedString(storage)

        let targetRanges = secondarySearchTerms.isEmpty ? primaryRanges : secondaryRanges
        if !targetRanges.isEmpty {
            let step = secondarySearchTerms.isEmpty ? primaryNavigationStep : secondaryNavigationStep
            let idx = ((step % targetRanges.count) + targetRanges.count) % targetRanges.count
            textView.setSelectedRange(targetRanges[idx])
            textView.scrollRangeToVisible(targetRanges[idx])
        }
    }

    private func ranges(for terms: [String], in content: String) -> [NSRange] {
        var found: [NSRange] = []
        let lower = content.lowercased()
        for term in terms where !term.isEmpty {
            let termLower = term.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: termLower, range: searchStart..<lower.endIndex) {
                found.append(NSRange(range, in: content))
                searchStart = range.upperBound
            }
        }
        return found.sorted { $0.location < $1.location }
    }

    private func extractDocxContent() -> String {
        let url = URL(fileURLWithPath: filePath)
        guard let entries = try? unzipEntries(in: url) else { return "无法读取文档" }
        let prefixes = ["word/document", "word/header", "word/footer"]
        let contentEntries = entries
            .filter { e in e.hasSuffix(".xml") && prefixes.contains(where: { e.hasPrefix($0) }) }
            .sorted()
        let parts = contentEntries.compactMap { entry -> String? in
            guard let data = try? unzipData(from: url, entry: entry) else { return nil }
            return DocxPreviewParser.parse(data)
        }
        return parts.joined(separator: "\n\n")
    }

    private func unzipEntries(in fileURL: URL) throws -> [String] {
        let data = try runProcess(["-Z1", fileURL.path])
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }

    private func unzipData(from fileURL: URL, entry: String) throws -> Data {
        try runProcess(["-p", fileURL.path, entry])
    }

    private func runProcess(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

/// Simple parser for docx XML that preserves paragraph breaks
private final class DocxPreviewParser: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var currentParagraph = ""
    private var inParagraph = false

    static func parse(_ data: Data) -> String {
        let delegate = DocxPreviewParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.paragraphs.joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = element.split(separator: ":").last.map(String.init) ?? element
        if local == "p" { inParagraph = true; currentParagraph = "" }
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

final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?

    init(url: URL) {
        previewItemURL = url
    }
}

struct QuickLookPreview: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = PreviewItem(url: fileURL)
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = PreviewItem(url: fileURL)
        nsView.refreshPreviewItem()
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    var searchTerms: [String] = []
    var primaryNavigationStep: Int = 0
    var secondarySearchTerms: [String] = []
    var secondaryNavigationStep: Int = 0

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        // Highlight and scroll to first match
        nsView.highlightedSelections = nil
        guard let doc = nsView.document else { return }
        var allSelections: [PDFSelection] = []
        var primarySelections: [PDFSelection] = []
        var secondarySelections: [PDFSelection] = []
        for term in searchTerms where !term.isEmpty {
            let selections = doc.findString(term, withOptions: .caseInsensitive)
            for sel in selections {
                sel.color = .yellow
                primarySelections.append(sel)
                allSelections.append(sel)
            }
        }
        for term in secondarySearchTerms where !term.isEmpty {
            let selections = doc.findString(term, withOptions: .caseInsensitive)
            for sel in selections {
                sel.color = NSColor.systemCyan.withAlphaComponent(0.65)
                secondarySelections.append(sel)
                allSelections.append(sel)
            }
        }
        if !allSelections.isEmpty {
            nsView.highlightedSelections = allSelections
        }
        let targetSelections = secondarySearchTerms.isEmpty ? primarySelections : secondarySelections
        if !targetSelections.isEmpty {
            let step = secondarySearchTerms.isEmpty ? primaryNavigationStep : secondaryNavigationStep
            let idx = ((step % targetSelections.count) + targetSelections.count) % targetSelections.count
            nsView.setCurrentSelection(targetSelections[idx], animate: true)
            nsView.scrollSelectionToVisible(nil)
        }
    }
}
