import Foundation

struct TantivySearchHit: Decodable {
    let path: String
    let score: Double
}

final class TantivyEngine {
    private static let bundledSidecarRelativePath = "bin/paozier-tantivy-sidecar"

    private let fm = FileManager.default
    private let dataDir: URL
    private let indexDir: URL
    private let buildRoot: URL
    private var pendingOperations: [Operation] = []

    init(dataDir: URL) {
        self.dataDir = dataDir
        self.indexDir = dataDir.appendingPathComponent("tantivy.index", isDirectory: true)
        self.buildRoot = dataDir.appendingPathComponent("tantivy-build", isDirectory: true)
    }

    func prepare() {
        _ = try? sidecarExecutableURL()
    }

    func queueAdd(url: URL, content: String) {
        pendingOperations.append(.add(path: url.standardizedFileURL.path, content: content))
    }

    func queueDelete(url: URL) {
        pendingOperations.append(.delete(path: url.standardizedFileURL.path))
    }

    func queueDelete(urls: [URL]) {
        pendingOperations.reserveCapacity(pendingOperations.count + urls.count)
        for url in urls {
            queueDelete(url: url)
        }
    }

    func commit() {
        guard !pendingOperations.isEmpty else { return }
        let payload = ApplyPayload(indexPath: indexDir.path, operations: pendingOperations)
        do {
            _ = try run(command: "apply", payload: payload)
            pendingOperations.removeAll(keepingCapacity: true)
        } catch {
            NSLog("Tantivy apply failed: %@", String(describing: error))
        }
    }

    func search(query: String, limit: Int) -> [TantivySearchHit] {
        let payload = SearchPayload(indexPath: indexDir.path, query: query, limit: limit)
        do {
            let data = try run(command: "search", payload: payload)
            return try JSONDecoder().decode(SearchResponse.self, from: data).hits
        } catch {
            NSLog("Tantivy search failed: %@", String(describing: error))
            return []
        }
    }

    func reset() {
        pendingOperations.removeAll(keepingCapacity: true)
        try? fm.removeItem(at: indexDir)
    }

    private func run<Payload: Encodable>(command: String, payload: Payload) throws -> Data {
        let executableURL = try sidecarExecutableURL()
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: buildRoot, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [command]
        process.currentDirectoryURL = dataDir

        var env = ProcessInfo.processInfo.environment
        env["PAOZIER_TANTIVY_INDEX_DIR"] = indexDir.path
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let inputData = try JSONEncoder().encode(payload)
        try process.run()

        stdinPipe.fileHandleForWriting.write(inputData)
        try? stdinPipe.fileHandleForWriting.close()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TantivyError.processFailed(status: process.terminationStatus, message: stderrText)
        }
        return stdoutData
    }

    private func sidecarExecutableURL() throws -> URL {
        if let bundledExecutableURL = bundledSidecarExecutableURL() {
            return bundledExecutableURL
        }

        let manifestURL = try sidecarManifestURL()
        let executableURL = buildRoot
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("paozier-tantivy-sidecar")

        if needsBuild(executableURL: executableURL, manifestURL: manifestURL) {
            try buildSidecar(manifestURL: manifestURL)
        }
        guard fm.isExecutableFile(atPath: executableURL.path) else {
            throw TantivyError.sidecarUnavailable
        }
        return executableURL
    }

    private func bundledSidecarExecutableURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let executableURL = resourceURL.appendingPathComponent(Self.bundledSidecarRelativePath)
        guard fm.isExecutableFile(atPath: executableURL.path) else { return nil }
        return executableURL
    }

    private func sidecarManifestURL() throws -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repoRoot
            .appendingPathComponent("rust", isDirectory: true)
            .appendingPathComponent("paozier-tantivy-sidecar", isDirectory: true)
            .appendingPathComponent("Cargo.toml")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw TantivyError.sidecarSourceMissing
        }
        return manifestURL
    }

    private func needsBuild(executableURL: URL, manifestURL: URL) -> Bool {
        guard let binaryDate = modificationDate(of: executableURL) else { return true }
        let sourceRoot = manifestURL.deletingLastPathComponent()
        let sourceDates = [
            modificationDate(of: manifestURL),
            modificationDate(of: sourceRoot.appendingPathComponent("src").appendingPathComponent("main.rs"))
        ].compactMap { $0 }
        guard let newestSource = sourceDates.max() else { return true }
        return newestSource > binaryDate
    }

    private func buildSidecar(manifestURL: URL) throws {
        guard let cargoPath = Self.findExecutable("cargo") else {
            throw TantivyError.cargoUnavailable
        }

        try fm.createDirectory(at: buildRoot, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cargoPath)
        process.arguments = ["build", "--manifest-path", manifestURL.path, "--release"]
        process.currentDirectoryURL = manifestURL.deletingLastPathComponent()

        var env = ProcessInfo.processInfo.environment
        env["CARGO_TARGET_DIR"] = buildRoot.path
        process.environment = env

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(decoding: outputData, as: UTF8.self)
            throw TantivyError.buildFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
    }

    private static func findExecutable(_ name: String) -> String? {
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

private extension TantivyEngine {
    enum Operation: Encodable {
        case add(path: String, content: String)
        case delete(path: String)

        enum CodingKeys: String, CodingKey {
            case type, path, content
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .add(let path, let content):
                try container.encode("add", forKey: .type)
                try container.encode(path, forKey: .path)
                try container.encode(content, forKey: .content)
            case .delete(let path):
                try container.encode("delete", forKey: .type)
                try container.encode(path, forKey: .path)
            }
        }
    }

    struct ApplyPayload: Encodable {
        let indexPath: String
        let operations: [Operation]

        enum CodingKeys: String, CodingKey {
            case indexPath = "index_path"
            case operations
        }
    }

    struct SearchPayload: Encodable {
        let indexPath: String
        let query: String
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case indexPath = "index_path"
            case query
            case limit
        }
    }

    struct SearchResponse: Decodable {
        let hits: [TantivySearchHit]
    }

    enum TantivyError: Error {
        case cargoUnavailable
        case buildFailed(String)
        case processFailed(status: Int32, message: String)
        case sidecarSourceMissing
        case sidecarUnavailable
    }
}
