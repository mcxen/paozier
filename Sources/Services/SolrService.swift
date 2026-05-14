import Foundation

actor SolrService {
    static let shared = SolrService()
    private let baseURL = "http://localhost:8983/solr/paozier"

    func search(query: String, rows: Int = 20) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "\(baseURL)/select?q=\(encoded)&rows=\(rows)&hl=true&hl.fl=content,title,file_name&hl.snippets=3&hl.fragsize=200&wt=json"
        guard let url = URL(string: urlStr) else { throw SolrError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let response = json["response"] as? [String: Any] ?? [:]
        let docs = response["docs"] as? [[String: Any]] ?? []
        let highlighting = json["highlighting"] as? [String: [String: [String]]] ?? [:]

        return docs.map { doc in
            let id = doc["id"] as? String ?? UUID().uuidString
            let snippets = highlighting[id]?["content"] ?? highlighting[id]?["title"] ?? []
            let snippet = snippets.joined(separator: " ... ")
                .replacingOccurrences(of: "<em>", with: "")
                .replacingOccurrences(of: "</em>", with: "")

            return SearchResult(
                id: id,
                filePath: doc["file_path"] as? String ?? "",
                fileName: (doc["file_name"] as? String) ?? (doc["file_path"] as? String)?.components(separatedBy: "/").last ?? "",
                title: (doc["title"] as? String) ?? "",
                author: (doc["author"] as? String) ?? "",
                snippet: snippet,
                fileSize: (doc["file_size"] as? Int64) ?? 0,
                lastModified: nil
            )
        }
    }

    func indexPDF(at fileURL: URL) async throws {
        let id = fileURL.path.data(using: .utf8)!.base64EncodedString()
        let fileName = fileURL.lastPathComponent
        let filePath = fileURL.path
        let urlStr = "\(baseURL)/update/extract?literal.id=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&literal.file_path=\(filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&literal.file_name=\(fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&commit=false&wt=json"

        guard let url = URL(string: urlStr) else { throw SolrError.invalidURL }

        let fileData = try Data(contentsOf: fileURL)
        let mimeType = Self.mimeType(for: fileURL.pathExtension)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 else {
            throw SolrError.indexFailed
        }
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "rtf": return "application/rtf"
        case "html", "htm": return "text/html"
        case "xml": return "application/xml"
        case "json": return "application/json"
        case "csv", "tsv": return "text/csv"
        case "epub": return "application/epub+zip"
        case "odt": return "application/vnd.oasis.opendocument.text"
        case "ods": return "application/vnd.oasis.opendocument.spreadsheet"
        case "odp": return "application/vnd.oasis.opendocument.presentation"
        default: return "text/plain"
        }
    }

    func commit() async throws {
        let urlStr = "\(baseURL)/update?commit=true&wt=json"
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        _ = try await URLSession.shared.data(for: request)
    }

    func docCount() async throws -> Int {
        let urlStr = "\(baseURL)/select?q=*:*&rows=0&wt=json"
        guard let url = URL(string: urlStr) else { return 0 }
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let response = json["response"] as? [String: Any] ?? [:]
        return response["numFound"] as? Int ?? 0
    }

    func deleteAll() async throws {
        let urlStr = "\(baseURL)/update?commit=true&wt=json"
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"delete\":{\"query\":\"*:*\"}}".data(using: .utf8)
        _ = try await URLSession.shared.data(for: request)
    }
}

enum SolrError: Error, LocalizedError {
    case invalidURL
    case indexFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 Solr URL"
        case .indexFailed: return "索引失败"
        }
    }
}
