import SwiftUI
import AppKit

struct LivePreviewView: View {
    let result: SearchResult
    let searchOptions: SearchOptions

    @State private var copied = false

    private var previewContent: String {
        var content = result.content.isEmpty ? result.snippet : result.content
        content = content.replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: "")
        return String(content.prefix(20000))
    }

    private var paragraphs: [PreviewParagraph] {
        let raw = previewContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let chunks = raw.isEmpty ? [previewContent] : raw
        return chunks.enumerated().map { idx, text in
            PreviewParagraph(id: idx, text: text, hasMatch: paragraphHasMatch(text))
        }
    }

    private var firstMatchID: Int? {
        paragraphs.first(where: \.hasMatch)?.id
    }

    private var scrollTrigger: String {
        "\(result.id)-\(searchOptions.trimmedQuery)-\(searchOptions.usesRegex)-\(searchOptions.fuzzySpaces)"
    }

    private func highlightedParagraph(_ content: String) -> AttributedString {
        var attributed = AttributedString(content)
        attributed.font = .system(.body, design: .monospaced)
        attributed.foregroundColor = .primary

        if searchOptions.usesRegex {
            highlightRegex(in: content, attributed: &attributed)
        } else {
            highlightTerms(in: content, attributed: &attributed)
        }
        return attributed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title.isEmpty ? result.fileName : result.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(result.filePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    let text = result.content.isEmpty ? result.snippet : result.content
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制全文", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(paragraphs) { paragraph in
                            Text(highlightedParagraph(paragraph.text))
                                .textSelection(.enabled)
                                .padding(.horizontal, 14)
                                .padding(.vertical, paragraph.hasMatch ? 6 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(paragraph.hasMatch ? Color.yellow.opacity(0.08) : Color.clear)
                                )
                                .id(paragraph.id)
                        }
                    }
                    .padding(.vertical, 14)
                }
                .onAppear { scrollToFirstMatch(proxy) }
                .onChange(of: scrollTrigger) { _, _ in scrollToFirstMatch(proxy) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func scrollToFirstMatch(_ proxy: ScrollViewProxy) {
        guard let firstMatchID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(firstMatchID, anchor: .center)
            }
        }
    }

    private func paragraphHasMatch(_ text: String) -> Bool {
        if searchOptions.usesRegex {
            guard let regex = try? NSRegularExpression(pattern: searchOptions.trimmedQuery, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
        }
        let lower = text.lowercased()
        let terms = searchOptions.highlightTerms.map { $0.lowercased() }
        guard !terms.isEmpty else { return false }
        if searchOptions.fuzzySpaces && terms.count > 1 {
            return containsTermsInOrder(terms, in: lower)
        }
        return terms.contains { lower.contains($0) }
    }

    private func containsTermsInOrder(_ terms: [String], in text: String) -> Bool {
        var searchStart = text.startIndex
        for term in terms {
            guard let range = text.range(of: term, range: searchStart..<text.endIndex) else { return false }
            searchStart = range.upperBound
        }
        return true
    }

    private func highlightTerms(in content: String, attributed: inout AttributedString) {
        let lower = content.lowercased()
        for term in searchOptions.highlightTerms where !term.isEmpty {
            let termLower = term.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: termLower, range: searchStart..<lower.endIndex) {
                applyHighlight(range, in: content, to: &attributed)
                searchStart = range.upperBound
            }
        }
    }

    private func highlightRegex(in content: String, attributed: inout AttributedString) {
        guard let regex = try? NSRegularExpression(pattern: searchOptions.trimmedQuery, options: [.caseInsensitive]) else { return }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        for match in regex.matches(in: content, range: range) {
            guard let swiftRange = Range(match.range, in: content) else { continue }
            applyHighlight(swiftRange, in: content, to: &attributed)
        }
    }

    private func applyHighlight(_ range: Range<String.Index>, in content: String, to attributed: inout AttributedString) {
        let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
        let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
        if let s = attrStart, let e = attrEnd {
            attributed[s..<e].backgroundColor = .yellow.opacity(0.42)
            attributed[s..<e].font = .system(.body, design: .monospaced).bold()
        }
    }
}

private struct PreviewParagraph: Identifiable {
    let id: Int
    let text: String
    let hasMatch: Bool
}
