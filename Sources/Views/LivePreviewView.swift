import SwiftUI
import AppKit

struct LivePreviewView: View {
    let result: SearchResult
    let searchTerms: [String]

    @State private var copied = false

    private var highlightedContent: AttributedString {
        var content = result.content.isEmpty ? result.snippet : result.content
        // Strip HTML tags from Solr highlighting
        content = content.replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: "")

        var attributed = AttributedString(content.prefix(8000))
        attributed.font = .system(.body, design: .monospaced)
        attributed.foregroundColor = .primary

        // Highlight search terms
        for term in searchTerms where !term.isEmpty {
            let lower = String(content.prefix(8000)).lowercased()
            let termLower = term.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: termLower, range: searchStart..<lower.endIndex) {
                let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
                let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
                if let s = attrStart, let e = attrEnd {
                    attributed[s..<e].backgroundColor = .yellow.opacity(0.4)
                    attributed[s..<e].font = .system(.body, design: .monospaced).bold()
                }
                searchStart = range.upperBound
            }
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

            // Content with highlighting
            ScrollView {
                Text(highlightedContent)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
