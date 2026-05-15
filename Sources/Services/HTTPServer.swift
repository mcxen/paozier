import Foundation
import Network

/// Lightweight HTTP server for web-based search
class HTTPServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 9880
    var isRunning: Bool { listener != nil }

    func start(port: UInt16 = 9880) throws {
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
            guard let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            Task {
                let response = await self?.handleRequest(request) ?? Self.response(status: 500, body: "Error")
                conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    private func handleRequest(_ raw: String) async -> String {
        let lines = raw.split(separator: "\r\n")
        guard let firstLine = lines.first else { return Self.response(status: 400, body: "Bad Request") }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return Self.response(status: 400, body: "Bad Request") }

        let method = String(parts[0])
        let path = String(parts[1])

        if method == "GET" && path == "/" {
            return Self.response(status: 200, body: Self.searchPage, contentType: "text/html; charset=utf-8")
        }

        if method == "GET" && path.hasPrefix("/api/search") {
            let query = Self.queryParam(from: path, key: "q") ?? ""
            if query.isEmpty {
                return Self.jsonResponse(["results": [], "total": 0] as [String: Any])
            }
            let results = await SearchEngine.shared.search(query: query, limit: 20)
            let items = results.map { r in
                ["id": r.id, "fileName": r.fileName, "filePath": r.filePath, "snippet": r.snippet, "fileSize": r.fileSize] as [String: Any]
            }
            return Self.jsonResponse(["results": items, "total": items.count, "query": query])
        }

        if method == "GET" && path == "/api/status" {
            let count = await SearchEngine.shared.documentCount
            return Self.jsonResponse(["ok": true, "documents": count])
        }

        return Self.response(status: 404, body: "Not Found")
    }

    // MARK: - Helpers

    private static func response(status: Int, body: String, contentType: String = "text/plain; charset=utf-8") -> String {
        let statusText = status == 200 ? "OK" : status == 404 ? "Not Found" : "Error"
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private static func jsonResponse(_ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let body = String(data: data, encoding: .utf8) ?? "{}"
        return response(status: 200, body: body, contentType: "application/json; charset=utf-8")
    }

    private static func queryParam(from path: String, key: String) -> String? {
        guard let queryStart = path.firstIndex(of: "?") else { return nil }
        let queryString = String(path[path.index(after: queryStart)...])
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 && kv[0] == key {
                return String(kv[1]).removingPercentEncoding
            }
        }
        return nil
    }

    private static let searchPage = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Paozier Search</title>
    <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,system-ui,sans-serif;background:#f8fafc;color:#1e293b;padding:2rem}
    .container{max-width:720px;margin:0 auto}
    h1{font-size:1.5rem;margin-bottom:1rem;display:flex;align-items:center;gap:.5rem}
    .search-box{display:flex;gap:.5rem;margin-bottom:1.5rem}
    input{flex:1;padding:.6rem .8rem;border:1px solid #e2e8f0;border-radius:.5rem;font-size:.9rem;outline:none}
    input:focus{border-color:#3b82f6;box-shadow:0 0 0 2px rgba(59,130,246,.15)}
    button{padding:.6rem 1.2rem;background:#0f172a;color:#fff;border:none;border-radius:.5rem;cursor:pointer;font-size:.9rem}
    button:hover{background:#1e293b}
    .result{border:1px solid #e2e8f0;border-radius:.5rem;padding:.8rem;margin-bottom:.6rem;background:#fff}
    .result h3{font-size:.9rem;margin-bottom:.3rem}
    .result p{font-size:.8rem;color:#64748b;line-height:1.4}
    .result small{font-size:.7rem;color:#94a3b8}
    .empty{text-align:center;color:#94a3b8;padding:3rem 0}
    .count{font-size:.8rem;color:#64748b;margin-bottom:.8rem}
    </style></head>
    <body><div class="container">
    <h1>🔍 Paozier Search</h1>
    <div class="search-box"><input id="q" placeholder="搜索文档内容..." autofocus><button onclick="doSearch()">搜索</button></div>
    <div id="count"></div><div id="results"><p class="empty">输入关键词搜索本地文档</p></div>
    </div>
    <script>
    const q=document.getElementById('q'),res=document.getElementById('results'),cnt=document.getElementById('count');
    q.addEventListener('keydown',e=>{if(e.key==='Enter')doSearch()});
    async function doSearch(){
      const v=q.value.trim();if(!v){res.innerHTML='<p class="empty">输入关键词搜索</p>';cnt.textContent='';return}
      res.innerHTML='<p class="empty">搜索中...</p>';
      const r=await fetch('/api/search?q='+encodeURIComponent(v)).then(r=>r.json());
      cnt.textContent=`找到 ${r.total} 个结果`;
      if(!r.results.length){res.innerHTML='<p class="empty">无匹配结果</p>';return}
      res.innerHTML=r.results.map(i=>`<div class="result"><h3>${esc(i.fileName)}</h3><p>${esc(i.snippet)}</p><small>${esc(i.filePath)}</small></div>`).join('');
    }
    function esc(s){return s?s.replace(/&/g,'&amp;').replace(/</g,'&lt;'):''}
    </script></body></html>
    """
}
