import SwiftUI
import Darwin

struct IndexManagementView: View {
    @EnvironmentObject var indexManager: IndexManager
    @State private var selectedFolderID: String?
    @State private var pendingFolderAction: FolderAction?

    private var selectedFolder: IndexedFolder? {
        indexManager.indexedFolders.first { $0.id == selectedFolderID } ?? indexManager.indexedFolders.first
    }

    private enum FolderAction: Identifiable {
        case clear(IndexedFolder)
        case remove(IndexedFolder)

        var id: String {
            switch self {
            case .clear(let folder): return "clear-\(folder.id)"
            case .remove(let folder): return "remove-\(folder.id)"
            }
        }

        var title: String {
            switch self {
            case .clear: return L("确认清理索引？")
            case .remove: return L("确认移除文件夹？")
            }
        }

        var message: String {
            switch self {
            case .clear: return L("会清除该文件夹在搜索引擎里的索引记录，文件夹本身和原文件不会被删除。")
            case .remove: return L("会移除该文件夹并清理对应索引，原文件不会被删除。")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusSection
                    memorySection
                    foldersSection
                }
                .padding(16)
            }
        }
        .frame(minWidth: 320)
        .onAppear {
            selectedFolderID = selectedFolderID ?? indexManager.indexedFolders.first?.id
        }
        .alert(pendingFolderAction?.title ?? "", isPresented: Binding(
            get: { pendingFolderAction != nil },
            set: { if !$0 { pendingFolderAction = nil } }
        )) {
            Button(L("取消"), role: .cancel) { pendingFolderAction = nil }
            Button(L("确认"), role: .destructive) { performPendingFolderAction() }
        } message: {
            Text(pendingFolderAction?.message ?? "")
        }
    }

    private var header: some View {
        HStack {
            Label(L("索引管理"), systemImage: "chart.bar.doc.horizontal")
                .font(.headline)
            Spacer()
            Button {
                Task { await indexManager.reindexAll() }
            } label: {
                Label(L("重建全部"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(indexManager.isIndexing)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(indexManager.isIndexing ? Color.blue : (indexManager.isReady ? .green : .orange))
                    .frame(width: 9, height: 9)
                Text(indexManager.isIndexing ? L("索引任务运行中") : L("索引就绪"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(LF("%d 个文档", indexManager.totalDocs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: indexManager.isIndexing ? indexManager.indexProgress : 1)
                .tint(indexManager.isIndexing ? .blue : .green)

            HStack {
                Text(indexManager.isIndexing ? indexManager.indexingFolderName : indexManager.statusMessage)
                    .lineLimit(1)
                Spacer()
                if indexManager.isIndexing {
                    Text("\(indexManager.indexingFileCount)/\(indexManager.indexingTotalFiles)")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var memorySection: some View {
        let snapshot = MemorySnapshot.current
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L("资源占用"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(snapshot.usedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Color.green.frame(width: geo.size.width * 0.34)
                    Color.yellow.frame(width: geo.size.width * 0.23)
                    Color.orange.frame(width: geo.size.width * 0.20)
                    Color.red.frame(width: geo.size.width * 0.14)
                    Color.purple.frame(width: geo.size.width * 0.09)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.8))
                        .frame(width: 2)
                        .offset(x: max(0, min(geo.size.width - 2, geo.size.width * snapshot.ratio)))
                }
            }
            .frame(height: 10)
            Text(L("当前进程内存 / 物理内存"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("索引结果"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { indexManager.refreshFolderCounts() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(L("刷新文件数量"))
            }

            Picker("", selection: Binding(
                get: { selectedFolderID ?? indexManager.indexedFolders.first?.id ?? "" },
                set: { selectedFolderID = $0 }
            )) {
                ForEach(indexManager.indexedFolders) { folder in
                    Text(URL(fileURLWithPath: folder.path).lastPathComponent).tag(folder.id)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            if let selectedFolder {
                VStack(spacing: 0) {
                    folderMetric(L("路径"), selectedFolder.path)
                    folderMetric(L("文件数"), "\(selectedFolder.fileCount)")
                    folderMetric(L("上次索引"), selectedFolder.lastIndexed?.formatted(date: .abbreviated, time: .shortened) ?? L("尚未完成"))
                }
                .font(.caption)
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button {
                        indexManager.selectedFolder = selectedFolder
                    } label: {
                        Label(L("查看文件"), systemImage: "folder")
                    }
                    Button {
                        Task { await indexManager.indexFolder(selectedFolder) }
                    } label: {
                        Label(L("重新索引"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(indexManager.isIndexing)
                    Button(role: .destructive) {
                        pendingFolderAction = .clear(selectedFolder)
                    } label: {
                        Label(L("清理索引"), systemImage: "trash")
                    }
                    .disabled(indexManager.isIndexing)
                    Button(role: .destructive) {
                        pendingFolderAction = .remove(selectedFolder)
                    } label: {
                        Label(L("移除文件夹"), systemImage: "minus.circle")
                    }
                    .disabled(indexManager.isIndexing)
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: selectedFolder.path)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                }
                .controlSize(.small)
            } else {
                ContentUnavailableView(L("暂无索引文件夹"), systemImage: "folder.badge.plus")
                    .frame(minHeight: 140)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func folderMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func performPendingFolderAction() {
        guard let pendingFolderAction else { return }
        switch pendingFolderAction {
        case .clear(let folder):
            Task { await indexManager.clearFolderIndex(folder) }
        case .remove(let folder):
            indexManager.removeFolder(folder)
            selectedFolderID = indexManager.indexedFolders.first?.id
        }
        self.pendingFolderAction = nil
    }
}

private struct MemorySnapshot {
    let used: UInt64
    let total: UInt64

    var ratio: Double {
        guard total > 0 else { return 0 }
        return min(Double(used) / Double(total), 1)
    }

    var usedText: String {
        "\(Self.format(used)) / \(Self.format(total))"
    }

    static var current: MemorySnapshot {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let used = result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
        return MemorySnapshot(used: used, total: ProcessInfo.processInfo.physicalMemory)
    }

    private static func format(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb < 1024 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}
