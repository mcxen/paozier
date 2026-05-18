import SwiftUI
import Darwin

struct IndexManagementView: View {
    @EnvironmentObject var indexManager: IndexManager
    @State private var selectedFolderID: String?
    @State private var pendingFolderAction: FolderAction?
    @State private var infoFolderID: String?
    @State private var visibleFolderCount = 20

    private let pageSize = 20

    private var infoFolder: IndexedFolder? {
        guard let infoFolderID else { return nil }
        return indexManager.indexedFolders.first(where: { $0.id == infoFolderID })
    }

    private var visibleFolders: [IndexedFolder] {
        Array(indexManager.indexedFolders.prefix(visibleFolderCount))
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
        .frame(minWidth: 420)
        .onAppear {
            selectedFolderID = selectedFolderID ?? indexManager.indexedFolders.first?.id
            visibleFolderCount = max(pageSize, min(visibleFolderCount, indexManager.indexedFolders.count))
        }
        .onChange(of: indexManager.indexedFolders.map(\.id)) { _, ids in
            if let selectedFolderID, !ids.contains(selectedFolderID) {
                self.selectedFolderID = ids.first
            }
            if let infoFolderID, !ids.contains(infoFolderID) {
                self.infoFolderID = nil
            }
            visibleFolderCount = min(max(pageSize, visibleFolderCount), max(pageSize, ids.count))
        }
        .sheet(isPresented: Binding(
            get: { infoFolder != nil },
            set: { if !$0 { infoFolderID = nil } }
        )) {
            if let infoFolder {
                FolderIndexInfoView(
                    folder: infoFolder,
                    status: indexManager.status(for: infoFolder),
                    isActive: indexManager.isActiveFolder(infoFolder),
                    onReindex: { Task { await indexManager.indexFolder(infoFolder) } },
                    onClear: { pendingFolderAction = .clear(infoFolder) },
                    onReveal: { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: infoFolder.path) }
                )
            }
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
        HStack(spacing: 10) {
            Label(L("索引管理"), systemImage: "chart.bar.doc.horizontal")
                .font(.headline)
            Spacer()
            Button {
                indexManager.addFolder()
            } label: {
                Label(L("添加文件夹"), systemImage: "plus")
            }
            .controlSize(.small)

            Button {
                indexManager.refreshFolderCounts()
            } label: {
                Label(L("刷新"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button {
                Task { await indexManager.reindexAll() }
            } label: {
                Label(L("重建全部"), systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .disabled(indexManager.isIndexing)
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

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(indexManager.isIndexing ? indexManager.indexingFolderName : indexManager.statusMessage)
                        .lineLimit(1)
                    Text(LF("队列中 %d 个文件夹", indexManager.queuedFolderIDs.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
                Text(LF("%d 个文件夹", indexManager.indexedFolders.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if visibleFolders.isEmpty {
                ContentUnavailableView(L("暂无索引文件夹"), systemImage: "folder.badge.plus")
                    .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(visibleFolders) { folder in
                        folderRow(folder)
                            .onAppear { loadMoreFoldersIfNeeded(current: folder) }
                    }

                    if visibleFolderCount < indexManager.indexedFolders.count {
                        Button(L("加载更多文件夹")) {
                            visibleFolderCount = min(visibleFolderCount + pageSize, indexManager.indexedFolders.count)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func folderRow(_ folder: IndexedFolder) -> some View {
        let status = indexManager.status(for: folder)
        let isSelected = selectedFolderID == folder.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    selectedFolderID = folder.id
                    indexManager.selectedFolder = folder
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(indexManager.isActiveFolder(folder) ? .blue : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                statusBadge(status)
                            }
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Button {
                        infoFolderID = folder.id
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .help(L("查看索引详情"))

                    Button {
                        Task { await indexManager.indexFolder(folder) }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                    .disabled(indexManager.isActiveFolder(folder))
                    .help(L("重新索引"))

                    Menu {
                        Button(L("查看文件")) { indexManager.selectedFolder = folder }
                        Button(L("在 Finder 中显示")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path) }
                        Button(L("清理索引"), role: .destructive) { pendingFolderAction = .clear(folder) }
                        Button(L("移除文件夹"), role: .destructive) { pendingFolderAction = .remove(folder) }
                            .disabled(indexManager.isActiveFolder(folder))
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help(L("管理"))
                }
                .foregroundStyle(.secondary)
            }

            ProgressView(value: progressValue(for: status))
                .tint(progressTint(for: status))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryStatusText(folder: folder, status: status))
                    Text(secondaryStatusText(folder: folder, status: status))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                Spacer()
                Text(folder.lastIndexed?.formatted(date: .abbreviated, time: .shortened) ?? L("尚未完成"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadMoreFoldersIfNeeded(current folder: IndexedFolder) {
        guard let lastVisible = visibleFolders.last, lastVisible.id == folder.id else { return }
        guard visibleFolderCount < indexManager.indexedFolders.count else { return }
        visibleFolderCount = min(visibleFolderCount + pageSize, indexManager.indexedFolders.count)
    }

    private func progressValue(for status: FolderIndexStatus) -> Double {
        if status.isQueued { return 0 }
        if status.phase == .failed && status.totalFiles == 0 { return 0 }
        if status.phase == .idle { return 0 }
        return status.progress
    }

    private func progressTint(for status: FolderIndexStatus) -> Color {
        switch status.phase {
        case .queued: return .orange
        case .scanning, .indexing: return .blue
        case .completed: return .green
        case .failed: return .orange
        case .idle: return .gray
        }
    }

    private func primaryStatusText(folder: IndexedFolder, status: FolderIndexStatus) -> String {
        if !status.statusText.isEmpty {
            return status.statusText
        }
        return LF("%d 个支持文件", folder.fileCount)
    }

    private func secondaryStatusText(folder: IndexedFolder, status: FolderIndexStatus) -> String {
        if let currentFilePath = status.currentFilePath, status.isActive {
            return URL(fileURLWithPath: currentFilePath).lastPathComponent
        }
        if let queuePosition = status.queuePosition {
            return LF("等待前方 %d 个任务", max(queuePosition - 1, 0))
        }
        if status.ocrIndexedFiles > 0 {
            return LF("%d 个 OCR 文件", status.ocrIndexedFiles)
        }
        if status.failedFiles > 0 {
            return LF("%d 个文件失败", status.failedFiles)
        }
        return LF("%d 文件", folder.fileCount)
    }

    private func statusBadge(_ status: FolderIndexStatus) -> some View {
        Text(statusBadgeTitle(status))
            .font(.caption2.weight(.medium))
            .foregroundStyle(statusBadgeColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusBadgeColor(status).opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusBadgeTitle(_ status: FolderIndexStatus) -> String {
        switch status.phase {
        case .queued: return L("队列中")
        case .scanning: return L("扫描中")
        case .indexing: return L("索引中")
        case .completed: return L("已完成")
        case .failed: return L("需关注")
        case .idle: return L("空闲")
        }
    }

    private func statusBadgeColor(_ status: FolderIndexStatus) -> Color {
        switch status.phase {
        case .queued: return .orange
        case .scanning, .indexing: return .blue
        case .completed: return .green
        case .failed: return .orange
        case .idle: return .secondary
        }
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

private struct FolderIndexInfoView: View {
    let folder: IndexedFolder
    let status: FolderIndexStatus
    let isActive: Bool
    let onReindex: () -> Void
    let onClear: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                        .font(.title3.weight(.semibold))
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 0) {
                detailMetric(L("状态"), statusText)
                detailMetric(L("文件数"), "\(folder.fileCount)")
                detailMetric(L("索引进度"), progressText)
                detailMetric(L("失败数"), "\(status.failedFiles)")
                detailMetric(L("OCR 文件"), "\(status.ocrIndexedFiles)")
                detailMetric(L("OCR 模式"), AppSettings.shared.enableImageOCR ? L("已开启") : L("未开启"))
                detailMetric(L("上次索引"), folder.lastIndexed?.formatted(date: .abbreviated, time: .shortened) ?? L("尚未完成"))
                if let startedAt = status.startedAt {
                    detailMetric(L("开始时间"), startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let finishedAt = status.finishedAt {
                    detailMetric(L("结束时间"), finishedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let currentFilePath = status.currentFilePath {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isActive ? L("当前文件") : L("最近文件"))
                        .font(.caption.weight(.semibold))
                    Text(currentFilePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let lastErrorDescription = status.lastErrorDescription, !lastErrorDescription.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("最近错误"))
                        .font(.caption.weight(.semibold))
                    Text(lastErrorDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(L("在 Finder 中显示"), action: onReveal)
                Button(L("清理索引"), role: .destructive, action: onClear)
                Spacer()
                Button(L("重新索引"), action: onReindex)
                    .disabled(isActive)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 360, alignment: .topLeading)
    }

    private var statusText: String {
        if status.statusText.isEmpty {
            return L("空闲")
        }
        return status.statusText
    }

    private var progressText: String {
        if status.totalFiles > 0 {
            return "\(status.completedFiles)/\(status.totalFiles)"
        }
        return status.phase == .completed ? "100%" : "0%"
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
