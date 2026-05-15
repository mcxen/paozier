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
    :root{--bg:#f8fafc;--surface:#fff;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--faint:#94a3b8;--accent:#3b82f6;--accent-bg:rgba(59,130,246,.08);--shadow:0 1px 3px rgba(0,0,0,.06);--radius:.75rem}
    @media(prefers-color-scheme:dark){:root{--bg:#0f172a;--surface:#1e293b;--border:#334155;--text:#f1f5f9;--muted:#94a3b8;--faint:#475569;--accent:#60a5fa;--accent-bg:rgba(96,165,250,.1);--shadow:0 1px 3px rgba(0,0,0,.3)}}
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,system-ui,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);min-height:100vh;min-height:100dvh;display:flex;flex-direction:column}
    .header{position:sticky;top:0;z-index:10;background:var(--bg);border-bottom:1px solid var(--border);padding:clamp(.75rem,2vw,1.25rem) clamp(1rem,4vw,2rem)}
    .brand{font-size:clamp(1.1rem,3vw,1.4rem);font-weight:700;display:flex;align-items:center;gap:.4rem;margin-bottom:clamp(.5rem,1.5vw,.75rem)}
    .search-box{display:flex;gap:.5rem}
    input{flex:1;min-height:44px;padding:.6rem 1rem;border:1.5px solid var(--border);border-radius:var(--radius);font-size:clamp(.9rem,2.5vw,1rem);background:var(--surface);color:var(--text);outline:none;transition:border-color .2s,box-shadow .2s}
    input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-bg)}
    input::placeholder{color:var(--faint)}
    button{min-height:44px;min-width:44px;padding:.6rem 1.2rem;background:var(--accent);color:#fff;border:none;border-radius:var(--radius);cursor:pointer;font-size:clamp(.85rem,2.5vw,.95rem);font-weight:600;transition:transform .1s,opacity .2s}
    button:hover{opacity:.9}
    button:active{transform:scale(.96)}
    .main{flex:1;padding:clamp(.75rem,3vw,1.5rem) clamp(1rem,4vw,2rem);max-width:860px;width:100%;margin:0 auto}
    .count{font-size:clamp(.75rem,2vw,.85rem);color:var(--muted);margin-bottom:.75rem;opacity:0;transition:opacity .3s}
    .count.show{opacity:1}
    .results{display:grid;gap:.6rem}
    .result{border:1px solid var(--border);border-radius:var(--radius);padding:clamp(.7rem,2vw,1rem);background:var(--surface);box-shadow:var(--shadow);transition:transform .15s,box-shadow .15s;animation:fadeUp .25s ease both}
    .result:hover{transform:translateY(-1px);box-shadow:0 4px 12px rgba(0,0,0,.08)}
    @media(prefers-color-scheme:dark){.result:hover{box-shadow:0 4px 12px rgba(0,0,0,.3)}}
    .result h3{font-size:clamp(.85rem,2.5vw,.95rem);font-weight:600;margin-bottom:.25rem;word-break:break-all}
    .result p{font-size:clamp(.78rem,2vw,.85rem);color:var(--muted);line-height:1.5;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
    .result small{display:block;margin-top:.4rem;font-size:clamp(.65rem,1.8vw,.75rem);color:var(--faint);word-break:break-all}
    .empty{text-align:center;color:var(--faint);padding:clamp(2rem,8vw,4rem) 1rem;font-size:clamp(.9rem,2.5vw,1rem)}
    .skeleton{display:flex;flex-direction:column;gap:.6rem}
    .skel-card{height:5rem;border-radius:var(--radius);background:linear-gradient(90deg,var(--border) 25%,var(--surface) 50%,var(--border) 75%);background-size:200% 100%;animation:shimmer 1.5s infinite}
    .footer{padding:.75rem clamp(1rem,4vw,2rem);border-top:1px solid var(--border);display:flex;align-items:center;gap:.5rem;font-size:clamp(.7rem,1.8vw,.8rem);color:var(--faint)}
    .dot{width:8px;height:8px;border-radius:50%;background:#22c55e;flex-shrink:0}
    @keyframes fadeUp{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}
    @keyframes shimmer{to{background-position:-200% 0}}
    @media(min-width:768px){.results{grid-template-columns:repeat(auto-fill,minmax(320px,1fr))}}
    </style></head>
    <body>
    <div class="header">
      <div class="brand">🔍 Paozier</div>
      <div class="search-box"><input id="q" placeholder="搜索文档内容..." autofocus><button onclick="doSearch()">搜索</button></div>
    </div>
    <div class="main">
      <div id="count" class="count"></div>
      <div id="results"><p class="empty">输入关键词搜索本地文档</p></div>
    </div>
    <div class="footer"><div class="dot"></div><span id="status">加载中...</span></div>
    <script>
    const q=document.getElementById('q'),res=document.getElementById('results'),cnt=document.getElementById('count'),st=document.getElementById('status');
    q.addEventListener('keydown',e=>{if(e.key==='Enter')doSearch()});
    async function doSearch(){
      const v=q.value.trim();
      if(!v){res.innerHTML='<p class="empty">输入关键词搜索</p>';cnt.textContent='';cnt.classList.remove('show');return}
      res.innerHTML='<div class="skeleton">'+('<div class="skel-card"></div>').repeat(4)+'</div>';
      cnt.classList.remove('show');
      try{
        const r=await fetch('/api/search?q='+encodeURIComponent(v)).then(r=>r.json());
        cnt.textContent='找到 '+r.total+' 个结果';cnt.classList.add('show');
        if(!r.results.length){res.innerHTML='<p class="empty">无匹配结果</p>';return}
        res.innerHTML='<div class="results">'+r.results.map((i,idx)=>'<div class="result" style="animation-delay:'+idx*50+'ms"><h3>'+esc(i.fileName)+'</h3><p>'+esc(i.snippet)+'</p><small>'+esc(i.filePath)+'</small></div>').join('')+'</div>';
      }catch(e){res.innerHTML='<p class="empty">请求失败</p>';}
    }
    function esc(s){return s?s.replace(/&/g,'&amp;').replace(/</g,'&lt;'):''}
    fetch('/api/status').then(r=>r.json()).then(d=>{st.textContent=d.documents+' 个文档已索引';}).catch(()=>{st.textContent='离线';});
    </script></body></html>
    """
}
