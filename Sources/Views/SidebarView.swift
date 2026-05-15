import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var solrManager: SolrManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paozier")
                        .font(.headline)
                    Text("全文搜索")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            List {
                // Engine status
                Section {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(solrManager.isRunning ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Circle()
                                .fill(solrManager.isRunning ? .green : .red)
                                .frame(width: 8, height: 8)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(solrManager.isRunning ? "运行中" : "已停止")
                                .font(.callout.weight(.medium))
                            Text("\(solrManager.totalDocs) 个文档已索引")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                if solrManager.isRunning {
                                    await solrManager.stopSolr()
                                } else {
                                    await solrManager.startSolr()
                                }
                            }
                        } label: {
                            Image(systemName: solrManager.isEngineBusy ? "hourglass" : (solrManager.isRunning ? "stop.circle" : "play.circle.fill"))
                                .font(.title3)
                                .foregroundStyle(solrManager.isRunning ? .red : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(solrManager.isEngineBusy)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("引擎", systemImage: "gearshape")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Indexed folders
                Section {
                    ForEach(solrManager.indexedFolders) { folder in
                        Button {
                            solrManager.selectedFolder = folder
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue.opacity(0.7))
                                    .font(.callout)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                                        .font(.callout)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(folder.fileCount) 文件")
                                            .font(.caption2)
                                        if let date = folder.lastIndexed {
                                            Text("·")
                                            Text(date, style: .relative)
                                                .font(.caption2)
                                        }
                                    }
                                    .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("查看内容") { solrManager.selectedFolder = folder }
                            Button("重新索引") { Task { await solrManager.indexFolder(folder) } }
                            Button("刷新文件数量") { solrManager.refreshFolderCounts() }
                            Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path) }
                        }
                    }

                    Button {
                        solrManager.addFolder()
                    } label: {
                        Label("添加文件夹", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                } header: {
                    Label("文件夹", systemImage: "folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Progress
                if solrManager.isIndexing {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: solrManager.indexProgress)
                                .tint(.blue)
                            Text(solrManager.statusMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Label("进度", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                // Supported formats
                Section {
                    Text("PDF · Word · Excel · PPT · TXT · Markdown · HTML · RTF · JSON · XML · CSV · EPUB · ODF")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                } header: {
                    Label("支持格式", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220, idealWidth: 250)
        .task {
            await solrManager.refreshStatus()
        }
    }
}
