import Foundation
import Network

/// MCP (Model Context Protocol) server for AI tool integration
class MCPServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 9881
    var isRunning: Bool { listener != nil }

    private static let toolsJSON = """
    [
      {"name":"search_documents","description":"Full-text search across all indexed documents.","inputSchema":{"type":"object","properties":{"query":{"type":"string","description":"Search keywords"},"limit":{"type":"integer","description":"Max results (default 10)"}},"required":["query"]}},
      {"name":"get_document_content","description":"Read the full text content of a file by path.","inputSchema":{"type":"object","properties":{"path":{"type":"string","description":"Absolute file path"}},"required":["path"]}},
      {"name":"index_folder","description":"Add a folder to the search index. Recursively indexes all supported files.","inputSchema":{"type":"object","properties":{"path":{"type":"string","description":"Absolute folder path"}},"required":["path"]}},
      {"name":"list_indexed_folders","description":"List all currently indexed folders with file counts.","inputSchema":{"type":"object","properties":{}}},
      {"name":"index_status","description":"Get index status: total documents, engine info, services.","inputSchema":{"type":"object","properties":{}}},
      {"name":"list_files","description":"List files in a directory. Returns names, sizes, types.","inputSchema":{"type":"object","properties":{"path":{"type":"string","description":"Directory path"},"extensions":{"type":"string","description":"Filter by extensions (comma-separated)"}},"required":["path"]}},
      {"name":"get_file_info","description":"Get metadata of a file: size, date, type.","inputSchema":{"type":"object","properties":{"path":{"type":"string","description":"Absolute file path"}},"required":["path"]}},
      {"name":"remove_folder","description":"Remove a folder from the search index.","inputSchema":{"type":"object","properties":{"path":{"type":"string","description":"Folder path to remove"}},"required":["path"]}},
      {"name":"reindex_all","description":"Rebuild the entire search index.","inputSchema":{"type":"object","properties":{}}}
    ]
    """

    var tools: Any { (try? JSONSerialization.jsonObject(with: Data(Self.toolsJSON.utf8))) ?? [] }

    func start(port: UInt16 = 9881) throws {
        self.port = port
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data else { conn.cancel(); return }
            Task {
                let response = await self.handleMCPRequest(data)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    private func handleMCPRequest(_ data: Data) async -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return jsonRPCError(id: nil, code: -32700, message: "Parse error")
        }

        let id = json["id"]
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return jsonRPCResult(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "paozier", "version": "1.0.0"]
            ])
        case "tools/list":
            return jsonRPCResult(id: id, result: ["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let result = await callTool(name: name, arguments: args)
            return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": result]]])
        default:
            return jsonRPCError(id: id, code: -32601, message: "Method not found")
        }
    }

    private func callTool(name: String, arguments: [String: Any]) async -> String {
        switch name {
        case "search_documents":
            let query = arguments["query"] as? String ?? ""
            let limit = arguments["limit"] as? Int ?? 10
            let results = await SearchEngine.shared.search(query: query, limit: limit)
            if results.isEmpty { return "No results found for: \(query)" }
            return results.map { "[\($0.fileName)] \($0.filePath)\n  \($0.snippet)" }.joined(separator: "\n\n")

        case "get_document_content":
            let path = arguments["path"] as? String ?? ""
            guard FileManager.default.fileExists(atPath: path) else { return "File not found: \(path)" }
            return (try? String(contentsOfFile: path, encoding: .utf8).prefix(16000).description) ?? "Cannot read file (binary or encoding issue)."

        case "index_folder":
            let path = arguments["path"] as? String ?? ""
            guard FileManager.default.fileExists(atPath: path) else { return "Folder not found: \(path)" }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            guard isDir.boolValue else { return "Not a directory: \(path)" }

            // Index via engine
            let url = URL(fileURLWithPath: path)
            let files = findFiles(in: url)
            var indexed = 0
            for file in files {
                do { try await SearchEngine.shared.indexFile(at: file); indexed += 1 } catch {}
            }
            await SearchEngine.shared.commit()
            return "Indexed \(indexed)/\(files.count) files from: \(path)"

        case "list_indexed_folders":
            let folders = await MainActor.run { IndexManager.shared?.indexedFolders ?? [] }
            if folders.isEmpty { return "No folders indexed." }
            return folders.map { "[\($0.fileCount) files] \($0.path)" }.joined(separator: "\n")

        case "index_status":
            let count = await SearchEngine.shared.documentCount
            return "Documents: \(count)\nEngines: SearchKit + SQLite FTS5\nHTTP: localhost:9880\nMCP: localhost:9881"

        case "list_files":
            let path = arguments["path"] as? String ?? ""
            let extFilter = (arguments["extensions"] as? String)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard FileManager.default.fileExists(atPath: path) else { return "Path not found: \(path)" }
            let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            var lines: [String] = []
            for item in items.sorted() {
                let full = (path as NSString).appendingPathComponent(item)
                let ext = (item as NSString).pathExtension.lowercased()
                if let filter = extFilter, !filter.isEmpty, !filter.contains(ext) { continue }
                let attrs = try? FileManager.default.attributesOfItem(atPath: full)
                let size = attrs?[.size] as? Int64 ?? 0
                let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
                lines.append("\(isDir ? "📁" : "📄") \(item) (\(formatSize(size)))")
            }
            return lines.isEmpty ? "Empty directory." : lines.joined(separator: "\n")

        case "get_file_info":
            let path = arguments["path"] as? String ?? ""
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return "File not found: \(path)" }
            let size = attrs[.size] as? Int64 ?? 0
            let modified = attrs[.modificationDate] as? Date
            let type = (path as NSString).pathExtension
            return "Path: \(path)\nSize: \(formatSize(size))\nType: \(type)\nModified: \(modified?.description ?? "unknown")"

        case "remove_folder":
            let path = arguments["path"] as? String ?? ""
            await MainActor.run { IndexManager.shared?.indexedFolders.removeAll { $0.path == path } }
            return "Removed folder: \(path)"

        case "reindex_all":
            await MainActor.run { Task { await IndexManager.shared?.reindexAll() } }
            return "Reindex started."

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func findFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if IndexManager.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        return files
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func jsonRPCResult(id: Any?, result: [String: Any]) -> Data {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }

    private func jsonRPCError(id: Any?, code: Int, message: String) -> Data {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }
}
