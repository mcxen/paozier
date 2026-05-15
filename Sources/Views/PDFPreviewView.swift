import SwiftUI
import PDFKit
import QuickLookUI

struct PDFPreviewView: View {
    let filePath: String

    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    private var isTextFile: Bool {
        ["txt", "md", "markdown", "json", "xml", "csv", "tsv", "html", "htm", "rtf", "log", "yaml", "yml", "toml", "ini", "conf", "sh", "py", "js", "swift", "java", "c", "h", "cpp"].contains(fileExtension)
    }

    var body: some View {
        let url = URL(fileURLWithPath: filePath)
        if isTextFile {
            TextFilePreview(filePath: filePath)
        } else if fileExtension == "pdf", let doc = PDFDocument(url: url) {
            PDFKitView(document: doc)
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
