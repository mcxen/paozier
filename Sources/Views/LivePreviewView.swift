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
                    Label(copied ? L("已复制") : L("复制全文"), systemImage: copied ? "checkmark" : "doc.on.doc")
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
        let html = renderHTML()
        let htmlURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("paozier-markdown-preview", isDirectory: true)
            .appendingPathComponent("\(abs(markdown.hashValue)).html")
        try? FileManager.default.createDirectory(at: htmlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? html.write(to: htmlURL, atomically: true, encoding: .utf8)
        webView.loadFileURL(htmlURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    private func renderHTML() -> String {
        let markdownJSON = jsonString(markdown)
        let basePathJSON = jsonString(baseURL.path)
        let primaryTermsJSON = json(primaryTerms)
        let secondaryTermsJSON = json(secondaryTerms)
        let markedScript = Self.markedScript
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          padding: 24px 32px 52px;
          font: 15px/1.58 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
          color: CanvasText;
          background: Canvas;
        }
        .markdown-body {
          max-width: 980px;
          margin: 0 auto;
          word-wrap: break-word;
        }
        h1, h2, h3, h4, h5, h6 {
          margin: 24px 0 16px;
          line-height: 1.25;
          font-weight: 650;
        }
        h1, h2 {
          padding-bottom: .3em;
          border-bottom: 1px solid color-mix(in srgb, CanvasText 16%, transparent);
        }
        h1 { font-size: 2em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: .875em; }
        h6 { font-size: .85em; color: color-mix(in srgb, CanvasText 64%, transparent); }
        p, blockquote, ul, ol, dl, table, pre, details { margin: 0 0 16px; }
        ul, ol { padding-left: 2em; }
        li { margin: .25em 0; }
        li > p { margin-top: 16px; }
        li + li { margin-top: .25em; }
        .contains-task-list { padding-left: 1.5em; }
        .task-list-item { list-style-type: none; }
        .task-list-item input {
          margin: 0 .45em .25em -1.4em;
          vertical-align: middle;
        }
        a { color: #0969da; text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 650; }
        code {
          font-family: "SF Mono", Menlo, monospace;
          font-size: 85%;
          padding: .2em .4em;
          border-radius: 6px;
          background: color-mix(in srgb, CanvasText 10%, transparent);
        }
        pre {
          overflow: auto;
          padding: 16px;
          border-radius: 6px;
          line-height: 1.45;
          background: color-mix(in srgb, CanvasText 8%, transparent);
        }
        pre code {
          display: block;
          padding: 0;
          overflow: visible;
          font-size: 100%;
          white-space: pre;
          background: transparent;
        }
        blockquote {
          padding: 0 1em;
          border-left: .25em solid color-mix(in srgb, CanvasText 22%, transparent);
          color: color-mix(in srgb, CanvasText 66%, transparent);
        }
        blockquote > :first-child { margin-top: 0; }
        blockquote > :last-child { margin-bottom: 0; }
        img {
          max-width: 100%;
          height: auto;
        }
        img.missing-image {
          display: inline-flex;
          min-width: 160px;
          min-height: 42px;
          padding: 10px 12px;
          border: 1px dashed color-mix(in srgb, CanvasText 28%, transparent);
          border-radius: 6px;
          color: color-mix(in srgb, CanvasText 58%, transparent);
          background: color-mix(in srgb, CanvasText 5%, transparent);
        }
        table {
          display: block;
          width: max-content;
          max-width: 100%;
          overflow: auto;
          border-spacing: 0;
          border-collapse: collapse;
        }
        th, td {
          padding: 6px 13px;
          border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
        }
        tr { background: Canvas; border-top: 1px solid color-mix(in srgb, CanvasText 16%, transparent); }
        tr:nth-child(2n) { background: color-mix(in srgb, CanvasText 4%, transparent); }
        hr {
          height: .25em;
          padding: 0;
          margin: 24px 0;
          background: color-mix(in srgb, CanvasText 14%, transparent);
          border: 0;
        }
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
        <article id="content" class="markdown-body"></article>
        <script>
        \(markedScript)
        </script>
        <script>
        const markdownSource = \(markdownJSON);
        const markdownBasePath = \(basePathJSON);
        const primaryTerms = \(primaryTermsJSON);
        const secondaryTerms = \(secondaryTermsJSON);
        const markedAPI = window.marked && (window.marked.parse ? window.marked : (window.marked.marked ? window.marked.marked : null));
        markedAPI.setOptions({
          gfm: true,
          breaks: false,
          pedantic: false,
          headerIds: false,
          mangle: false
        });
        const content = document.getElementById('content');
        content.innerHTML = markedAPI.parse(markdownSource);
        sanitize(content);
        resolveMarkdownImages(content, markdownBasePath);
        document.querySelectorAll('a[href]').forEach(a => {
          a.target = '_blank';
          a.rel = 'noreferrer';
        });
        document.querySelectorAll('ul').forEach(ul => {
          if (ul.querySelector(':scope > li > input[type="checkbox"]')) ul.classList.add('contains-task-list');
        });
        document.querySelectorAll('li').forEach(li => {
          if (li.querySelector(':scope > input[type="checkbox"]')) li.classList.add('task-list-item');
        });
        function sanitize(root) {
          root.querySelectorAll('script, iframe, object, embed').forEach(el => el.remove());
          root.querySelectorAll('*').forEach(el => {
            for (const attr of [...el.attributes]) {
              const name = attr.name.toLowerCase();
              const value = attr.value.trim().toLowerCase();
              if (name.startsWith('on') || value.startsWith('javascript:')) {
                el.removeAttribute(attr.name);
              }
            }
          });
        }
        function resolveMarkdownImages(root, basePath) {
          root.querySelectorAll('img[src]').forEach(img => {
            const raw = img.getAttribute('src') || '';
            const resolved = resolveMarkdownURL(raw, basePath);
            if (resolved) img.setAttribute('src', resolved);
            img.addEventListener('error', () => {
              img.classList.add('missing-image');
              img.setAttribute('alt', img.getAttribute('alt') || raw);
            });
          });
        }
        function resolveMarkdownURL(raw, basePath) {
          let value = raw.trim().replace(/^<|>$/g, '').replace(/^['"]|['"]$/g, '');
          if (!value) return value;
          if (/^(https?:|data:|blob:)/i.test(value)) return value;
          if (/^file:/i.test(value)) return encodeURI(decodeURI(value));
          value = value.split('#')[0].split('?')[0] + (value.includes('?') ? '?' + value.split('?').slice(1).join('?') : '');
          try {
            if (value.startsWith('/')) return new URL('file://' + value).href;
            const base = new URL('file://' + basePath.replace(/\\/$/, '') + '/');
            return new URL(value, base).href;
          } catch (_) {
            const joined = basePath.replace(/\\/$/, '') + '/' + value.replace(/^\\.\\//, '');
            return 'file://' + joined.split('/').map((part, idx) => idx === 0 ? part : encodeURIComponent(decodeURIComponent(part))).join('/');
          }
        }
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

    private static let markedScript: String = {
        let candidates = [
            Bundle.main.url(forResource: "marked.umd", withExtension: "js"),
            Bundle.main.resourceURL?.appendingPathComponent("Paozier_Paozier.bundle/Contents/Resources/marked.umd.js"),
            Bundle.main.resourceURL?.appendingPathComponent("Paozier_Paozier.bundle/marked.umd.js"),
            Bundle.main.resourceURL?.appendingPathComponent("marked.umd.js")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let script = try? String(contentsOf: url, encoding: .utf8) {
                return script
            }
        }
        return """
        window.marked = { setOptions: function(){}, parse: function(value) {
          const escaped = String(value).replace(/[&<>]/g, function(ch) {
            return ({'&':'&amp;','<':'&lt;','>':'&gt;'}[ch]);
          });
          return escaped
            .replace(/^###\\s+(.+)$/gm, '<h3>$1</h3>')
            .replace(/^##\\s+(.+)$/gm, '<h2>$1</h2>')
            .replace(/^#\\s+(.+)$/gm, '<h1>$1</h1>')
            .replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>')
            .replace(/`([^`]+)`/g, '<code>$1</code>')
            .split(/\\n{2,}/).map(function(block) {
              return /^<h[1-6]|^<pre|^<ul|^<ol|^<blockquote|^<table/.test(block) ? block : '<p>' + block.replace(/\\n/g, '<br>') + '</p>';
            }).join('\\n');
        }};
        """
    }()

    private func json(_ terms: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: terms)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
