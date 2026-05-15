# Paozier

macOS 本地全文搜索客户端，基于 Apple SearchKit + SQLite FTS5 双引擎。

## 功能

- 选择本地文件夹，自动扫描并索引所有支持格式的文件
- SearchKit + SQLite FTS5 双引擎融合搜索（支持中英文）
- 搜索结果高亮显示匹配片段（Live Preview）
- 内置多格式预览（PDFKit / QuickLook / 文本）
- 增量索引，支持多文件夹管理
- 内置 HTTP 搜索服务（端口 9880）
- 内置 MCP 服务器（端口 9881），供 AI 工具集成
- 报告收集、搜索历史、书签

## 支持格式

PDF · Word (docx) · Excel (xlsx) · PowerPoint (pptx) · RTF · HTML · TXT · Markdown · JSON · XML · CSV · EPUB · 代码文件 (swift/py/js/ts/java/c/cpp/rs/go 等)

## 技术栈

- SwiftUI macOS App (macOS 14+)
- Apple SearchKit（DFSearchKit 封装）— TF-IDF 相关性排序
- SQLite FTS5（DSFFullTextSearchIndex 封装）— CJK 全文索引
- Network.framework (NWListener) — 轻量 HTTP/TCP 服务器
- PDFKit + QuickLook — 文件预览

## 快速开始

```bash
# 1. 构建
swift build

# 2. 运行（自动启动 HTTP:9880 和 MCP:9881 服务）
swift run Paozier
```

无需安装 Java、Solr 或任何外部依赖。

## HTTP API

应用启动后自动监听 `localhost:9880`：

```bash
# 状态
curl http://localhost:9880/api/status

# 搜索
curl "http://localhost:9880/api/search?q=关键词"

# 网页搜索界面
open http://localhost:9880
```

## MCP Server

应用启动后自动监听 `localhost:9881`，支持 JSON-RPC 2.0：

```bash
# 列出工具
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | nc localhost 9881

# 搜索文档
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"全文搜索"}}}' | nc localhost 9881

# 索引文件夹
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"index_folder","arguments":{"path":"/path/to/folder"}}}' | nc localhost 9881
```

可用工具：`search_documents`、`get_document_content`、`index_folder`、`list_indexed_folders`、`index_status`、`list_files`、`get_file_info`、`remove_folder`、`reindex_all`

## 目录结构

```
paozier/
├── Package.swift              # SPM 配置
├── Sources/
│   ├── App/
│   │   ├── PaozierApp.swift       # @main 入口
│   │   └── ContentView.swift      # 主界面（三栏布局）
│   ├── Views/
│   │   ├── SidebarView.swift      # 侧边栏
│   │   ├── SearchResultsView.swift # 搜索结果列表
│   │   ├── PDFPreviewView.swift   # 多格式预览
│   │   ├── LivePreviewView.swift  # 高亮文本预览
│   │   ├── FolderContentView.swift # 文件夹浏览
│   │   ├── HistoryView.swift      # 搜索历史/书签
│   │   ├── CompendiumView.swift   # 报告管理
│   │   └── ProximitySearchView.swift # 邻近搜索
│   ├── Services/
│   │   ├── SearchEngine.swift     # 双引擎搜索 + 文本提取
│   │   ├── IndexManager.swift     # 索引/文件夹管理
│   │   ├── DataManager.swift      # 持久化（历史/书签/报告）
│   │   ├── HTTPServer.swift       # HTTP 搜索服务
│   │   └── MCPServer.swift        # MCP AI 工具服务
│   └── Models/
│       └── Models.swift           # 数据模型
├── .github/workflows/
│   └── release-dmg.yml            # CI: Universal Binary → DMG
└── README.md
```

## 数据存储

运行时数据位于 `~/Library/Application Support/Paozier/`：
- `searchkit.index` — SearchKit 索引
- `fts.db` — SQLite FTS5 数据库
- `folders.json` — 已索引文件夹
- `history.json` / `bookmarks.json` / `compendium.json`
