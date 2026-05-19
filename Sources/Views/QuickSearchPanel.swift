import SwiftUI
import AppKit
import PDFKit

// MARK: - Panel Controller

@MainActor
final class QuickSearchPanelController {
    static let shared = QuickSearchPanelController()
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.close()
            self.panel = nil
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = L("快速搜索")
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: QuickSearchPanelView())
            addPinAccessory(to: panel)
            applySettings()
            panel.center()
            self.panel = panel
        }
        applySettings()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applySettings() {
        guard let panel else { return }
        let pinned = AppSettings.shared.quickSearchPanelAlwaysOnTop
        panel.isFloatingPanel = pinned
        panel.level = pinned ? .floating : .normal
        panel.hidesOnDeactivate = !pinned
    }

    private func addPinAccessory(to panel: NSPanel) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = NSHostingView(rootView: QuickSearchPinButton())
        panel.addTitlebarAccessoryViewController(accessory)
    }
}

@MainActor
final class QuickSearchStatusItemController: NSObject {
    static let shared = QuickSearchStatusItemController()
    private var statusItem: NSStatusItem?

    func sync() {
        if AppSettings.shared.quickSearchMenuBarEnabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: L("快速搜索"))
                ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: L("快速搜索"))
            button.imagePosition = .imageOnly
            button.toolTip = L("打开 Paozier 快速搜索")
            button.target = self
            button.action = #selector(openQuickSearch)
        }
        statusItem = item
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func openQuickSearch() {
        QuickSearchPanelController.shared.show()
    }
}

// MARK: - SwiftUI View

private struct QuickSearchPinButton: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button {
            settings.quickSearchPanelAlwaysOnTop.toggle()
            settings.save()
            QuickSearchPanelController.shared.applySettings()
        } label: {
            Image(systemName: settings.quickSearchPanelAlwaysOnTop ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(settings.quickSearchPanelAlwaysOnTop ? Color.accentColor : .secondary)
        .help(settings.quickSearchPanelAlwaysOnTop ? L("取消固定在最前") : L("固定在最前"))
    }
}

struct QuickSearchPanelView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var hoveredResultID: String?
    @State private var pinnedResultID: String?
    @State private var hoverCloseTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索..."), text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit(search)
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text(query.isEmpty ? L("输入关键词快速搜索") : L("无结果"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { result in
                    Button { openFile(result) } label: {
                        QuickSearchResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        guard pinnedResultID == nil else { return }
                        if isHovering {
                            cancelHoverClose()
                            hoveredResultID = result.id
                        } else if hoveredResultID == result.id {
                            scheduleHoverClose(result.id)
                        }
                    }
                    .popover(isPresented: Binding(
                        get: { (pinnedResultID ?? hoveredResultID) == result.id },
                        set: { isPresented in
                            if !isPresented {
                                if pinnedResultID == result.id { pinnedResultID = nil }
                                if hoveredResultID == result.id { hoveredResultID = nil }
                            }
                        }
                    ), attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                        QuickSearchHoverPreview(
                            result: result,
                            query: query,
                            isPinned: pinnedResultID == result.id,
                            onPin: {
                                pinnedResultID = result.id
                                hoveredResultID = nil
                            },
                            onClose: {
                                if pinnedResultID == result.id { pinnedResultID = nil }
                                if hoveredResultID == result.id { hoveredResultID = nil }
                            },
                            onHoverChange: { isHovering in
                                guard pinnedResultID == nil else { return }
                                if isHovering {
                                    cancelHoverClose()
                                    hoveredResultID = result.id
                                } else if hoveredResultID == result.id {
                                    scheduleHoverClose(result.id)
                                }
                            }
                        )
                    }
                    .contextMenu {
                        Button {
                            pinnedResultID = result.id
                            hoveredResultID = nil
                        } label: {
                            Label(L("预览窗口"), systemImage: "rectangle.on.rectangle")
                        }
                        Button {
                            openFile(result)
                        } label: {
                            Label(L("打开文件"), systemImage: "arrow.up.right.square")
                        }
                        Button {
                            revealFile(result)
                        } label: {
                            Label(L("在 Finder 中显示"), systemImage: "folder")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }

    private func cancelHoverClose() {
        hoverCloseTask?.cancel()
        hoverCloseTask = nil
    }

    private func scheduleHoverClose(_ resultID: String) {
        cancelHoverClose()
        hoverCloseTask = Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if hoveredResultID == resultID {
                    hoveredResultID = nil
                }
                hoverCloseTask = nil
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        pinnedResultID = nil
        hoveredResultID = nil
        cancelHoverClose()
        Task {
            let items = await SearchEngine.shared.search(query: q, limit: 15)
            await MainActor.run { results = items; isSearching = false }
        }
    }

    private func openFile(_ result: SearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath))
    }

    private func revealFile(_ result: SearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.filePath)])
    }
}

private struct QuickSearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.caption)
                Text(result.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        let ext = URL(fileURLWithPath: result.filePath).pathExtension.lowercased()
        if ext == "pdf" { return "doc.richtext.fill" }
        if ext == "md" || ext == "markdown" { return "doc.plaintext.fill" }
        return "doc.text.fill"
    }

    private var iconColor: Color {
        URL(fileURLWithPath: result.filePath).pathExtension.lowercased() == "pdf" ? .red : .blue
    }

    private var summary: String {
        let text = result.snippet.isEmpty ? String(result.content.prefix(120)) : result.snippet
        let cleaned = QuickSearchPreviewText.clean(text)
        if !cleaned.isEmpty { return cleaned }
        if URL(fileURLWithPath: result.filePath).pathExtension.lowercased() == "pdf",
           let page = result.matchedPageIndex {
            return LF("PDF 第 %d 页附近", page + 1)
        }
        return L("局部预览")
    }
}

private struct QuickSearchHoverPreview: View {
    let result: SearchResult
    let query: String
    let isPinned: Bool
    let onPin: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
    @State private var pdfPageStep = 0

    private var fileExtension: String {
        URL(fileURLWithPath: result.filePath).pathExtension.lowercased()
    }

    private var isMarkdown: Bool {
        fileExtension == "md" || fileExtension == "markdown"
    }

    private var isPDF: Bool {
        fileExtension == "pdf"
    }

    private var previewTitle: String {
        if isPDF, let page = result.matchedPageIndex {
            return LF("PDF 第 %d 页附近", page + 1)
        }
        if isMarkdown { return L("Markdown 局部预览") }
        return L("局部预览")
    }

    private var excerpt: String {
        let source = previewSource
        let cleaned = QuickSearchPreviewText.clean(source)
        guard !cleaned.isEmpty else { return result.snippet }

        let terms = searchTerms
        if isMarkdown {
            if let range = markdownAnchorRange(in: cleaned, terms: terms) {
                return markdownExcerpt(in: cleaned, around: range)
            }
            return String(cleaned.prefix(1200))
        }

        guard let range = firstMatchRange(in: cleaned, terms: terms) else {
            return String(cleaned.prefix(900))
        }
        return excerpt(in: cleaned, around: range, radius: isPDF ? 520 : 420)
    }

    private var previewSource: String {
        if isMarkdown,
           !result.filePath.hasPrefix("http"),
           let text = try? String(contentsOf: URL(fileURLWithPath: result.filePath), encoding: .utf8) {
            return text
        }
        return result.content.isEmpty ? result.snippet : result.content
    }

    private var searchTerms: [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty && $0.count < 80 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isPDF ? "doc.richtext.fill" : (isMarkdown ? "text.alignleft" : "doc.text.magnifyingglass"))
                    .foregroundStyle(isPDF ? .red : .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(previewTitle)
                        .font(.caption.weight(.semibold))
                    Text(result.fileName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isPDF {
                    Button {
                        pdfPageStep -= 1
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .help(L("上一个匹配页面"))

                    Button {
                        pdfPageStep += 1
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(L("下一个匹配页面"))
                }
                if !isPinned {
                    Button(action: onPin) {
                        Image(systemName: "pin")
                    }
                    .buttonStyle(.borderless)
                    .help(L("固定预览"))
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(L("关闭预览"))
            }

            Divider()

            if isPDF {
                QuickSearchPDFPreview(fileURL: URL(fileURLWithPath: result.filePath), query: query, fallbackPageIndex: result.matchedPageIndex, navigationStep: pdfPageStep)
                    .frame(width: 520, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
            } else {
                ScrollView {
                    Text(previewText)
                        .textSelection(.enabled)
                        .font(isMarkdown ? .body : .system(.body, design: .monospaced))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                }
                .frame(width: 440, height: 260)
            }
        }
        .padding(12)
        .frame(width: isPDF ? 548 : 468)
        .onHover(perform: onHoverChange)
        .onChange(of: result.id) { _, _ in pdfPageStep = 0 }
        .onChange(of: query) { _, _ in pdfPageStep = 0 }
    }

    private var previewText: AttributedString {
        var attributed = markdownAwareText(excerpt)
        highlightTerms(searchTerms, in: String(attributed.characters), attributed: &attributed)
        return attributed
    }

    private func markdownAwareText(_ content: String) -> AttributedString {
        if isMarkdown,
           let rendered = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            var attributed = rendered
            attributed.foregroundColor = .primary
            return attributed
        }

        var attributed = AttributedString(content)
        attributed.foregroundColor = .primary
        return attributed
    }

    private func firstMatchRange(in content: String, terms: [String]) -> Range<String.Index>? {
        let lower = content.lowercased()
        let ranges = terms
            .map { $0.lowercased() }
            .compactMap { lower.range(of: $0) }
        return ranges.min { $0.lowerBound < $1.lowerBound }
    }

    private func markdownAnchorRange(in content: String, terms: [String]) -> Range<String.Index>? {
        let snippet = QuickSearchPreviewText.clean(result.snippet)
        let snippetAnchor = QuickSearchPreviewText.anchorText(from: snippet, terms: terms)
        if let range = QuickSearchPreviewText.range(ofNormalized: snippetAnchor, in: content) {
            return range
        }
        return firstMatchRange(in: content, terms: terms)
    }

    private func markdownExcerpt(in content: String, around range: Range<String.Index>) -> String {
        let paragraphRanges = content.paragraphRanges()
        guard !paragraphRanges.isEmpty else {
            return excerpt(in: content, around: range, radius: 520)
        }

        let hitIndex = paragraphRanges.firstIndex { paragraphRange in
            paragraphRange.overlaps(range) || paragraphRange.contains(range.lowerBound)
        } ?? 0
        let startIndex = max(paragraphRanges.startIndex, hitIndex - 2)
        let endIndex = min(paragraphRanges.endIndex - 1, hitIndex + 4)
        let start = paragraphRanges[startIndex].lowerBound
        let end = paragraphRanges[endIndex].upperBound
        let prefix = start == content.startIndex ? "" : "...\n\n"
        let suffix = end == content.endIndex ? "" : "\n\n..."
        return prefix + String(content[start..<end]) + suffix
    }

    private func excerpt(in content: String, around range: Range<String.Index>, radius: Int) -> String {
        let start = content.index(range.lowerBound, offsetBy: -radius, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: radius, limitedBy: content.endIndex) ?? content.endIndex
        let prefix = start == content.startIndex ? "" : "..."
        let suffix = end == content.endIndex ? "" : "..."
        return prefix + String(content[start..<end]) + suffix
    }

    private func highlightTerms(_ terms: [String], in content: String, attributed: inout AttributedString) {
        let lower = content.lowercased()
        for term in terms {
            let needle = term.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: needle, range: searchStart..<lower.endIndex) {
                if let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].backgroundColor = .yellow.opacity(0.7)
                    attributed[attributedRange].foregroundColor = .black
                }
                searchStart = range.upperBound
            }
        }
    }
}

private struct QuickSearchPDFPreview: NSViewRepresentable {
    let fileURL: URL
    let query: String
    let fallbackPageIndex: Int?
    let navigationStep: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: fileURL)
        goToTargetPage(in: view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != fileURL {
            view.document = PDFDocument(url: fileURL)
        }
        goToTargetPage(in: view, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func goToTargetPage(in view: PDFView, context: Context) {
        guard let document = view.document, document.pageCount > 0 else { return }
        let target = context.coordinator.resolvedPageIndex(
            fileURL: fileURL,
            query: query,
            fallbackPageIndex: fallbackPageIndex,
            navigationStep: navigationStep,
            document: document
        )
        let clampedIndex = min(max(target, 0), document.pageCount - 1)
        if let page = document.page(at: clampedIndex) {
            view.go(to: page)
        }
    }

    final class Coordinator {
        private var cachedKey = ""
        private var cachedPageIndices: [Int] = [0]

        func resolvedPageIndex(fileURL: URL, query: String, fallbackPageIndex: Int?, navigationStep: Int, document: PDFDocument) -> Int {
            let key = "\(fileURL.path)|\(query)|\(fallbackPageIndex ?? -1)|\(document.pageCount)"
            if key != cachedKey {
                let terms = query
                    .split(whereSeparator: \.isWhitespace)
                    .map { normalize(String($0)) }
                    .filter { !$0.isEmpty && $0.count < 80 }
                let matchingPages = pageIndicesFromPDFDocument(document, terms: terms)
                if let fallbackPageIndex, document.pageCount > 0 {
                    cachedPageIndices = orderedPages(matchingPages, startingAt: fallbackPageIndex)
                } else {
                    cachedPageIndices = matchingPages.isEmpty ? [0] : matchingPages
                }
                cachedKey = key
            }

            let idx = ((navigationStep % cachedPageIndices.count) + cachedPageIndices.count) % cachedPageIndices.count
            return cachedPageIndices[idx]
        }

        private func pageIndicesFromPDFDocument(_ document: PDFDocument, terms: [String]) -> [Int] {
            guard !terms.isEmpty else { return [] }
            var pageIndices: [Int] = []
            for pageIndex in 0..<document.pageCount {
                guard let pageText = document.page(at: pageIndex)?.string else { continue }
                let normalizedPageText = normalize(pageText)
                if terms.contains(where: { normalizedPageText.contains($0) }) {
                    pageIndices.append(pageIndex)
                }
            }
            return pageIndices
        }

        private func orderedPages(_ pages: [Int], startingAt fallbackPageIndex: Int) -> [Int] {
            let unique = Array(Set(pages + [fallbackPageIndex])).sorted()
            guard let start = unique.firstIndex(of: fallbackPageIndex) else { return unique }
            return Array(unique[start...]) + Array(unique[..<start])
        }

        private func normalize(_ text: String) -> String {
            text
                .lowercased()
                .replacingOccurrences(of: "\u{00a0}", with: " ")
                .replacingOccurrences(of: "\u{3000}", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
    }
}

private enum QuickSearchPreviewText {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<em>", with: "")
            .replacingOccurrences(of: "</em>", with: "")
            .replacingOccurrences(of: #"\[\[PAOZIER_PAGE_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func anchorText(from snippet: String, terms: [String]) -> String {
        let cleaned = clean(snippet)
        guard !cleaned.isEmpty else { return "" }
        let lower = cleaned.lowercased()
        let ranges = terms
            .map { $0.lowercased() }
            .compactMap { lower.range(of: $0) }
        guard let first = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return String(cleaned.prefix(40))
        }

        let start = cleaned.index(first.lowerBound, offsetBy: -24, limitedBy: cleaned.startIndex) ?? cleaned.startIndex
        let end = cleaned.index(first.upperBound, offsetBy: 36, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
        return String(cleaned[start..<end])
    }

    static func range(ofNormalized needle: String, in haystack: String) -> Range<String.Index>? {
        let normalizedNeedle = normalizedForAnchor(needle).text
        guard !normalizedNeedle.isEmpty else { return nil }

        let normalizedHaystack = normalizedForAnchor(haystack)
        guard let range = normalizedHaystack.text.range(of: normalizedNeedle) else { return nil }
        let lowerOffset = normalizedHaystack.text.distance(from: normalizedHaystack.text.startIndex, to: range.lowerBound)
        let upperOffset = normalizedHaystack.text.distance(from: normalizedHaystack.text.startIndex, to: range.upperBound)
        guard normalizedHaystack.indices.indices.contains(lowerOffset),
              normalizedHaystack.indices.indices.contains(max(upperOffset - 1, lowerOffset)) else { return nil }
        let lower = normalizedHaystack.indices[lowerOffset]
        let upperLast = normalizedHaystack.indices[max(upperOffset - 1, lowerOffset)]
        return lower..<haystack.index(after: upperLast)
    }

    private static func normalizedForAnchor(_ text: String) -> (text: String, indices: [String.Index]) {
        var output = ""
        var indices: [String.Index] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let scalarText = String(character)
            if !scalarText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !"#*`[]()!>|-_".contains(character) {
                output.append(contentsOf: scalarText.lowercased())
                indices.append(index)
            }
            index = text.index(after: index)
        }
        return (output, indices)
    }
}

private extension String {
    func paragraphRanges() -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = startIndex
        while start < endIndex {
            if let blankLine = range(of: "\n\n", range: start..<endIndex) {
                let paragraphEnd = blankLine.lowerBound
                if start < paragraphEnd {
                    ranges.append(start..<paragraphEnd)
                }
                start = blankLine.upperBound
            } else {
                ranges.append(start..<endIndex)
                break
            }
        }
        return ranges
    }
}
