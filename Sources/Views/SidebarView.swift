import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paozier").font(.headline)
                    Text("SearchKit + FTS5").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12).background(.ultraThinMaterial)
            Divider()

            List {
                Section {
                    HStack(spacing: 10) {
                        Circle().fill(indexManager.isReady ? .green : .orange).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(indexManager.statusMessage).font(.caption).lineLimit(2)
                            Text("\(indexManager.totalDocs) 个文档已索引").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: { Label("引擎", systemImage: "gearshape").font(.caption.weight(.semibold)) }

                Section {
                    ForEach(indexManager.indexedFolders) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundStyle(.blue).font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: folder.path).lastPathComponent).font(.callout).lineLimit(1)
                                Text("\(folder.fileCount) 文件").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .contextMenu {
                            Button("重新索引") { Task { await indexManager.indexFolder(folder) } }
                            Button("移除") { indexManager.removeFolder(folder) }
                        }
                    }
                    Button { indexManager.addFolder() } label: { Label("添加文件夹", systemImage: "plus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.blue)
                } header: { Label("文件夹", systemImage: "folder").font(.caption.weight(.semibold)) }

                if indexManager.isIndexing {
                    Section {
                        ProgressView(value: indexManager.indexProgress).tint(.blue)
                        Text(indexManager.statusMessage).font(.caption2).foregroundStyle(.secondary)
                    } header: { Label("进度", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold)) }
                }

                Section {
                    HStack {
                        Circle().fill(indexManager.httpRunning ? .green : .red).frame(width: 6, height: 6)
                        Text("HTTP").font(.caption)
                        Spacer()
                        Text(":\(indexManager.httpServer.port)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(get: { indexManager.httpRunning }, set: { $0 ? indexManager.startHTTP() : indexManager.stopHTTP() }))
                            .toggleStyle(.switch).controlSize(.mini)
                    }
                    if indexManager.httpRunning {
                        Link("打开网页搜索", destination: URL(string: "http://localhost:\(indexManager.httpServer.port)")!)
                            .font(.caption)
                    }
                    HStack {
                        Circle().fill(indexManager.mcpRunning ? .green : .red).frame(width: 6, height: 6)
                        Text("MCP").font(.caption)
                        Spacer()
                        Text(":\(indexManager.mcpServer.port)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(get: { indexManager.mcpRunning }, set: { $0 ? indexManager.startMCP() : indexManager.stopMCP() }))
                            .toggleStyle(.switch).controlSize(.mini)
                    }
                } header: { Label("服务", systemImage: "network").font(.caption.weight(.semibold)) }

                Section {
                    Text("PDF · Word · TXT · MD · HTML · JSON · XML · CSV · RTF · EPUB · 代码文件")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(3)
                } header: { Label("支持格式", systemImage: "doc.on.doc").font(.caption.weight(.semibold)) }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220, idealWidth: 250)
    }
}
