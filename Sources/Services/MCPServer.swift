import Foundation
import Network

/// MCP (Model Context Protocol) server for AI tool integration
class MCPServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 9881
    var isRunning: Bool { listener != nil }

    let tools: [[String: Any]] = [
        [
            "name": "search_documents",
            "description": "Search local documents by keyword. Returns matching file paths and snippets.",
            "inputSchema": [
                "type": "object",
                "properties": ["query": ["type": "string", "description": "Search query"]],
                "required": ["query"]
            ] as [String: Any]
        ],
        [
            "name": "get_document_content",
            "description": "Get the text content of a document by file path.",
            "inputSchema": [
                "type": "object",
                "properties": ["path": ["type": "string", "description": "File path"]],
                "required": ["path"]
            ] as [String: Any]
        ],
        [
            "name": "index_status",
            "description": "Get the current index status (document count).",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ]
    ]

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
            let results = await SearchEngine.shared.search(query: query, limit: 10)
            let items = results.map { "[\($0.fileName)] \($0.filePath)\n  \($0.snippet)" }
            return items.isEmpty ? "No results found." : items.joined(separator: "\n\n")

        case "get_document_content":
            let path = arguments["path"] as? String ?? ""
            return (try? String(contentsOfFile: path, encoding: .utf8).prefix(8000).description) ?? "Cannot read file."

        case "index_status":
            let count = await SearchEngine.shared.documentCount
            return "Indexed documents: \(count)"

        default:
            return "Unknown tool: \(name)"
        }
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
