import Foundation
import AppKit
import Combine

@MainActor
class SolrManager: ObservableObject {
    @Published var isRunning = false
    @Published var isIndexing = false
    @Published var isEngineBusy = false
    @Published var indexProgress: Double = 0
    @Published var indexedFolders: [IndexedFolder] = []
    @Published var selectedFolder: IndexedFolder?
    @Published var totalDocs: Int = 0
    @Published var statusMessage = "就绪"

    private var solrProcess: Process?
    private let solrPort = 8983
    private let dataDir: URL
    private let solrHome: URL

    static let supportedExtensions: Set<String> = [
        "pdf", "txt", "md", "markdown", "docx", "doc", "rtf",
        "html", "htm", "xml", "json", "csv", "tsv",
        "pptx", "ppt", "xlsx", "xls", "odt", "ods", "odp", "epub"
    ]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = appSupport.appendingPathComponent("Paozier", isDirectory: true)
        solrHome = dataDir.appendingPathComponent("solr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        loadFolders()
        refreshFolderCounts()
    }

    var solrBaseURL: String { "http://localhost:\(solrPort)/solr/paozier" }

    func startSolr() async {
        guard !isEngineBusy else { return }
        guard !isRunning else { return }
        isEngineBusy = true
        defer { isEngineBusy = false }
        statusMessage = "启动 Solr..."

        guard let solrDir = findSolrDirectory() else {
            statusMessage = "Solr 未找到，请运行 scripts/setup-solr.sh"
            return
        }

        ensureCoreConfig(from: solrDir)

        if await checkHealth() {
            isRunning = true
            statusMessage = "Solr 运行中"
            await refreshDocCount()
            return
        }

        if await solrServerResponds() {
            isRunning = false
            statusMessage = "8983 端口已有 Solr，但 paozier core 不可用；请停止旧 Solr 后重试"
            return
        }

        let binPath = solrDir.appendingPathComponent("bin/solr").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["start", "-f", "-p", "\(solrPort)", "-s", solrHome.path]
        process.environment = {
            var env = ProcessInfo.processInfo.environment
            env["SOLR_SECURITY_MANAGER_ENABLED"] = "false"
            return env
        }()
        process.currentDirectoryURL = solrDir
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        solrProcess = process
        do {
            try process.run()
            // Wait for Solr to be ready
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if await checkHealth() {
                    isRunning = true
                    statusMessage = "Solr 运行中"
                    await refreshDocCount()
                    return
                }
            }
            let stderr = String(data: error.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            statusMessage = stderr.isEmpty ? "Solr 启动超时" : "Solr 启动失败: \(stderr.prefix(120))"
        } catch {
            statusMessage = "启动失败: \(error.localizedDescription)"
        }
    }

    func stopSolr() async {
        guard !isEngineBusy else { return }
        isEngineBusy = true
        statusMessage = "停止 Solr..."

        solrProcess?.terminate()
        solrProcess = nil

        if let solrDir = findSolrDirectory() {
            _ = try? await runSolrCommand(arguments: ["stop", "-p", "\(solrPort)"], in: solrDir)
        }

        for _ in 0..<10 {
            if !(await solrServerResponds()) {
                isRunning = false
                totalDocs = 0
                statusMessage = "已停止"
                isEngineBusy = false
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        isRunning = await checkHealth()
        statusMessage = isRunning ? "停止失败：Solr 仍在运行" : "已停止"
        isEngineBusy = false
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            var folder = IndexedFolder(path: url.path)
            folder.fileCount = findIndexableFiles(in: url).count
            indexedFolders.append(folder)
            saveFolders()
            Task { await indexFolder(folder) }
        }
    }

    func indexFolder(_ folder: IndexedFolder) async {
        let healthy = await checkHealth()
        if !isRunning || !healthy {
            await startSolr()
        }

        guard await checkHealth() else {
            statusMessage = "Solr 未就绪，无法索引"
            return
        }

        isIndexing = true
        indexProgress = 0
        statusMessage = "扫描文件..."

        let folderURL = URL(fileURLWithPath: folder.path)
        let files = findIndexableFiles(in: folderURL)
        let total = files.count

        if total == 0 {
            statusMessage = "未找到支持的文件"
            isIndexing = false
            return
        }

        statusMessage = "索引中 (0/\(total))..."
        var failed = 0
        try? await SolrService.shared.deleteFolder(path: folder.path)
        for (i, file) in files.enumerated() {
            do {
                try await SolrService.shared.indexFile(at: file)
            } catch {
                failed += 1
            }
            indexProgress = Double(i + 1) / Double(max(total, 1))
            statusMessage = failed == 0 ? "索引中 (\(i + 1)/\(total))..." : "索引中 (\(i + 1)/\(total))，失败 \(failed) 个"
        }

        // Update folder info
        if let idx = indexedFolders.firstIndex(where: { $0.id == folder.id }) {
            indexedFolders[idx].fileCount = files.count
            indexedFolders[idx].lastIndexed = Date()
            saveFolders()
        }

        try? await SolrService.shared.commit()
        await refreshDocCount()
        isIndexing = false
        statusMessage = failed == 0 ? "索引完成 (\(total) 个文件)" : "索引完成，成功 \(total - failed)，失败 \(failed)"
    }

    func reindexAll() async {
        for folder in indexedFolders {
            await indexFolder(folder)
        }
    }

    func refreshStatus() async {
        isRunning = await checkHealth()
        if isRunning {
            statusMessage = "Solr 运行中"
            await refreshDocCount()
        } else {
            totalDocs = 0
            statusMessage = await solrServerResponds() ? "Solr 已启动，但 paozier core 不可用" : "已停止"
        }
        refreshFolderCounts()
    }

    func refreshFolderCounts() {
        var changed = false
        for idx in indexedFolders.indices {
            let count = findIndexableFiles(in: URL(fileURLWithPath: indexedFolders[idx].path)).count
            if indexedFolders[idx].fileCount != count {
                indexedFolders[idx].fileCount = count
                changed = true
            }
        }
        if changed {
            saveFolders()
        }
    }

    private func refreshDocCount() async {
        totalDocs = (try? await SolrService.shared.docCount()) ?? 0
    }

    private func checkHealth() async -> Bool {
        guard var components = URLComponents(string: "\(solrBaseURL)/select") else { return false }
        components.queryItems = [
            URLQueryItem(name: "q", value: "*:*"),
            URLQueryItem(name: "rows", value: "0"),
            URLQueryItem(name: "wt", value: "json")
        ]
        guard let url = components.url else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func solrServerResponds() async -> Bool {
        guard let url = URL(string: "http://localhost:\(solrPort)/solr/admin/info/system?wt=json") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func findSolrDirectory() -> URL? {
        let execPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [
            // App bundle: Paozier.app/Contents/Resources/solr
            execPath.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/solr"),
            // Bundle API
            Bundle.main.resourceURL?.appendingPathComponent("solr"),
            // Working directory (swift run)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("solr"),
            // Relative to .build/debug/Paozier
            execPath.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("solr")
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("bin/solr").path) }
    }

    private func runSolrCommand(arguments: [String], in solrDir: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = solrDir.appendingPathComponent("bin/solr")
            process.arguments = arguments
            process.currentDirectoryURL = solrDir
            process.environment = {
                var env = ProcessInfo.processInfo.environment
                env["SOLR_SECURITY_MANAGER_ENABLED"] = "false"
                return env
            }()

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.terminationHandler = { process in
                let out = output.fileHandleForReading.readDataToEndOfFile()
                let err = error.fileHandleForReading.readDataToEndOfFile()
                let text = (String(data: out, encoding: .utf8) ?? "") + (String(data: err, encoding: .utf8) ?? "")
                if process.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: SolrError.commandFailed(text))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func ensureCoreConfig(from solrDir: URL) {
        // Ensure solr.xml exists in solrHome
        let solrXml = solrHome.appendingPathComponent("solr.xml")
        if !FileManager.default.fileExists(atPath: solrXml.path) {
            try? FileManager.default.createDirectory(at: solrHome, withIntermediateDirectories: true)
            try? "<solr></solr>".write(to: solrXml, atomically: true, encoding: .utf8)
        }

        let coreDir = solrHome.appendingPathComponent("paozier")
        let confDir = coreDir.appendingPathComponent("conf")
        try? FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)

        let corePropFile = coreDir.appendingPathComponent("core.properties")
        try? "name=paozier\n".write(to: corePropFile, atomically: true, encoding: .utf8)

        let srcConf = solrDir.appendingPathComponent("server/solr/paozier/conf")
        for file in ["schema.xml", "solrconfig.xml"] {
            let src = srcConf.appendingPathComponent(file)
            let dst = confDir.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            if FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.removeItem(at: dst)
            }
            try? FileManager.default.copyItem(at: src, to: dst)
        }
    }

    private func findIndexableFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
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
