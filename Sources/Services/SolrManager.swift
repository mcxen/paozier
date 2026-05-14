import Foundation
import AppKit
import Combine

@MainActor
class SolrManager: ObservableObject {
    @Published var isRunning = false
    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var indexedFolders: [IndexedFolder] = []
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
    }

    var solrBaseURL: String { "http://localhost:\(solrPort)/solr/paozier" }

    func startSolr() async {
        guard !isRunning else { return }
        statusMessage = "启动 Solr..."

        // Solr binary: bundled in app or project root
        let solrDir = Bundle.main.resourceURL?.appendingPathComponent("solr")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("solr")

        let binPath = solrDir.appendingPathComponent("bin/solr").path
        guard FileManager.default.fileExists(atPath: binPath) else {
            statusMessage = "Solr 未找到，请运行 scripts/setup-solr.sh"
            return
        }

        // Ensure core config exists in app data solrHome
        let coreDir = solrHome.appendingPathComponent("paozier")
        let confDir = coreDir.appendingPathComponent("conf")
        try? FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)

        let corePropFile = coreDir.appendingPathComponent("core.properties")
        if !FileManager.default.fileExists(atPath: corePropFile.path) {
            try? "name=paozier".write(to: corePropFile, atomically: true, encoding: .utf8)
        }
        // Copy config from bundle/project
        let srcConf = solrDir.appendingPathComponent("server/solr/paozier/conf")
        for file in ["schema.xml", "solrconfig.xml"] {
            let src = srcConf.appendingPathComponent(file)
            let dst = confDir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: src.path) && !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["start", "-f", "-p", "\(solrPort)", "-s", solrHome.path]
        process.environment = {
            var env = ProcessInfo.processInfo.environment
            env["SOLR_SECURITY_MANAGER_ENABLED"] = "false"
            return env
        }()
        process.currentDirectoryURL = solrDir

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
            statusMessage = "Solr 启动超时"
        } catch {
            statusMessage = "启动失败: \(error.localizedDescription)"
        }
    }

    func stopSolr() {
        solrProcess?.terminate()
        solrProcess = nil
        isRunning = false
        statusMessage = "已停止"
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let folder = IndexedFolder(path: url.path)
            indexedFolders.append(folder)
            saveFolders()
            Task { await indexFolder(folder) }
        }
    }

    func indexFolder(_ folder: IndexedFolder) async {
        guard isRunning else {
            statusMessage = "请先启动 Solr"
            return
        }
        isIndexing = true
        indexProgress = 0
        statusMessage = "扫描 PDF 文件..."

        let folderURL = URL(fileURLWithPath: folder.path)
        let pdfFiles = findPDFs(in: folderURL)
        let total = pdfFiles.count

        statusMessage = "索引中 (0/\(total))..."
        for (i, file) in pdfFiles.enumerated() {
            do {
                try await SolrService.shared.indexPDF(at: file)
            } catch {
                // Skip failed files
            }
            indexProgress = Double(i + 1) / Double(max(total, 1))
            statusMessage = "索引中 (\(i + 1)/\(total))..."
        }

        // Update folder info
        if let idx = indexedFolders.firstIndex(where: { $0.id == folder.id }) {
            indexedFolders[idx].fileCount = total
            indexedFolders[idx].lastIndexed = Date()
            saveFolders()
        }

        try? await SolrService.shared.commit()
        await refreshDocCount()
        isIndexing = false
        statusMessage = "索引完成 (\(total) 个文件)"
    }

    func reindexAll() async {
        for folder in indexedFolders {
            await indexFolder(folder)
        }
    }

    private func refreshDocCount() async {
        totalDocs = (try? await SolrService.shared.docCount()) ?? 0
    }

    private func checkHealth() async -> Bool {
        guard let url = URL(string: "\(solrBaseURL)/admin/ping") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func findPDFs(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        return files
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
