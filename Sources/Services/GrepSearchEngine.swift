import Foundation

actor GrepSearchEngine {
    static let shared = GrepSearchEngine()

    private let rgPath: String?
    private let grepPath = "/usr/bin/grep"
    private let batchSize = 10
    private let maxMatchesPerFile = 50
    private let smallFileLimit: UInt64 = 5 * 1024 * 1024

    private let skippedExtensions: Set<String> = [
        "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx",
        "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp", "ico",
        "zip", "gz", "bz2", "xz", "7z", "rar", "tar", "dmg", "pkg",
        "mp3", "m4a", "wav", "flac", "mp4", "mov", "avi", "mkv",
        "ttf", "otf", "woff", "woff2", "eot", "sqlite", "db"
    ]

    init() {
        rgPath = Self.findExecutable("rg")
    }

    func search(
        query: String,
        folderPaths: [String],
        allowedExtensions: Set<String>?,
        isRegex: Bool
    ) -> AsyncStream<GrepBatchResult> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = folderPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        return AsyncStream { continuation in
            let worker = Task.detached(priority: .userInitiated) { [rgPath, grepPath, batchSize, maxMatchesPerFile, smallFileLimit, skippedExtensions] in
                guard !trimmedQuery.isEmpty, !folders.isEmpty else {
                    continuation.yield(GrepBatchResult(results: [], isFinal: true))
                    continuation.finish()
                    return
                }

                var pending: [SearchResult] = []

                func emit(_ result: SearchResult) {
                    pending.append(result)
                    if pending.count >= batchSize {
                        continuation.yield(GrepBatchResult(results: pending, isFinal: false))
                        pending.removeAll(keepingCapacity: true)
                    }
                }

                if let rgPath {
                    for folder in folders where !Task.isCancelled {
                        Self.runRipgrep(
                            executablePath: rgPath,
                            query: trimmedQuery,
                            folderPath: folder,
                            allowedExtensions: allowedExtensions,
                            isRegex: isRegex,
                            skippedExtensions: skippedExtensions,
                            emit: emit
                        )
                    }
                } else {
                    for folder in folders where !Task.isCancelled {
                        Self.runSwiftAndGrepFallback(
                            grepPath: grepPath,
                            query: trimmedQuery,
                            folderPath: folder,
                            allowedExtensions: allowedExtensions,
                            isRegex: isRegex,
                            maxMatchesPerFile: maxMatchesPerFile,
                            smallFileLimit: smallFileLimit,
                            skippedExtensions: skippedExtensions,
                            emit: emit
                        )
                    }
                }

                if !pending.isEmpty {
                    continuation.yield(GrepBatchResult(results: pending, isFinal: false))
                }
                continuation.yield(GrepBatchResult(results: [], isFinal: true))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
    }

    private static func runRipgrep(
        executablePath: String,
        query: String,
        folderPath: String,
        allowedExtensions: Set<String>?,
        isRegex: Bool,
        skippedExtensions: Set<String>,
        emit: @escaping (SearchResult) -> Void
    ) {
        var arguments = [
            "--line-number",
            "--ignore-case",
            "--color", "never",
            "--no-heading",
            "--max-count", "50"
        ]
        if !isRegex { arguments.append("--fixed-strings") }
        if let allowedExtensions, !allowedExtensions.isEmpty {
            for ext in allowedExtensions.sorted() {
                arguments += ["--glob", "*.\(ext)"]
            }
        } else {
            for ext in skippedExtensions.sorted() {
                arguments += ["--glob", "!*.\(ext)"]
            }
        }
        arguments += ["--", query, folderPath]

        runProcess(executablePath: executablePath, arguments: arguments) { line in
            if let result = parseGrepLine(line) {
                emit(result)
            }
        }
    }

    private static func runSwiftAndGrepFallback(
        grepPath: String,
        query: String,
        folderPath: String,
        allowedExtensions: Set<String>?,
        isRegex: Bool,
        maxMatchesPerFile: Int,
        smallFileLimit: UInt64,
        skippedExtensions: Set<String>,
        emit: @escaping (SearchResult) -> Void
    ) {
        for fileURL in searchableFiles(in: folderPath, allowedExtensions: allowedExtensions, skippedExtensions: skippedExtensions) where !Task.isCancelled {
            let size = fileSize(at: fileURL.path)
            if size <= smallFileLimit {
                swiftSearchFile(fileURL, query: query, isRegex: isRegex, maxMatches: maxMatchesPerFile, emit: emit)
            } else {
                grepFile(grepPath: grepPath, fileURL: fileURL, query: query, isRegex: isRegex, maxMatches: maxMatchesPerFile, emit: emit)
            }
        }
    }

    private static func swiftSearchFile(
        _ fileURL: URL,
        query: String,
        isRegex: Bool,
        maxMatches: Int,
        emit: (SearchResult) -> Void
    ) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: .newlines)
        let regex = isRegex ? try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) : nil
        let needle = query.lowercased()
        var matches = 0

        for (idx, line) in lines.enumerated() {
            let isMatch: Bool
            if isRegex, let regex {
                isMatch = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil
            } else {
                isMatch = line.lowercased().contains(needle)
            }
            guard isMatch else { continue }

            let start = max(0, idx - 2)
            let end = min(lines.count - 1, idx + 2)
            let context = lines[start...end].joined(separator: " ")
            emit(makeResult(filePath: fileURL.path, lineNumber: idx + 1, lineContent: context))
            matches += 1
            if matches >= maxMatches { break }
        }
    }

    private static func grepFile(
        grepPath: String,
        fileURL: URL,
        query: String,
        isRegex: Bool,
        maxMatches: Int,
        emit: @escaping (SearchResult) -> Void
    ) {
        var arguments = ["-n", "-i", "-I", "--max-count=\(maxMatches)"]
        if !isRegex { arguments.append("-F") }
        arguments += ["--", query, fileURL.path]
        runProcess(executablePath: grepPath, arguments: arguments) { line in
            let prefixed = "\(fileURL.path):\(line)"
            if let result = parseGrepLine(prefixed) {
                emit(result)
            }
        }
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        onLine: @escaping (String) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return
        }

        let handle = output.fileHandleForReading
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let range = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    onLine(line)
                }
            }
        }
        process.waitUntilExit()
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
            onLine(line)
        }
    }

    private static func parseGrepLine(_ line: String) -> SearchResult? {
        let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let lineNumber = Int(parts[1]) else { return nil }
        return makeResult(filePath: String(parts[0]), lineNumber: lineNumber, lineContent: String(parts[2]))
    }

    private static func makeResult(filePath: String, lineNumber: Int, lineContent: String) -> SearchResult {
        let url = URL(fileURLWithPath: filePath)
        let normalized = url.standardizedFileURL.path
        let fileName = url.lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: normalized)
        return SearchResult(
            id: "grep:\(normalized):\(lineNumber)",
            filePath: normalized,
            fileName: fileName,
            title: fileName,
            author: "",
            snippet: LF("行%d: %@", lineNumber, lineContent.trimmingCharacters(in: .whitespacesAndNewlines)),
            content: lineContent,
            fileSize: attrs?[.size] as? Int64 ?? 0,
            lastModified: attrs?[.modificationDate] as? Date
        )
    }

    private static func searchableFiles(
        in folderPath: String,
        allowedExtensions: Set<String>?,
        skippedExtensions: Set<String>
    ) -> [URL] {
        let fm = FileManager.default
        let folderURL = URL(fileURLWithPath: folderPath)
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if let allowedExtensions, !allowedExtensions.isEmpty, !allowedExtensions.contains(ext) { continue }
            if allowedExtensions == nil, skippedExtensions.contains(ext) { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append(fileURL.standardizedFileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func fileSize(at path: String) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
    }

    private static func findExecutable(_ name: String) -> String? {
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
