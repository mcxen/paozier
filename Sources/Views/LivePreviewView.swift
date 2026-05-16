import SwiftUI
import AppKit
import WebKit

struct LivePreviewView: View {
    let result: SearchResult
    let searchOptions: SearchOptions
    var primaryNavigationStep: Int = 0
    var secondaryQuery: String = ""
    var secondaryNavigationStep: Int = 0

    @State private var copied = false

    private var isMarkdown: Bool {
        let ext = URL(fileURLWithPath: result.filePath).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

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
            PreviewParagraph(id: idx, text: text, hasPrimaryMatch: paragraphHasPrimaryMatch(text), hasSecondaryMatch: paragraphHasSecondaryMatch(text))
        }
    }

    private var primaryMatchIDs: [Int] {
        paragraphs.filter(\.hasPrimaryMatch).map(\.id)
    }

    private var secondaryMatchIDs: [Int] {
        paragraphs.filter(\.hasSecondaryMatch).map(\.id)
    }

    private var scrollTrigger: String {
        "\(result.id)-\(searchOptions.trimmedQuery)-\(searchOptions.usesRegex)-\(searchOptions.fuzzySpaces)"
    }

    private func highlightedParagraph(_ content: String) -> AttributedString {
        var attributed = markdownAttributedString(content)

        if searchOptions.usesRegex {
            highlightRegex(in: String(attributed.characters), attributed: &attributed)
        } else {
            highlightTerms(searchOptions.highlightTerms, in: String(attributed.characters), attributed: &attributed, color: .yellow.opacity(0.68), foreground: .black)
        }
        highlightTerms(secondaryTerms, in: String(attributed.characters), attributed: &attributed, color: .cyan.opacity(0.5), foreground: .black)
        return attributed
    }

    private func markdownAttributedString(_ content: String) -> AttributedString {
        if isMarkdown,
           let rendered = try? AttributedString(markdown: normalizedMarkdownLine(content), options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            var attributed = rendered
            attributed.font = markdownFont(for: content)
            attributed.foregroundColor = .primary
            return attributed
        }

        var attributed = AttributedString(content)
        attributed.font = .system(.body, design: .monospaced)
        attributed.foregroundColor = .primary
        return attributed
    }

    private func normalizedMarkdownLine(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return trimmed.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        }
        return content
    }

    private func markdownFont(for content: String) -> Font {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") { return .title2.bold() }
        if trimmed.hasPrefix("## ") { return .title3.bold() }
        if trimmed.hasPrefix("### ") { return .headline.bold() }
        return .body
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

            if isMarkdown {
                MarkdownWebPreview(
                    markdown: previewContent,
                    baseURL: URL(fileURLWithPath: result.filePath).deletingLastPathComponent(),
                    primaryTerms: searchOptions.usesRegex ? [] : searchOptions.highlightTerms,
                    primaryNavigationStep: primaryNavigationStep,
                    secondaryTerms: secondaryTerms,
                    secondaryNavigationStep: secondaryNavigationStep
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(paragraphs) { paragraph in
                                Text(highlightedParagraph(paragraph.text))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, (paragraph.hasPrimaryMatch || paragraph.hasSecondaryMatch) ? 6 : 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(paragraph.hasPrimaryMatch ? Color.yellow.opacity(0.08) : (paragraph.hasSecondaryMatch ? Color.cyan.opacity(0.08) : Color.clear))
                                    )
                                    .id(paragraph.id)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .onAppear { scrollTo(proxy, ids: primaryMatchIDs, step: primaryNavigationStep) }
                    .onChange(of: scrollTrigger) { _, _ in scrollTo(proxy, ids: primaryMatchIDs, step: primaryNavigationStep) }
                    .onChange(of: primaryNavigationStep) { _, step in scrollTo(proxy, ids: primaryMatchIDs, step: step) }
                    .onChange(of: secondaryQuery) { _, _ in scrollTo(proxy, ids: secondaryMatchIDs, step: secondaryNavigationStep) }
                    .onChange(of: secondaryNavigationStep) { _, step in scrollTo(proxy, ids: secondaryMatchIDs, step: step) }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var secondaryTerms: [String] {
        secondaryQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func scrollTo(_ proxy: ScrollViewProxy, ids: [Int], step: Int) {
        guard !ids.isEmpty else { return }
        let idx = ((step % ids.count) + ids.count) % ids.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(ids[idx], anchor: .center)
            }
        }
    }

    private func paragraphHasPrimaryMatch(_ text: String) -> Bool {
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

    private func paragraphHasSecondaryMatch(_ text: String) -> Bool {
        let lower = text.lowercased()
        return secondaryTerms.map { $0.lowercased() }.contains { lower.contains($0) }
    }

    private func containsTermsInOrder(_ terms: [String], in text: String) -> Bool {
        var searchStart = text.startIndex
        for term in terms {
            guard let range = text.range(of: term, range: searchStart..<text.endIndex) else { return false }
            searchStart = range.upperBound
        }
        return true
    }

    private func highlightTerms(_ terms: [String], in content: String, attributed: inout AttributedString, color: Color, foreground: Color) {
        let lower = content.lowercased()
        for term in terms where !term.isEmpty {
            let termLower = term.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: termLower, range: searchStart..<lower.endIndex) {
                applyHighlight(range, in: content, to: &attributed, color: color, foreground: foreground)
                searchStart = range.upperBound
            }
        }
    }

    private func highlightRegex(in content: String, attributed: inout AttributedString) {
        guard let regex = try? NSRegularExpression(pattern: searchOptions.trimmedQuery, options: [.caseInsensitive]) else { return }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        for match in regex.matches(in: content, range: range) {
            guard let swiftRange = Range(match.range, in: content) else { continue }
            applyHighlight(swiftRange, in: content, to: &attributed, color: .yellow.opacity(0.68), foreground: .black)
        }
    }

    private func applyHighlight(_ range: Range<String.Index>, in content: String, to attributed: inout AttributedString, color: Color, foreground: Color) {
        let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
        let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
        if let s = attrStart, let e = attrEnd {
            attributed[s..<e].backgroundColor = color
            attributed[s..<e].foregroundColor = foreground
            attributed[s..<e].font = .system(.body, design: .monospaced).bold()
        }
    }
}

private struct PreviewParagraph: Identifiable {
    let id: Int
    let text: String
    let hasPrimaryMatch: Bool
    let hasSecondaryMatch: Bool
}

private struct MarkdownWebPreview: NSViewRepresentable {
    let markdown: String
    let baseURL: URL
    let primaryTerms: [String]
    let primaryNavigationStep: Int
    let secondaryTerms: [String]
    let secondaryNavigationStep: Int

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(renderHTML(), baseURL: baseURL)
    }

    private func renderHTML() -> String {
        let body = markdownToHTML(markdown)
        let primaryTermsJSON = json(primaryTerms)
        let secondaryTermsJSON = json(secondaryTerms)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        body {
          margin: 0;
          padding: 24px 28px 48px;
          font: 15px/1.62 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          color: CanvasText;
          background: Canvas;
        }
        h1, h2, h3 { line-height: 1.25; margin: 1.2em 0 .55em; font-weight: 750; }
        h1 { font-size: 28px; border-bottom: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding-bottom: 8px; }
        h2 { font-size: 22px; }
        h3 { font-size: 18px; }
        p { margin: .85em 0; }
        ul, ol { padding-left: 1.6em; }
        li { margin: .32em 0; }
        code {
          font-family: "SF Mono", Menlo, monospace;
          font-size: .92em;
          padding: 2px 4px;
          border-radius: 4px;
          background: color-mix(in srgb, CanvasText 10%, transparent);
        }
        pre {
          overflow: auto;
          padding: 12px;
          border-radius: 7px;
          background: color-mix(in srgb, CanvasText 9%, transparent);
        }
        pre code { padding: 0; background: transparent; }
        blockquote {
          margin: 1em 0;
          padding-left: 14px;
          border-left: 3px solid #6aa7ff;
          color: color-mix(in srgb, CanvasText 72%, transparent);
        }
        img {
          display: block;
          max-width: min(100%, 980px);
          height: auto;
          margin: 14px 0;
          border-radius: 6px;
        }
        table { border-collapse: collapse; max-width: 100%; overflow: auto; }
        th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 6px 8px; }
        mark.primary {
          background: #ffe66d;
          color: #111;
          border-radius: 3px;
          padding: 0 2px;
        }
        mark.secondary {
          background: #9de8ff;
          color: #07121a;
          border-radius: 3px;
          padding: 0 2px;
        }
        </style>
        </head>
        <body>
        \(body)
        <script>
        const primaryTerms = \(primaryTermsJSON);
        const secondaryTerms = \(secondaryTermsJSON);
        function walk(node, terms, className) {
          if (!terms.length || ['SCRIPT','STYLE','CODE','PRE'].includes(node.parentNode?.nodeName)) return;
          if (node.nodeType === Node.TEXT_NODE) {
            let text = node.nodeValue;
            let frag = document.createDocumentFragment();
            let lower = text.toLowerCase();
            let ranges = [];
            for (const term of terms) {
              if (!term) continue;
              let start = 0, needle = term.toLowerCase();
              while (true) {
                const idx = lower.indexOf(needle, start);
                if (idx < 0) break;
                ranges.push([idx, idx + needle.length]);
                start = idx + Math.max(needle.length, 1);
              }
            }
            ranges.sort((a,b) => a[0]-b[0]);
            let merged = [];
            for (const r of ranges) {
              if (!merged.length || r[0] > merged[merged.length-1][1]) merged.push(r);
              else merged[merged.length-1][1] = Math.max(merged[merged.length-1][1], r[1]);
            }
            if (!merged.length) return;
            let pos = 0;
            for (const [s,e] of merged) {
              if (s > pos) frag.appendChild(document.createTextNode(text.slice(pos, s)));
              const mark = document.createElement('mark');
              mark.className = className;
              mark.textContent = text.slice(s, e);
              frag.appendChild(mark);
              pos = e;
            }
            if (pos < text.length) frag.appendChild(document.createTextNode(text.slice(pos)));
            node.replaceWith(frag);
          } else {
            for (const child of [...node.childNodes]) walk(child, terms, className);
          }
        }
        walk(document.body, primaryTerms, 'primary');
        walk(document.body, secondaryTerms, 'secondary');
        function jump(selector, step) {
          const matches = [...document.querySelectorAll(selector)];
          if (!matches.length) return;
          const idx = ((step % matches.length) + matches.length) % matches.length;
          matches[idx].scrollIntoView({ block: 'center' });
        }
        jump('mark.secondary', \(secondaryNavigationStep));
        if (!secondaryTerms.length) jump('mark.primary', \(primaryNavigationStep));
        </script>
        </body>
        </html>
        """
    }

    private func json(_ terms: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: terms)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func markdownToHTML(_ markdown: String) -> String {
        var html: [String] = []
        var inCode = false
        var listOpen = false

        func closeList() {
            if listOpen {
                html.append("</ul>")
                listOpen = false
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    html.append("</code></pre>")
                    inCode = false
                } else {
                    closeList()
                    html.append("<pre><code>")
                    inCode = true
                }
                continue
            }

            if inCode {
                html.append(escapeHTML(rawLine) + "\n")
                continue
            }

            if line.isEmpty {
                closeList()
                continue
            }

            if let image = parseImage(line) {
                closeList()
                html.append(image)
            } else if line.hasPrefix("### ") {
                closeList()
                html.append("<h3>\(inlineMarkdown(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                closeList()
                html.append("<h2>\(inlineMarkdown(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                closeList()
                html.append("<h1>\(inlineMarkdown(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !listOpen {
                    html.append("<ul>")
                    listOpen = true
                }
                html.append("<li>\(inlineMarkdown(String(line.dropFirst(2))))</li>")
            } else if line.hasPrefix("> ") {
                closeList()
                html.append("<blockquote>\(inlineMarkdown(String(line.dropFirst(2))))</blockquote>")
            } else {
                closeList()
                html.append("<p>\(inlineMarkdown(line))</p>")
            }
        }
        closeList()
        if inCode { html.append("</code></pre>") }
        return html.joined(separator: "\n")
    }

    private func parseImage(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let altRange = Range(match.range(at: 1), in: line),
              let srcRange = Range(match.range(at: 2), in: line) else { return nil }
        let alt = escapeHTML(String(line[altRange]))
        let src = escapeAttribute(String(line[srcRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        return #"<img alt="\#(alt)" src="\#(src)">"#
    }

    private func inlineMarkdown(_ text: String) -> String {
        var html = escapeHTML(text)
        html = replace(html, pattern: #"`([^`]+)`"#, template: #"<code>$1</code>"#)
        html = replace(html, pattern: #"\*\*([^*]+)\*\*"#, template: #"<strong>$1</strong>"#)
        html = replace(html, pattern: #"\*([^*]+)\*"#, template: #"<em>$1</em>"#)
        return html
    }

    private func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: template)
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
