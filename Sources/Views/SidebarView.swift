import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var solrManager: SolrManager

    var body: some View {
        List {
            Section("引擎状态") {
                HStack {
                    Circle()
                        .fill(solrManager.isRunning ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(solrManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("索引文档")
                        .font(.caption)
                    Spacer()
                    Text("\(solrManager.totalDocs)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !solrManager.isRunning {
                    Button("启动 Solr") {
                        Task { await solrManager.startSolr() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("停止") {
                        solrManager.stopSolr()
                    }
                    .controlSize(.small)
                }
            }

            Section("索引文件夹") {
                ForEach(solrManager.indexedFolders) { folder in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.path.components(separatedBy: "/").suffix(2).joined(separator: "/"))
                            .font(.caption)
                            .lineLimit(1)
                        HStack {
                            Text("\(folder.fileCount) PDF")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let date = folder.lastIndexed {
                                Text(date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("重新索引") {
                            Task { await solrManager.indexFolder(folder) }
                        }
                    }
                }

                Button {
                    solrManager.addFolder()
                } label: {
                    Label("添加文件夹", systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
            }

            if solrManager.isIndexing {
                Section("索引进度") {
                    ProgressView(value: solrManager.indexProgress)
                    Text(solrManager.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}
