import Foundation
import AppKit
import Network

/// Lightweight HTTP server for web-based search
class HTTPServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 9880
    var isRunning: Bool { listener != nil }
    private let recentPathsQueue = DispatchQueue(label: "paozier.http.recent-paths")
    private var recentResultPaths: Set<String> = []

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
            rememberResultPaths(results.map(\.filePath))
            return Self.jsonResponse(["results": items, "total": items.count, "query": query])
        }

        if method == "GET" && path.hasPrefix("/api/external_search") {
            let query = Self.queryParam(from: path, key: "q") ?? ""
            if query.isEmpty {
                return Self.jsonResponse(["results": [], "total": 0] as [String: Any])
            }
            let limit = Int(Self.queryParam(from: path, key: "limit") ?? "") ?? 10
            let results = await MemosSearchService.shared.search(query: query, limit: limit)
            let items = results.map(Self.externalResultJSON)
            return Self.jsonResponse(["results": items, "total": items.count, "query": query])
        }

        if method == "GET" && path.hasPrefix("/api/external_content") {
            guard let sourceID = Self.queryParam(from: path, key: "sourceId"),
                  let memoID = Self.queryParam(from: path, key: "id") else {
                return Self.response(status: 400, body: "Missing sourceId or id")
            }
            do {
                let result = try await MemosSearchService.shared.content(sourceID: sourceID, memoID: memoID)
                return Self.jsonResponse(Self.externalResultJSON(result))
            } catch {
                return Self.response(status: 502, body: "External content unavailable")
            }
        }

        if method == "GET" && path.hasPrefix("/api/memos_sources") {
            let sources = await MainActor.run { AppSettings.shared.memosSources }
            let items = sources.enumerated().map { index, source in
                [
                    "id": source.id,
                    "name": source.displayName(index: index),
                    "baseURL": source.baseURL,
                    "enabled": source.isEnabled
                ] as [String: Any]
            }
            return Self.jsonResponse(["sources": items, "total": items.count])
        }

        if method == "GET" && path.hasPrefix("/api/memos_validate") {
            guard let sourceID = Self.queryParam(from: path, key: "id") else {
                return Self.jsonResponse(["ok": false, "message": "missing id"])
            }
            let validation = await MemosSearchService.shared.validate(sourceID: sourceID)
            return Self.jsonResponse(["ok": validation.ok, "message": validation.message])
        }

        if method == "GET" && path.hasPrefix("/api/grep_search") {
            let query = Self.queryParam(from: path, key: "q") ?? ""
            if query.isEmpty {
                return Self.jsonResponse(["results": [], "total": 0] as [String: Any])
            }
            let limit = Int(Self.queryParam(from: path, key: "limit") ?? "") ?? 50
            let isRegex = Self.queryParam(from: path, key: "regex") == "1" || Self.queryParam(from: path, key: "regex") == "true"
            let folders = await indexedFolderPaths().sorted()
            let stream = await GrepSearchEngine.shared.search(
                query: query,
                folderPaths: folders,
                allowedExtensions: nil,
                isRegex: isRegex
            )
            var results: [SearchResult] = []
            for await batch in stream {
                results.append(contentsOf: batch.results)
                if results.count >= limit { break }
            }
            results = Array(results.prefix(limit))
            let items = results.map { r in
                ["id": r.id, "fileName": r.fileName, "filePath": r.filePath, "snippet": r.snippet, "fileSize": r.fileSize] as [String: Any]
            }
            rememberResultPaths(results.map(\.filePath))
            return Self.jsonResponse(["results": items, "total": items.count, "query": query, "engine": "grep"])
        }

        if method == "GET" && path == "/api/status" {
            let count = await SearchEngine.shared.documentCount
            let folders = await indexedFolderPaths().sorted()
            return Self.jsonResponse(["ok": true, "documents": count, "folders": folders])
        }

        if method == "GET" && path.hasPrefix("/api/open") {
            guard let filePath = Self.queryParam(from: path, key: "path"),
                  await isPathAllowed(filePath) else {
                return Self.jsonResponse(["ok": false, "error": "forbidden"])
            }
            await MainActor.run { NSWorkspace.shared.open(URL(fileURLWithPath: filePath)) }
            return Self.jsonResponse(["ok": true])
        }

        if method == "GET" && path.hasPrefix("/api/reveal") {
            guard let filePath = Self.queryParam(from: path, key: "path"),
                  await isPathAllowed(filePath) else {
                return Self.jsonResponse(["ok": false, "error": "forbidden"])
            }
            await MainActor.run { NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "") }
            return Self.jsonResponse(["ok": true])
        }

        if method == "GET" && path.hasPrefix("/api/content") {
            guard let filePath = Self.queryParam(from: path, key: "path"),
                  await isPathAllowed(filePath) else {
                return Self.response(status: 403, body: "Forbidden")
            }
            let url = URL(fileURLWithPath: filePath)
            let content = await SearchEngine.shared.previewText(for: url)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return Self.response(status: 415, body: "Preview unavailable")
            }
            let truncated = String(content.prefix(32000))
            return Self.response(status: 200, body: truncated, contentType: "text/plain; charset=utf-8")
        }

        return Self.response(status: 404, body: "Not Found")
    }

    private func isPathAllowed(_ path: String) async -> Bool {
        let normalizedPath = Self.normalizedPath(path)
        let folders = await indexedFolderPaths()
        if folders.contains(where: { folderPath in
            normalizedPath == folderPath || normalizedPath.hasPrefix(folderPath + "/")
        }) {
            return true
        }
        return isRecentResultPath(normalizedPath)
    }

    private func indexedFolderPaths() async -> Set<String> {
        await MainActor.run {
            Set((IndexManager.shared?.indexedFolders ?? []).map { Self.normalizedPath($0.path) })
        }
    }

    private func rememberResultPaths(_ paths: [String]) {
        let normalized = paths.map(Self.normalizedPath)
        recentPathsQueue.sync {
            recentResultPaths.formUnion(normalized)
            if recentResultPaths.count > 500 {
                recentResultPaths = Set(recentResultPaths.suffix(300))
            }
        }
    }

    private func isRecentResultPath(_ path: String) -> Bool {
        recentPathsQueue.sync { recentResultPaths.contains(path) }
    }

    // MARK: - Helpers

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func response(status: Int, body: String, contentType: String = "text/plain; charset=utf-8") -> String {
        let statusText = status == 200 ? "OK" : status == 404 ? "Not Found" : "Error"
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private static func jsonResponse(_ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let body = String(data: data, encoding: .utf8) ?? "{}"
        return response(status: 200, body: body, contentType: "application/json; charset=utf-8")
    }

    private static func externalResultJSON(_ result: ExternalSearchResult) -> [String: Any] {
        [
            "id": result.id,
            "memoId": result.externalID,
            "sourceId": result.sourceID,
            "sourceKind": result.sourceKind,
            "sourceName": result.sourceName,
            "title": result.title,
            "snippet": result.snippet,
            "content": result.content,
            "url": result.url,
            "createdAt": result.createdAt?.ISO8601Format() ?? "",
            "updatedAt": result.updatedAt?.ISO8601Format() ?? ""
        ]
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
    :root{--bg:#f8fafc;--surface:#fff;--surface-2:#f1f5f9;--border:#e2e8f0;--text:#1e293b;--muted:#64748b;--faint:#94a3b8;--accent:#3b82f6;--accent-bg:rgba(59,130,246,.08);--mark:#fde68a;--mark-text:#111827;--shadow:0 1px 3px rgba(0,0,0,.06);--radius:.75rem}
    @media(prefers-color-scheme:dark){:root{--bg:#0f172a;--surface:#1e293b;--surface-2:#111827;--border:#334155;--text:#f1f5f9;--muted:#94a3b8;--faint:#64748b;--accent:#60a5fa;--accent-bg:rgba(96,165,250,.1);--mark:#facc15;--mark-text:#111827;--shadow:0 1px 3px rgba(0,0,0,.3)}}
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{height:100%}
    body{font-family:-apple-system,system-ui,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);height:100dvh;display:flex;flex-direction:column;overflow:hidden}
    .header{flex:0 0 auto;z-index:10;background:var(--bg);border-bottom:1px solid var(--border);padding:.55rem clamp(.75rem,2vw,1.2rem)}
    .topbar{display:grid;grid-template-columns:auto minmax(220px,1fr) auto;gap:.65rem;align-items:center}
    .brand{font-size:clamp(1rem,2vw,1.15rem);font-weight:700;display:flex;align-items:center;gap:.35rem;white-space:nowrap}
    .search-box{display:flex;gap:.45rem;min-width:0}
    .search-options{display:flex;gap:.75rem;align-items:center;font-size:.76rem;color:var(--muted);white-space:nowrap}
    .search-options label{display:flex;align-items:center;gap:.35rem}
    .search-options input{min-height:auto;flex:0 0 auto;width:14px;height:14px;padding:0}
    input{flex:1;min-height:36px;padding:.45rem .75rem;border:1.5px solid var(--border);border-radius:.65rem;font-size:.92rem;background:var(--surface);color:var(--text);outline:none;transition:border-color .2s,box-shadow .2s}
    input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-bg)}
    input::placeholder{color:var(--faint)}
    .btn{min-height:36px;min-width:52px;padding:.45rem .9rem;background:var(--accent);color:#fff;border:none;border-radius:.65rem;cursor:pointer;font-size:.88rem;font-weight:600;transition:transform .1s,opacity .2s}
    .btn:hover{opacity:.9}
    .btn:active{transform:scale(.96)}
    .content{flex:1 1 auto;min-height:0;display:flex;overflow:hidden}
    .list-pane{flex:1 1 auto;min-width:0;overflow-y:auto;padding:.7rem clamp(.8rem,2vw,1.2rem)}
    .preview-pane{flex:0 0 0;min-width:0;border-left:1px solid var(--border);overflow:hidden;transition:flex-basis .24s ease,min-width .24s ease;background:var(--surface);display:flex;flex-direction:column}
    .preview-pane.open{flex-basis:min(46vw,720px);min-width:380px}
    .preview-header{flex:0 0 auto;padding:.7rem .85rem;background:var(--surface);border-bottom:1px solid var(--border);display:flex;align-items:center;gap:.5rem}
    .preview-header span{flex:1;font-size:.8rem;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .preview-close{background:none;border:none;cursor:pointer;color:var(--muted);font-size:1.1rem;min-height:auto;min-width:auto;padding:2px 6px}
    .preview-meta{flex:0 0 auto;padding:.45rem .85rem;background:var(--surface-2);border-bottom:1px solid var(--border);font-size:.72rem;color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .preview-body{flex:1 1 auto;min-height:0;overflow:auto;padding:1rem;font-family:'SF Mono',Menlo,monospace;font-size:.8rem;white-space:pre-wrap;overflow-wrap:anywhere;color:var(--text);line-height:1.65}
    mark{background:var(--mark);color:var(--mark-text);border-radius:4px;padding:0 .12em}
    mark.current{outline:2px solid var(--accent);outline-offset:1px}
    .count{font-size:.78rem;color:var(--muted);margin-bottom:.45rem;opacity:0;transition:opacity .3s}
    .count.show{opacity:1}
    .results{display:flex;flex-direction:column;gap:.5rem}
    .result{display:flex;border:1px solid var(--border);border-radius:var(--radius);background:var(--surface);box-shadow:var(--shadow);transition:transform .15s,box-shadow .15s,border-color .15s;animation:fadeUp .25s ease both;overflow:hidden}
    .result:hover{transform:translateY(-1px);box-shadow:0 4px 12px rgba(0,0,0,.08);border-color:var(--accent)}
    .result.active{border-color:var(--accent);background:var(--accent-bg)}
    .result-actions{display:flex;flex-direction:column;justify-content:center;gap:2px;padding:.5rem;border-right:1px solid var(--border);background:var(--bg)}
    .act-btn{width:30px;height:30px;display:flex;align-items:center;justify-content:center;border:none;background:none;border-radius:6px;cursor:pointer;color:var(--muted);font-size:.85rem;transition:background .15s,color .15s}
    .act-btn:hover{background:var(--accent-bg);color:var(--accent)}
    .result-body{flex:1;padding:clamp(.6rem,1.5vw,.8rem);cursor:pointer;min-width:0}
    .result-body h3{font-size:clamp(.82rem,2.2vw,.92rem);font-weight:600;margin-bottom:.2rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .result-body p{font-size:clamp(.75rem,1.8vw,.82rem);color:var(--muted);line-height:1.4;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
    .result-body small{display:block;margin-top:.3rem;font-size:clamp(.62rem,1.5vw,.72rem);color:var(--faint);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .source-badge{display:inline-flex;align-items:center;margin-right:.35rem;padding:.08rem .35rem;border-radius:999px;background:var(--accent-bg);color:var(--accent);font-size:.68rem;font-weight:700}
    .section-title{font-size:.75rem;font-weight:700;color:var(--muted);padding:.35rem .1rem .1rem}
    .empty{text-align:center;color:var(--faint);padding:clamp(2rem,8vw,4rem) 1rem;font-size:clamp(.9rem,2.5vw,1rem)}
    .skeleton{display:flex;flex-direction:column;gap:.6rem}
    .skel-card{height:4.5rem;border-radius:var(--radius);background:linear-gradient(90deg,var(--border) 25%,var(--surface) 50%,var(--border) 75%);background-size:200% 100%;animation:shimmer 1.5s infinite}
    .footer{height:28px;padding:0 clamp(.8rem,2vw,1.2rem);border-top:1px solid var(--border);display:flex;align-items:center;gap:.45rem;font-size:.74rem;color:var(--faint)}
    .dot{width:7px;height:7px;border-radius:50%;background:#22c55e;flex-shrink:0}
    @keyframes fadeUp{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}
    @keyframes shimmer{to{background-position:-200% 0}}
    @media(max-width:900px){.topbar{grid-template-columns:1fr;gap:.45rem}.search-options{justify-content:space-between}.preview-pane.open{position:fixed;top:0;right:0;bottom:0;z-index:20;flex-basis:auto;width:min(92vw,560px);min-width:0;box-shadow:-4px 0 20px rgba(0,0,0,.15)}}
    </style></head>
    <body>
    <div class="header">
      <div class="topbar">
        <div class="brand">🔍 Paozier</div>
        <div class="search-box"><input id="q" placeholder="搜索文档内容..." autofocus><button class="btn" onclick="doSearch()">搜索</button></div>
        <div class="search-options"><label><input id="includeMemos" type="checkbox">Memos</label><span id="externalStatus">加载中...</span></div>
      </div>
    </div>
    <div class="content">
      <div class="list-pane">
        <div id="count" class="count"></div>
        <div id="results"><p class="empty">输入关键词搜索本地文档</p></div>
      </div>
      <div id="preview" class="preview-pane">
        <div class="preview-header"><span id="pname"></span><button class="preview-close" onclick="closePreview()">✕</button></div>
        <div class="preview-meta" id="pmeta"></div>
        <pre class="preview-body" id="pbody"></pre>
      </div>
    </div>
    <div class="footer"><div class="dot"></div><span id="status">加载中...</span></div>
    <script>
    const q=document.getElementById('q'),res=document.getElementById('results'),cnt=document.getElementById('count'),st=document.getElementById('status');
    const includeMemos=document.getElementById('includeMemos'),externalStatus=document.getElementById('externalStatus');
    const preview=document.getElementById('preview'),pname=document.getElementById('pname'),pmeta=document.getElementById('pmeta'),pbody=document.getElementById('pbody');
    const previewExts=new Set(['pdf','docx','doc','rtf','odt','epub','xlsx','xls','csv','tsv','ods','pptx','ppt','odp','txt','md','markdown','json','log','yaml','yml','toml','ini','conf','xml','html','htm','swift','py','js','ts','java','c','h','cpp','rs','go','rb','php','sh']);
    let activeResult=null;
    q.addEventListener('keydown',e=>{if(e.key==='Enter')doSearch()});
    async function doSearch(){
      const v=q.value.trim();
      if(!v){res.innerHTML='<p class="empty">输入关键词搜索</p>';cnt.textContent='';cnt.classList.remove('show');closePreview();return}
      res.innerHTML='<div class="skeleton">'+('<div class="skel-card"></div>').repeat(4)+'</div>';
      cnt.classList.remove('show');
      try{
        const localPromise=fetch('/api/search?q='+encodeURIComponent(v)).then(r=>r.json());
        const externalPromise=includeMemos.checked?fetch('/api/external_search?q='+encodeURIComponent(v)+'&limit=10').then(r=>r.json()).catch(()=>({results:[],total:0,error:true})):Promise.resolve({results:[],total:0});
        const [r,external]=await Promise.all([localPromise,externalPromise]);
        const total=r.total+external.total;
        cnt.textContent='找到 '+total+' 个结果（本地 '+r.total+'，Memos '+external.total+'）';cnt.classList.add('show');
        if(!total){res.innerHTML='<p class="empty">无匹配结果</p>';return}
        const terms=searchTerms(v);
        const localHTML=r.results.length?'<div class="section-title">本地文件</div>'+r.results.map((i,idx)=>localResultHTML(i,idx,terms)).join(''):'';
        const externalHTML=external.results.length?'<div class="section-title">Memos</div>'+external.results.map((i,idx)=>memosResultHTML(i,idx,terms)).join(''):'';
        res.innerHTML='<div class="results">'+localHTML+externalHTML+'</div>';
      }catch(e){res.innerHTML='<p class="empty">请求失败</p>';}
    }
    function localResultHTML(i,idx,terms){
      return `<div class="result" id="local-${idx}" style="animation-delay:${idx*40}ms"><div class="result-actions"><button class="act-btn" title="打开文件" onclick="openFile('${escAttr(i.filePath)}')">📂</button><button class="act-btn" title="在 Finder 中显示" onclick="revealFile('${escAttr(i.filePath)}')">📍</button></div><div class="result-body" onclick="showPreview('${escAttr(i.filePath)}','${escAttr(i.fileName)}','local-${idx}')"><h3><span class="source-badge">本地</span>${highlightText(i.fileName,terms)}</h3><p>${highlightText(i.snippet,terms)}</p><small>${esc(i.filePath)}</small></div></div>`;
    }
    function memosResultHTML(i,idx,terms){
      return `<div class="result" id="memos-${idx}" style="animation-delay:${idx*40}ms"><div class="result-actions"><button class="act-btn" title="打开链接" onclick="openExternal('${escAttr(i.url)}')">↗</button></div><div class="result-body" onclick="showMemosPreview('${escAttr(i.sourceId)}','${escAttr(i.memoId)}','${escAttr(i.title)}','memos-${idx}')"><h3><span class="source-badge">${esc(i.sourceName)}</span>${highlightText(i.title,terms)}</h3><p>${highlightText(i.snippet,terms)}</p><small>${esc(i.url||i.sourceName)}</small></div></div>`;
    }
    function openFile(p){fetch('/api/open?path='+encodeURIComponent(p))}
    function revealFile(p){fetch('/api/reveal?path='+encodeURIComponent(p))}
    function openExternal(url){if(url)window.open(url,'_blank','noopener')}
    function activateResult(resultId){
      if(activeResult!==null){const old=document.getElementById(activeResult);if(old)old.classList.remove('active')}
      activeResult=resultId;
      const el=document.getElementById(resultId);if(el)el.classList.add('active');
    }
    async function showPreview(path,name,resultId){
      const ext=path.split('.').pop().toLowerCase();
      activateResult(resultId);
      pname.textContent=name;pmeta.textContent=path;pbody.textContent='加载中...';
      preview.classList.add('open');
      if(!previewExts.has(ext)){
        pbody.textContent='该文件类型暂不支持网页文本预览。可以使用左侧按钮打开文件或在 Finder 中显示。';
        return;
      }
      try{
        const response=await fetch('/api/content?path='+encodeURIComponent(path));
        const t=await response.text();
        if(!response.ok){throw new Error(t||'Preview unavailable')}
        renderPreview(t,searchTerms(q.value));
      }
      catch(e){pbody.textContent='无法加载文件内容';}
    }
    async function showMemosPreview(sourceId,memoId,title,resultId){
      activateResult(resultId);
      pname.textContent=title;pmeta.textContent='Memos';pbody.textContent='加载中...';
      preview.classList.add('open');
      try{
        const response=await fetch('/api/external_content?sourceId='+encodeURIComponent(sourceId)+'&id='+encodeURIComponent(memoId));
        const item=await response.json();
        if(!response.ok){throw new Error('External content unavailable')}
        pmeta.textContent=item.sourceName+(item.url?' · '+item.url:'');
        renderPreview(item.content||item.snippet||'',searchTerms(q.value));
      }catch(e){pbody.textContent='无法加载 Memos 内容';}
    }
    function closePreview(){preview.classList.remove('open');pmeta.textContent='';pbody.textContent='';if(activeResult!==null){const el=document.getElementById(activeResult);if(el)el.classList.remove('active');activeResult=null;}}
    function renderPreview(text,terms){
      pbody.innerHTML=highlightText(text,terms);
      const first=pbody.querySelector('mark');
      if(first){first.classList.add('current');requestAnimationFrame(()=>first.scrollIntoView({block:'center'}));}
      else{pbody.scrollTop=0;}
    }
    function searchTerms(text){
      return [...new Set((text||'').trim().split(/\\s+/).map(t=>t.trim()).filter(t=>t.length>0 && t.length<80))].slice(0,12);
    }
    function highlightText(text,terms){
      if(!text)return '';
      if(!terms.length)return esc(text);
      const pattern=terms.map(escapeRegExp).join('|');
      if(!pattern)return esc(text);
      const regex=new RegExp(pattern,'gi');
      let html='',last=0;
      for(const match of text.matchAll(regex)){
        html+=esc(text.slice(last,match.index))+'<mark>'+esc(match[0])+'</mark>';
        last=match.index+match[0].length;
      }
      return html+esc(text.slice(last));
    }
    function escapeRegExp(s){
      return [...s].map(ch=>'.*+?^${}()|[]'.includes(ch)||ch.charCodeAt(0)===92?'\\\\'+ch:ch).join('');
    }
    function esc(s){return s?s.replace(/&/g,'&amp;').replace(/</g,'&lt;'):''}
    function escAttr(s){
      return esc(s||'').replace(/"/g,'&quot;').replace(/\\\\/g,'\\\\\\\\').replace(/'/g,"\\\\'");
    }
    fetch('/api/status').then(r=>r.json()).then(d=>{st.textContent=d.documents+' 个文档已索引';}).catch(()=>{st.textContent='离线';});
    fetch('/api/memos_sources').then(r=>r.json()).then(d=>{
      const enabled=(d.sources||[]).filter(s=>s.enabled);
      includeMemos.disabled=!enabled.length;
      includeMemos.checked=!!enabled.length;
      externalStatus.textContent=enabled.length?enabled.map(s=>s.name).join('、'):'未启用 Memos 源';
    }).catch(()=>{externalStatus.textContent='外部源不可用';includeMemos.disabled=true;});
    </script></body></html>
    """
}
