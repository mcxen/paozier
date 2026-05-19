import Foundation

actor MemosSearchService {
    static let shared = MemosSearchService()

    struct ValidationResult {
        let ok: Bool
        let message: String
    }

    private struct MemosListResponse: Decodable {
        let memos: [MemosMemo]
    }

    private struct MemosMemo: Decodable {
        let name: String?
        let uid: String?
        let id: Int?
        let content: String?
        let snippet: String?
        let createTime: String?
        let updateTime: String?
        let displayTime: String?
        let tags: [String]?
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func enabledSources() async -> [MemosSourceConfig] {
        await MainActor.run {
            AppSettings.shared.memosSources.filter { source in
                source.isEnabled &&
                !source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !source.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    func search(query: String, limit: Int = 10) async -> [ExternalSearchResult] {
        let sources = await enabledSources()
        var results: [ExternalSearchResult] = []
        for (index, source) in sources.enumerated() {
            do {
                let sourceResults = try await search(source: source, sourceIndex: index, query: query, limit: limit)
                results.append(contentsOf: sourceResults)
            } catch {
                continue
            }
        }
        return results
    }

    func content(sourceID: String, memoID: String) async throws -> ExternalSearchResult {
        let sources = await MainActor.run { AppSettings.shared.memosSources }
        guard let pair = sources.enumerated().first(where: { $0.element.id == sourceID }) else {
            throw URLError(.badURL)
        }
        let source = pair.element
        let endpoint = try endpointURL(for: source, path: "/api/v1/memos/\(memoID)")
        let data = try await data(for: endpoint, source: source)
        let memo = try decoder.decode(MemosMemo.self, from: data)
        return mapMemo(memo, source: source, sourceIndex: pair.offset, query: "")
    }

    func validate(sourceID: String) async -> ValidationResult {
        let sources = await MainActor.run { AppSettings.shared.memosSources }
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return ValidationResult(ok: false, message: "未找到 Memos 配置")
        }
        return await validate(source: source)
    }

    func validate(source: MemosSourceConfig) async -> ValidationResult {
        do {
            _ = try endpointURL(for: source, path: "/api/v1/memos")
            _ = try await search(source: source, sourceIndex: 0, query: "", limit: 1)
            return ValidationResult(ok: true, message: "连接成功")
        } catch {
            return ValidationResult(ok: false, message: readableError(error))
        }
    }

    private func search(source: MemosSourceConfig, sourceIndex: Int, query: String, limit: Int) async throws -> [ExternalSearchResult] {
        var components = URLComponents(url: try endpointURL(for: source, path: "/api/v1/memos"), resolvingAgainstBaseURL: false)
        let pageSize = max(1, min(limit, 50))
        var queryItems = [URLQueryItem(name: "pageSize", value: String(pageSize))]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "filter", value: #"content.contains("\#(escapedFilterValue(trimmedQuery))")"#))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }

        let data = try await data(for: url, source: source)
        let response = try decoder.decode(MemosListResponse.self, from: data)
        return response.memos
            .prefix(pageSize)
            .map { mapMemo($0, source: source, sourceIndex: sourceIndex, query: trimmedQuery) }
    }

    private func data(for url: URL, source: MemosSourceConfig) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(source.token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func mapMemo(_ memo: MemosMemo, source: MemosSourceConfig, sourceIndex: Int, query: String) -> ExternalSearchResult {
        let content = memo.content ?? ""
        let memoID = memoID(from: memo)
        let sourceName = source.displayName(index: sourceIndex)
        let title = title(from: content, fallback: "Memo \(memoID)")
        let snippet = memo.snippet?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? memo.snippet!
            : snippet(from: content, query: query)
        return ExternalSearchResult(
            id: "memos-\(source.id)-\(memoID)",
            externalID: memoID,
            sourceID: source.id,
            sourceKind: "memos",
            sourceName: sourceName,
            title: title,
            snippet: snippet,
            content: content,
            url: memoURL(source: source, memo: memo),
            createdAt: parseDate(memo.createTime),
            updatedAt: parseDate(memo.updateTime ?? memo.displayTime)
        )
    }

    private func endpointURL(for source: MemosSourceConfig, path: String) throws -> URL {
        let raw = source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let components = URLComponents(string: raw), components.scheme != nil else {
            throw URLError(.badURL)
        }
        var normalizedBase = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedBase.hasSuffix("/api/v1") {
            normalizedBase.removeLast("/api/v1".count)
        }
        guard let url = URL(string: normalizedBase + path) else { throw URLError(.badURL) }
        return url
    }

    private func memoID(from memo: MemosMemo) -> String {
        if let name = memo.name, let id = name.split(separator: "/").last {
            return String(id)
        }
        if let uid = memo.uid, !uid.isEmpty { return uid }
        if let id = memo.id { return String(id) }
        return UUID().uuidString
    }

    private func memoURL(source: MemosSourceConfig, memo: MemosMemo) -> String {
        let raw = source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let id = memo.uid?.isEmpty == false ? memo.uid! : memoID(from: memo)
        return raw.isEmpty ? "" : "\(raw)/m/\(id)"
    }

    private func title(from content: String, fallback: String) -> String {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            return String(title.prefix(80))
        }
        return fallback
    }

    private func snippet(from content: String, query: String) -> String {
        let compact = content.replacingOccurrences(of: "\n", with: " ")
        guard !compact.isEmpty else { return "" }
        let lower = compact.lowercased()
        let term = query.lowercased().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if !term.isEmpty, let range = lower.range(of: term) {
            let start = compact.index(range.lowerBound, offsetBy: -min(80, compact.distance(from: compact.startIndex, to: range.lowerBound)), limitedBy: compact.startIndex) ?? compact.startIndex
            let end = compact.index(range.upperBound, offsetBy: min(160, compact.distance(from: range.upperBound, to: compact.endIndex)), limitedBy: compact.endIndex) ?? compact.endIndex
            return (start == compact.startIndex ? "" : "…") + String(compact[start..<end]) + (end == compact.endIndex ? "" : "…")
        }
        return String(compact.prefix(240))
    }

    private func escapedFilterValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func readableError(_ error: Error) -> String {
        if let error = error as? HTTPError {
            if error.statusCode == 401 || error.statusCode == 403 {
                return "认证失败，请检查 Token"
            }
            return "HTTP \(error.statusCode): \(error.body.prefix(160))"
        }
        if let error = error as? URLError, error.code == .badURL {
            return "服务地址格式不正确"
        }
        return error.localizedDescription
    }
}

private struct HTTPError: Error {
    let statusCode: Int
    let body: String
}
