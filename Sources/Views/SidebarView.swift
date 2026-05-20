import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var indexManager: IndexManager
    @Binding var activePane: ContentView.MainPane
    @State private var showServices = false
    @State private var showFormats = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            paneTabs
            Divider()

            List {
                Section { statusCard } header: { sectionLabel(L("引擎"), "gearshape") }

                Section {
                    ForEach(indexManager.indexedFolders) { folder in
                        folderRow(folder)
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(L("查看文件")) { indexManager.selectedFolder = folder }
                            Button(L("重新索引")) { Task { await indexManager.indexFolder(folder) } }
                            Button(L("刷新文件数量")) { indexManager.refreshFolderCounts() }
                            Button(L("移除")) { indexManager.removeFolder(folder) }
                            Button(L("在 Finder 中显示")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path) }
                        }
                    }

                    Button { indexManager.addFolder() } label: {
                        Label(L("添加文件夹"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                } header: { foldersHeader }

                Section {
                    DisclosureGroup(isExpanded: $showServices) {
                        serviceRow("HTTP", port: indexManager.httpServer.port, isOn: Binding(get: { indexManager.httpRunning }, set: { $0 ? indexManager.startHTTP() : indexManager.stopHTTP() }))
                        if indexManager.httpRunning {
                            Link(L("打开网页搜索"), destination: URL(string: "http://localhost:\(indexManager.httpServer.port)")!)
                                .font(.caption)
                        }
                        serviceRow("MCP", port: indexManager.mcpServer.port, isOn: Binding(get: { indexManager.mcpRunning }, set: { $0 ? indexManager.startMCP() : indexManager.stopMCP() }))
                    } label: {
                        Label(L("服务"), systemImage: "network")
                            .font(.caption.weight(.semibold))
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showFormats) {
                        Text("PDF · Word · TXT · MD · HTML · JSON · XML · CSV · RTF · EPUB · \(L("代码文件"))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Label(L("支持格式"), systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220, idealWidth: 250)
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Paozier").font(.headline)
                Text("SearchKit + FTS5 + Tantivy").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { SettingsWindowController.shared.show() } label: {
                Image(systemName: "gearshape").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("设置"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var paneTabs: some View {
        HStack(spacing: 6) {
            Button {
                activePane = .search
            } label: {
                Label(L("搜索"), systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(activePane == .search ? .blue : .gray)

            Button {
                activePane = .index
            } label: {
                Label(L("索引"), systemImage: "chart.bar.doc.horizontal")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(activePane == .index ? .blue : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(indexManager.isIndexing ? Color.blue : (indexManager.isReady ? .green : .orange))
                    .frame(width: 8, height: 8)
                Text(indexManager.isIndexing ? L("索引中") : (indexManager.isReady ? L("就绪") : L("初始化")))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(indexManager.totalDocs.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if indexManager.isIndexing {
                ProgressView(value: indexManager.indexProgress)
                    .tint(.blue)
                HStack {
                    Text(indexManager.indexingFolderName.isEmpty ? indexManager.statusMessage : indexManager.indexingFolderName)
                        .lineLimit(1)
                    Spacer()
                    Text("\(indexManager.indexingFileCount)/\(indexManager.indexingTotalFiles)")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if indexManager.indexingFailedCount > 0 {
                    Text(LF("%d 个文件失败", indexManager.indexingFailedCount))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(indexManager.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var foldersHeader: some View {
        HStack {
            sectionLabel(L("文件夹"), "folder")
            Spacer()
            Button {
                Task { await indexManager.reindexAll() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
            .disabled(indexManager.isIndexing)
            .help(L("重新索引全部"))
        }
    }

    private func folderRow(_ folder: IndexedFolder) -> some View {
        let status = indexManager.status(for: folder)
        return Button {
            indexManager.selectedFolder = folder
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                            .font(.callout.weight(indexManager.selectedFolder?.id == folder.id ? .semibold : .regular))
                            .lineLimit(1)
                        if status.phase == .queued {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if status.isActive {
                            ProgressView(value: status.progress)
                                .controlSize(.mini)
                                .frame(width: 28)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(LF("%d 文件", folder.fileCount))
                        if status.phase == .queued, let queuePosition = status.queuePosition {
                            Text("·")
                            Text(LF("第 %d 个", queuePosition))
                        } else if let lastIndexed = folder.lastIndexed {
                            Text("·")
                            Text(lastIndexed, style: .relative)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func serviceRow(_ name: String, port: UInt16, isOn: Binding<Bool>) -> some View {
        HStack {
            Circle().fill(isOn.wrappedValue ? .green : .red).frame(width: 6, height: 6)
            Text(name).font(.caption)
            Spacer()
            Text(":\(port)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func sectionLabel(_ title: String, _ systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
    }
}
