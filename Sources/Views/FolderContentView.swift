import SwiftUI
import AppKit

struct FolderContentView: View {
    let folder: IndexedFolder

    @State private var files: [URL] = []
    @State private var selectedFile: URL?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text("\(files.count) 个支持文件")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        reloadFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("刷新")
                }
                .padding(10)
                .background(.regularMaterial)

                Divider()

                if files.isEmpty {
                    ContentUnavailableView("没有可预览文件", systemImage: "doc.questionmark")
                } else {
                    List(files, id: \.path, selection: $selectedFile) { file in
                        FolderFileRow(fileURL: file)
                            .tag(file)
                            .contextMenu {
                                Button("打开文件") { NSWorkspace.shared.open(file) }
                                Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "") }
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 260, idealWidth: 320)

            VStack(spacing: 0) {
                if let selectedFile {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(selectedFile.lastPathComponent)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(selectedFile.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(selectedFile)
                        } label: {
                            Label("打开", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            NSWorkspace.shared.selectFile(selectedFile.path, inFileViewerRootedAtPath: "")
                        } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(.regularMaterial)

                    Divider()

                    PDFPreviewView(filePath: selectedFile.path)
                } else {
                    ContentUnavailableView("选择文件预览", systemImage: "doc.text.magnifyingglass")
                }
            }
            .frame(minWidth: 420)
        }
        .onAppear(perform: reloadFiles)
        .onChange(of: folder.id) { _, _ in reloadFiles() }
    }

    private func reloadFiles() {
        files = Self.findFiles(in: URL(fileURLWithPath: folder.path))
        if selectedFile == nil || !files.contains(where: { $0.path == selectedFile?.path }) {
            selectedFile = files.first
        }
    }

    private static func findFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if SolrManager.supportedExtensions.contains(url.pathExtension.lowercased()) {
                urls.append(url)
            }
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

private struct FolderFileRow: View {
    let fileURL: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileURL.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text(fileURL.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch fileURL.pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc", "odt": return "doc.fill"
        case "xlsx", "xls", "csv", "tsv", "ods": return "tablecells.fill"
        case "pptx", "ppt", "odp": return "rectangle.fill.on.rectangle.fill"
        case "html", "htm", "epub": return "globe"
        default: return "doc.text.fill"
        }
    }

    private var color: Color {
        switch fileURL.pathExtension.lowercased() {
        case "pdf": return .red
        case "docx", "doc", "odt": return .blue
        case "xlsx", "xls", "csv", "tsv", "ods": return .green
        case "pptx", "ppt", "odp": return .orange
        case "html", "htm", "epub": return .purple
        default: return .gray
        }
    }
}
