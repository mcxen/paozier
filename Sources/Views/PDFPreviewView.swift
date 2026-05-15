import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let filePath: String

    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    private var isTextFile: Bool {
        ["txt", "md", "markdown", "json", "xml", "csv", "tsv", "html", "htm", "rtf", "log", "yaml", "yml", "toml", "ini", "conf", "sh", "py", "js", "swift", "java", "c", "h", "cpp"].contains(fileExtension)
    }

    var body: some View {
        if isTextFile {
            TextFilePreview(filePath: filePath)
        } else if let doc = PDFDocument(url: URL(fileURLWithPath: filePath)) {
            PDFKitView(document: doc)
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
        (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? "无法读取文件内容"
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

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

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
    }
}
