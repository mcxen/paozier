import Foundation
import AppKit

@MainActor
class IndexManager: ObservableObject {
    private struct IndexJob: Equatable {
        let folderID: String
    }

    static weak var shared: IndexManager?

    @Published var isReady = false
    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var indexedFolders: [IndexedFolder] = []
    @Published var selectedFolder: IndexedFolder?
    @Published var totalDocs: Int = 0
    @Published var statusMessage = L("就绪")
    @Published var httpRunning = false
    @Published var mcpRunning = false
    @Published var indexingFolderName = ""
    @Published var indexingFileCount = 0
    @Published var indexingTotalFiles = 0
    @Published var indexingFailedCount = 0
    @Published private(set) var folderStatuses: [String: FolderIndexStatus] = [:]
    @Published private(set) var queuedFolderIDs: [String] = []

    let httpServer = HTTPServer()
    let mcpServer = MCPServer()

    private let dataDir: URL
    private var isStartingUp = false
    private var isProcessingQueue = false
    private var activeFolderID: String?
    private var indexQueue: [IndexJob] = []

    nonisolated static let supportedExtensions: Set<String> = [
        "pdf", "txt", "md", "markdown", "docx", "doc", "rtf",
        "html", "htm", "xml", "json", "csv", "tsv",
        "pptx", "ppt", "xlsx", "xls", "odt", "ods", "odp", "epub",
        "log", "yaml", "yml", "toml", "ini", "conf",
        "swift", "py", "js", "ts", "java", "c", "h", "cpp", "rs", "go", "rb", "php", "sh",
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif", "webp"
    ]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = appSupport.appendingPathComponent("Paozier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        loadFolders()
        refreshFolderCounts()
        IndexManager.shared = self
    }

    func startup() async {
        if isReady { return }
        if isStartingUp {
            while !isReady {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return
        }
        isStartingUp = true
        defer { isStartingUp = false }

        statusMessage = L("初始化搜索引擎...")
        await syncSearchEngineSettings()
        await Task.detached {
            await SearchEngine.shared.open()
        }.value
        totalDocs = await SearchEngine.shared.documentCount
        isReady = true
        statusMessage = LF("就绪 · %d 个文档", totalDocs)
        startHTTP()
        startMCP()
    }

    func startHTTP() {
        guard !httpRunning else { return }
        do {
            try httpServer.start(port: 9880)
            httpRunning = true
        } catch { /* ignore */ }
    }

    func stopHTTP() {
        httpServer.stop()
        httpRunning = false
    }

    func startMCP() {
        guard !mcpRunning else { return }
        do {
            try mcpServer.start(port: 9881)
            mcpRunning = true
        } catch { /* ignore */ }
    }

    func stopMCP() {
        mcpServer.stop()
        mcpRunning = false
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            addFolder(at: url.standardizedFileURL.path)
        }
    }

    func addFolder(at path: String) {
        let normalized = normalizedPath(path)
        if let existing = indexedFolders.first(where: { normalizedPath($0.path) == normalized }) {
            selectedFolder = existing
            Task { await indexFolder(existing) }
            return
        }

        var folder = IndexedFolder(path: normalized)
        folder.fileCount = findFiles(in: URL(fileURLWithPath: normalized)).count
        indexedFolders.append(folder)
        selectedFolder = folder
        saveFolders()
        Task { await indexFolder(folder) }
    }

    func removeFolder(_ folder: IndexedFolder) {
        if activeFolderID == folder.id {
            statusMessage = L("正在索引的文件夹暂时不能移除")
            return
        }

        cancelQueuedJob(for: folder.id)
        folderStatuses[folder.id] = nil
        Task {
            await SearchEngine.shared.removeFiles(inFolderPath: folder.path)
            totalDocs = await SearchEngine.shared.documentCount
            statusMessage = L("已移除文件夹")
        }
        indexedFolders.removeAll { $0.id == folder.id }
        if selectedFolder?.id == folder.id {
            selectedFolder = nil
        }
        saveFolders()
    }

    func clearFolderIndex(_ folder: IndexedFolder) async {
        await SearchEngine.shared.removeFiles(inFolderPath: folder.path)
        totalDocs = await SearchEngine.shared.documentCount
        statusMessage = L("已清理文件夹索引")
        if let idx = indexedFolders.firstIndex(where: { $0.id == folder.id }) {
            indexedFolders[idx].lastIndexed = nil
            saveFolders()
        }
        folderStatuses[folder.id] = FolderIndexStatus(phase: .idle, statusText: L("索引已清理"))
    }

    func indexFolder(_ folder: IndexedFolder) async {
        enqueueIndexJob(for: folder.id)
        await processIndexQueueIfNeeded()
    }

    func indexImageOCRFile(_ fileURL: URL, in folder: IndexedFolder) async {
        guard !isIndexing else {
            statusMessage = L("已有索引任务正在运行...")
            return
        }

        guard await SearchEngine.shared.canRunImageOCR(for: fileURL) else {
            statusMessage = L("该文件不支持图片 OCR")
            return
        }

        await syncSearchEngineSettings()
        if !AppSettings.shared.enableImageOCR {
            statusMessage = L("图片 OCR 模式未开启")
            return
        }

        if !isReady {
            statusMessage = L("等待搜索引擎初始化...")
            await startup()
        }

        isIndexing = true
        activeFolderID = folder.id
        indexProgress = 0
        indexingFolderName = fileURL.lastPathComponent
        indexingFileCount = 0
        indexingTotalFiles = 1
        indexingFailedCount = 0
        folderStatuses[folder.id] = FolderIndexStatus(
            phase: .indexing,
            completedFiles: 0,
            totalFiles: 1,
            failedFiles: 0,
            ocrIndexedFiles: 0,
            statusText: L("正在提取图片文字..."),
            currentFilePath: fileURL.path,
            startedAt: Date()
        )
        defer {
            isIndexing = false
            activeFolderID = nil
            indexProgress = 0
            indexingFolderName = ""
        }

        do {
            await SearchEngine.shared.removeFile(at: fileURL)
            try await SearchEngine.shared.indexFile(at: fileURL, forceImageOCR: true)
            await SearchEngine.shared.commit()
            totalDocs = await SearchEngine.shared.documentCount
            indexingFileCount = 1
            indexProgress = 1
            folderStatuses[folder.id] = FolderIndexStatus(
                phase: .completed,
                completedFiles: 1,
                totalFiles: 1,
                failedFiles: 0,
                ocrIndexedFiles: 1,
                statusText: L("图片 OCR 索引完成"),
                currentFilePath: fileURL.path,
                startedAt: folderStatuses[folder.id]?.startedAt,
                finishedAt: Date()
            )
            statusMessage = L("图片 OCR 索引完成")
        } catch {
            indexingFailedCount = 1
            folderStatuses[folder.id] = FolderIndexStatus(
                phase: .failed,
                completedFiles: 1,
                totalFiles: 1,
                failedFiles: 1,
                ocrIndexedFiles: 0,
                statusText: L("图片 OCR 索引失败"),
                currentFilePath: fileURL.path,
                startedAt: folderStatuses[folder.id]?.startedAt,
                finishedAt: Date(),
                lastErrorDescription: error.localizedDescription
            )
            statusMessage = L("图片 OCR 索引失败")
        }
    }

    func reindexAll() async {
        guard !isIndexing else {
            statusMessage = L("已有索引任务正在运行...")
            return
        }

        await SearchEngine.shared.removeAll()
        totalDocs = 0
        statusMessage = L("正在排队重建全部索引...")

        for idx in indexedFolders.indices {
            indexedFolders[idx].lastIndexed = nil
        }
        saveFolders()

        indexQueue.removeAll()
        for folder in indexedFolders {
            enqueueIndexJob(for: folder.id)
        }
        await processIndexQueueIfNeeded()
    }

    func search(options: SearchOptions) async -> [SearchResult] {
        await syncSearchEngineSettings()
        return await SearchEngine.shared.search(options: options)
    }

    func grepSearch(options: SearchOptions) async -> AsyncStream<GrepBatchResult> {
        return await GrepSearchEngine.shared.search(
            query: options.trimmedQuery,
            folderPaths: indexedFolders.map(\.path),
            allowedExtensions: options.allowedExtensions,
            isRegex: options.usesRegex
        )
    }

    func search(query: String, fileTypeFilter: FileTypeFilter = .all) async -> [SearchResult] {
        await syncSearchEngineSettings()
        var options = SearchOptions(query: query)
        options.selectedFileTypes = fileTypeFilter == .all ? [] : [fileTypeFilter]
        return await SearchEngine.shared.search(options: options)
    }

    func files(in folder: IndexedFolder) -> [URL] {
        findFiles(in: URL(fileURLWithPath: folder.path))
    }

    func refreshFolderCounts() {
        var changed = false
        for idx in indexedFolders.indices {
            let count = findFiles(in: URL(fileURLWithPath: indexedFolders[idx].path)).count
            if indexedFolders[idx].fileCount != count {
                indexedFolders[idx].fileCount = count
                changed = true
            }
        }
        if changed { saveFolders() }
    }

    private func findFiles(in directory: URL) -> [URL] {
        Self.findSupportedFiles(in: directory, excluding: Set(AppSettings.shared.excludedExtensions))
    }

    nonisolated private static func findSupportedFiles(in directory: URL, excluding excludedExtensions: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard !excludedExtensions.contains(ext) else { continue }
            if Self.supportedExtensions.contains(ext) {
                files.append(fileURL.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif", "webp"].contains(ext)
    }

    private func filteredFilesForIndexing(_ files: [URL], referencedImagePaths: Set<String>) -> [URL] {
        let settings = AppSettings.shared
        guard settings.enableImageOCR else {
            return files.filter { !isImageFile($0) }
        }

        let scope = ImageOCRScope(rawValue: settings.imageOCRScope) ?? .markdownOnly
        return files.filter { fileURL in
            guard isImageFile(fileURL) else { return true }
            switch scope {
            case .markdownOnly:
                return false
            case .markdownAndStandalone:
                return !referencedImagePaths.contains(fileURL.standardizedFileURL.path)
            }
        }
    }

    private func referencedMarkdownImagePaths(in files: [URL]) -> Set<String> {
        guard AppSettings.shared.enableImageOCR else { return [] }
        let markdownFiles = files.filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
        guard !markdownFiles.isEmpty else { return [] }

        var referenced: Set<String> = []
        for markdownURL in markdownFiles {
            guard let content = try? String(contentsOf: markdownURL, encoding: .utf8) else { continue }
            for imageURL in SearchEngine.markdownImageURLs(in: content, markdownURL: markdownURL) {
                if isImageFile(imageURL) {
                    referenced.insert(imageURL.standardizedFileURL.path)
                }
            }
        }
        return referenced
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    func status(for folder: IndexedFolder) -> FolderIndexStatus {
        if let status = folderStatuses[folder.id] {
            return status
        }
        return FolderIndexStatus(
            phase: folder.lastIndexed == nil ? .idle : .completed,
            completedFiles: folder.fileCount,
            totalFiles: folder.fileCount,
            statusText: folder.lastIndexed == nil ? "" : L("已完成")
        )
    }

    func isActiveFolder(_ folder: IndexedFolder) -> Bool {
        activeFolderID == folder.id
    }

    func queuePosition(for folder: IndexedFolder) -> Int? {
        folderStatuses[folder.id]?.queuePosition
    }

    private func enqueueIndexJob(for folderID: String) {
        guard indexedFolders.contains(where: { $0.id == folderID }) else { return }

        if activeFolderID == folderID {
            statusMessage = L("该文件夹正在索引中")
            return
        }

        if let idx = indexQueue.firstIndex(where: { $0.folderID == folderID }) {
            let position = idx + 1
            folderStatuses[folderID] = FolderIndexStatus(
                phase: .queued,
                queuePosition: position,
                statusText: LF("排队中 · 第 %d 个", position)
            )
            return
        }

        indexQueue.append(IndexJob(folderID: folderID))
        syncQueuedFolderStates()
    }

    private func cancelQueuedJob(for folderID: String) {
        indexQueue.removeAll { $0.folderID == folderID }
        syncQueuedFolderStates()
    }

    private func syncQueuedFolderStates() {
        queuedFolderIDs = indexQueue.map(\.folderID)
        for (offset, job) in indexQueue.enumerated() {
            var status = folderStatuses[job.folderID] ?? FolderIndexStatus()
            status.phase = .queued
            status.queuePosition = offset + 1
            status.statusText = LF("排队中 · 第 %d 个", offset + 1)
            if !status.isTerminal {
                status.finishedAt = nil
                status.completedFiles = 0
                status.totalFiles = 0
                status.failedFiles = 0
                status.currentFilePath = nil
            }
            folderStatuses[job.folderID] = status
        }
    }

    private func processIndexQueueIfNeeded() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        defer {
            isProcessingQueue = false
            queuedFolderIDs = indexQueue.map(\.folderID)
        }

        if !isReady {
            statusMessage = L("等待搜索引擎初始化...")
            await startup()
        }

        while !indexQueue.isEmpty {
            let job = indexQueue.removeFirst()
            syncQueuedFolderStates()

            guard let folder = indexedFolders.first(where: { $0.id == job.folderID }) else {
                folderStatuses[job.folderID] = nil
                continue
            }

            await performIndexJob(for: folder)
        }
    }

    private func performIndexJob(for folder: IndexedFolder) async {
        await syncSearchEngineSettings()
        isIndexing = true
        activeFolderID = folder.id
        indexProgress = 0
        indexingFolderName = URL(fileURLWithPath: folder.path).lastPathComponent
        indexingFileCount = 0
        indexingTotalFiles = 0
        indexingFailedCount = 0
        statusMessage = L("扫描文件...")
        folderStatuses[folder.id] = FolderIndexStatus(
            phase: .scanning,
            statusText: L("扫描文件..."),
            startedAt: Date()
        )

        defer {
            isIndexing = false
            activeFolderID = nil
            indexProgress = 0
            indexingFolderName = ""
        }

        let folderURL = URL(fileURLWithPath: folder.path)
        let excludedExtensions = Set(AppSettings.shared.excludedExtensions)
        let allFiles = await Task.detached(priority: .userInitiated) {
            Self.findSupportedFiles(in: folderURL, excluding: excludedExtensions)
        }.value
        let referencedImagePaths = referencedMarkdownImagePaths(in: allFiles)
        let files = filteredFilesForIndexing(allFiles, referencedImagePaths: referencedImagePaths)
        let total = files.count
        indexingTotalFiles = total

        if total == 0 {
            folderStatuses[folder.id] = FolderIndexStatus(
                phase: .failed,
                completedFiles: 0,
                totalFiles: 0,
                failedFiles: 0,
                statusText: L("未找到支持的文件"),
                startedAt: folderStatuses[folder.id]?.startedAt ?? Date(),
                finishedAt: Date(),
                lastErrorDescription: L("未找到支持的文件")
            )
            statusMessage = L("未找到支持的文件")
            return
        }

        var status = folderStatuses[folder.id] ?? FolderIndexStatus()
        status.phase = .indexing
        status.totalFiles = total
        status.completedFiles = 0
        status.failedFiles = 0
        status.queuePosition = nil
        status.statusText = LF("索引中 %d/%d", 0, total)
        status.startedAt = status.startedAt ?? Date()
        folderStatuses[folder.id] = status

        var failed = 0
        var ocrIndexedFiles = 0
        var lastErrorDescription: String?
        var lastUIUpdate = Date.distantPast
        for (i, file) in files.enumerated() {
            do {
                await SearchEngine.shared.removeFile(at: file)
                try await SearchEngine.shared.indexFile(at: file)
                if AppSettings.shared.enableImageOCR && isImageFile(file) {
                    ocrIndexedFiles += 1
                }
            } catch {
                failed += 1
                lastErrorDescription = error.localizedDescription
            }

            let completed = i + 1
            let shouldUpdate = completed == total || completed % 25 == 0 || Date().timeIntervalSince(lastUIUpdate) > 0.25
            if shouldUpdate {
                indexProgress = Double(completed) / Double(total)
                indexingFileCount = completed
                indexingFailedCount = failed
                statusMessage = LF("索引中 %d/%d", completed, total)

                var activeStatus = folderStatuses[folder.id] ?? FolderIndexStatus()
                activeStatus.phase = .indexing
                activeStatus.completedFiles = completed
                activeStatus.totalFiles = total
                activeStatus.failedFiles = failed
                activeStatus.ocrIndexedFiles = ocrIndexedFiles
                activeStatus.statusText = LF("索引中 %d/%d", completed, total)
                activeStatus.currentFilePath = file.path
                activeStatus.lastErrorDescription = lastErrorDescription
                folderStatuses[folder.id] = activeStatus
                lastUIUpdate = Date()
            }
        }

        await SearchEngine.shared.commit()

        if let idx = indexedFolders.firstIndex(where: { $0.id == folder.id }) {
            indexedFolders[idx].fileCount = total
            indexedFolders[idx].lastIndexed = Date()
            selectedFolder = selectedFolder?.id == folder.id ? indexedFolders[idx] : selectedFolder
            saveFolders()
        }

        totalDocs = await SearchEngine.shared.documentCount
        let finalStatusText = failed > 0 ? LF("索引完成 · %d/%d · %d 个失败", total - failed, total, failed) : LF("索引完成 · %d 个文档", totalDocs)
        folderStatuses[folder.id] = FolderIndexStatus(
            phase: failed > 0 ? .failed : .completed,
            completedFiles: total,
            totalFiles: total,
            failedFiles: failed,
            ocrIndexedFiles: ocrIndexedFiles,
            statusText: finalStatusText,
            currentFilePath: files.last?.path,
            startedAt: status.startedAt,
            finishedAt: Date(),
            lastErrorDescription: lastErrorDescription
        )
        statusMessage = failed > 0 ? LF("索引完成 · %d 个文档 · %d 个失败", totalDocs, failed) : LF("索引完成 · %d 个文档", totalDocs)
    }

    private var foldersFile: URL { dataDir.appendingPathComponent("folders.json") }

    private func saveFolders() {
        try? JSONEncoder().encode(indexedFolders).write(to: foldersFile)
    }

    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersFile) else { return }
        indexedFolders = (try? JSONDecoder().decode([IndexedFolder].self, from: data)) ?? []
    }

    private func syncSearchEngineSettings() async {
        let s = AppSettings.shared
        await SearchEngine.shared.updateSettings(
            limit: s.searchResultLimit,
            skWeight: s.searchEngineWeightSK,
            ftsWeight: s.searchEngineWeightFTS,
            searchFilenames: s.searchFilenames,
            enableImageOCR: s.enableImageOCR,
            imageOCRScope: s.imageOCRScope
        )
    }
}
