import Foundation
import AppKit

@MainActor
class IndexManager: ObservableObject {
    static weak var shared: IndexManager?

    @Published var isReady = false
    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var indexedFolders: [IndexedFolder] = []
    @Published var selectedFolder: IndexedFolder?
    @Published var totalDocs: Int = 0
    @Published var statusMessage = "就绪"
    @Published var httpRunning = false
    @Published var mcpRunning = false
    @Published var indexingFolderName = ""
    @Published var indexingFileCount = 0
    @Published var indexingTotalFiles = 0
    @Published var indexingFailedCount = 0

    let httpServer = HTTPServer()
    let mcpServer = MCPServer()

    private let dataDir: URL
    private var isStartingUp = false

    nonisolated static let supportedExtensions: Set<String> = [
        "pdf", "txt", "md", "markdown", "docx", "doc", "rtf",
        "html", "htm", "xml", "json", "csv", "tsv",
        "pptx", "ppt", "xlsx", "xls", "odt", "ods", "odp", "epub",
        "log", "yaml", "yml", "toml", "ini", "conf",
        "swift", "py", "js", "ts", "java", "c", "h", "cpp", "rs", "go", "rb", "php", "sh"
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

        let s = AppSettings.shared
        statusMessage = "初始化搜索引擎..."
        await SearchEngine.shared.updateSettings(
            limit: s.searchResultLimit,
            skWeight: s.searchEngineWeightSK,
            ftsWeight: s.searchEngineWeightFTS,
            searchFilenames: s.searchFilenames
        )
        await Task.detached {
            await SearchEngine.shared.open()
        }.value
        totalDocs = await SearchEngine.shared.documentCount
        isReady = true
        statusMessage = "就绪 · \(totalDocs) 个文档"
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
            let path = url.standardizedFileURL.path
            if let existing = indexedFolders.first(where: { normalizedPath($0.path) == path }) {
                selectedFolder = existing
                Task { await indexFolder(existing) }
                return
            }

            var folder = IndexedFolder(path: path)
            folder.fileCount = Self.findSupportedFiles(in: URL(fileURLWithPath: path)).count
            indexedFolders.append(folder)
            selectedFolder = folder
            saveFolders()
            Task { await indexFolder(folder) }
        }
    }

    func removeFolder(_ folder: IndexedFolder) {
        let files = findFiles(in: URL(fileURLWithPath: folder.path))
        Task {
            await SearchEngine.shared.removeFiles(at: files)
            totalDocs = await SearchEngine.shared.documentCount
        }
        indexedFolders.removeAll { $0.id == folder.id }
        if selectedFolder?.id == folder.id {
            selectedFolder = nil
        }
        saveFolders()
    }

    func indexFolder(_ folder: IndexedFolder) async {
        if isIndexing {
            statusMessage = "已有索引任务正在运行..."
            return
        }

        if !isReady {
            statusMessage = "等待搜索引擎初始化..."
            await startup()
        }

        isIndexing = true
        indexProgress = 0
        indexingFolderName = URL(fileURLWithPath: folder.path).lastPathComponent
        indexingFileCount = 0
        indexingTotalFiles = 0
        indexingFailedCount = 0
        statusMessage = "扫描文件..."
        defer {
            isIndexing = false
            indexingFolderName = ""
        }

        let folderURL = URL(fileURLWithPath: folder.path)
        let files = await Task.detached(priority: .userInitiated) {
            Self.findSupportedFiles(in: folderURL)
        }.value
        let total = files.count
        indexingTotalFiles = total

        if total == 0 {
            statusMessage = "未找到支持的文件"
            return
        }

        var failed = 0
        var lastUIUpdate = Date.distantPast
        for (i, file) in files.enumerated() {
            do {
                await SearchEngine.shared.removeFile(at: file)
                try await SearchEngine.shared.indexFile(at: file)
            } catch {
                failed += 1
            }

            let completed = i + 1
            let shouldUpdate = completed == total || completed % 25 == 0 || Date().timeIntervalSince(lastUIUpdate) > 0.25
            if shouldUpdate {
                indexProgress = Double(completed) / Double(total)
                indexingFileCount = completed
                indexingFailedCount = failed
                statusMessage = "索引中 \(completed)/\(total)"
                lastUIUpdate = Date()
            }
        }

        await SearchEngine.shared.commit()

        if let idx = indexedFolders.firstIndex(where: { $0.id == folder.id }) {
            indexedFolders[idx].fileCount = total
            indexedFolders[idx].lastIndexed = Date()
            saveFolders()
        }

        totalDocs = await SearchEngine.shared.documentCount
        statusMessage = failed > 0 ? "索引完成 · \(totalDocs) 个文档 · \(failed) 个失败" : "索引完成 · \(totalDocs) 个文档"
    }

    func reindexAll() async {
        await SearchEngine.shared.removeAll()
        for folder in indexedFolders {
            await indexFolder(folder)
        }
    }

    func search(options: SearchOptions) async -> [SearchResult] {
        await SearchEngine.shared.search(options: options)
    }

    func search(query: String, fileTypeFilter: FileTypeFilter = .all) async -> [SearchResult] {
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
        Self.findSupportedFiles(in: directory)
    }

    nonisolated private static func findSupportedFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private var foldersFile: URL { dataDir.appendingPathComponent("folders.json") }

    private func saveFolders() {
        try? JSONEncoder().encode(indexedFolders).write(to: foldersFile)
    }

    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersFile) else { return }
        indexedFolders = (try? JSONDecoder().decode([IndexedFolder].self, from: data)) ?? []
    }
}
