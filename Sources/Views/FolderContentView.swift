import SwiftUI
import AppKit

struct FolderContentView: View {
    @EnvironmentObject var indexManager: IndexManager
    let folder: IndexedFolder

    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var fileActionMessage = ""

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(LF("%d 个支持文件", files.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { reloadFiles() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L("刷新"))
                }
                .padding(10)
                .background(.regularMaterial)

                Divider()

                if files.isEmpty {
                    ContentUnavailableView(L("没有可预览文件"), systemImage: "doc.questionmark")
                } else {
                    List(files, id: \.path, selection: $selectedFile) { file in
                        FolderFileRow(fileURL: file)
                            .tag(file)
                            .contextMenu {
                                Button(L("打开文件")) { NSWorkspace.shared.open(file) }
                                Button(L("在 Finder 中显示")) { NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "") }
                                if indexManager.isImageFile(file) {
                                    Button(L("执行图片 OCR 索引")) {
                                        Task {
                                            await indexManager.indexImageOCRFile(file, in: folder)
                                            fileActionMessage = indexManager.statusMessage
                                        }
                                    }
                                }
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
                        if indexManager.isImageFile(selectedFile) {
                            Button {
                                Task {
                                    await indexManager.indexImageOCRFile(selectedFile, in: folder)
                                    fileActionMessage = indexManager.statusMessage
                                }
                            } label: {
                                Label(L("执行图片 OCR 索引"), systemImage: "text.viewfinder")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(L("仅图片文件支持该操作"))
                        }
                        Button { NSWorkspace.shared.open(selectedFile) } label: {
                            Label(L("打开"), systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button { NSWorkspace.shared.selectFile(selectedFile.path, inFileViewerRootedAtPath: "") } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(.regularMaterial)

                    Divider()
                    if !fileActionMessage.isEmpty {
                        HStack {
                            Text(fileActionMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.035))
                        Divider()
                    }
                    PDFPreviewView(filePath: selectedFile.path)
                } else {
                    ContentUnavailableView(L("选择文件预览"), systemImage: "doc.text.magnifyingglass")
                }
            }
            .frame(minWidth: 420)
        }
        .onAppear(perform: reloadFiles)
        .onChange(of: folder.id) { _, _ in reloadFiles() }
        .onChange(of: selectedFile?.path) { _, _ in fileActionMessage = "" }
    }

    private func reloadFiles() {
        files = indexManager.files(in: folder)
        if selectedFile == nil || !files.contains(where: { $0.path == selectedFile?.path }) {
            selectedFile = files.first
        }
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
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif", "webp": return "photo"
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
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif", "webp": return .pink
        default: return .gray
        }
    }
}
