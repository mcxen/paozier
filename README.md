<div align="center">

<img width="128" height="128" alt="狍子应用图标" src="https://github.com/user-attachments/assets/9ccc3ca1-9768-4a32-a747-16a1ba1dcc3b" />

# 狍子 (Paozier)

> **"狍子"（páo zi）** — 森林中可爱又充满好奇心的小鹿，总能在密林深处找到它想要的东西。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

macOS 本地全文搜索客户端，基于 Apple SearchKit + SQLite FTS5 双引擎，像狍子一样灵敏地在你的文件森林中找到一切。

![狍子搜索界面，展示关键词输入和实时搜索结果](README.assets/search-interface.png)

支持查看索引结果：

![索引结果列表，展示匹配文件及高亮片段预览](README.assets/search-results.png)

## 功能特性

- 选择本地文件夹，自动扫描并索引
- SearchKit + FTS5 双引擎融合搜索，支持中英文
- 搜索结果高亮匹配片段（Live Preview）
- 内置多格式预览（PDF / QuickLook / 文本）
- 增量索引，多文件夹管理
- 内置 HTTP 搜索服务（端口 9880）
- 内置 MCP 服务器（端口 9881），供 AI 工具集成
- 附带 Textual 终端客户端（TUI）
- 搜索历史、书签、报告收集

## 支持格式

PDF · Word (docx) · Excel (xlsx) · PowerPoint (pptx) · RTF · HTML · TXT · Markdown · JSON · XML · CSV · EPUB · 代码文件（swift/py/js/ts/java/c/cpp/rs/go 等）

## 技术栈

- **SwiftUI** — macOS 14+ 原生应用
- **Apple SearchKit** — TF-IDF 相关性排序
- **SQLite FTS5** — CJK 全文索引
- **Network.framework** — 轻量 HTTP/TCP 服务器
- **PDFKit + QuickLook** — 文件预览

## 安装与运行

### 前置条件

- macOS 14 (Sonoma) 或更高版本
- Xcode 15+（含 Swift toolchain）

### 构建运行

```bash
# 克隆项目
git clone https://github.com/mcxen/paozier.git
cd paozier

# 构建
swift build

# 运行（自动启动 HTTP:9880 和 MCP:9881 服务）
swift run Paozier
```

无需安装 Java、Solr 或任何外部依赖。

### 基本使用

1. 启动应用后，点击侧边栏 "+" 添加文件夹
2. 等待索引完成
3. 在搜索栏输入关键词即可搜索
4. 点击结果查看预览和高亮片段

### TUI 客户端

项目附带一个基于 Textual 的终端客户端，说明见 [Sources/TUI/README.md](Sources/TUI/README.md)。

```bash
cd Sources/TUI
./run_tui.command
```

首次运行会自动创建本地 `.venv`、安装 `Textual` / `httpx` 依赖，并在必要时尝试拉起主应用。常用快捷键：`Ctrl+F` 搜索、`Ctrl+R` 刷新、`Ctrl+O` 打开文件、`Ctrl+E` 在 Finder 中显示、`j/k` 上下移动、`Ctrl+Q` 退出。

### HTTP API

```bash
# 状态
curl http://localhost:9880/api/status

# 搜索
curl "http://localhost:9880/api/search?q=关键词"

# 网页界面
open http://localhost:9880
```

### MCP Server

通过 JSON-RPC 2.0 协议与 AI 工具集成：

```bash
# 搜索文档
curl -X POST http://localhost:9881 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"全文搜索"}}}'
```

可用工具: `search_documents` · `get_document_content` · `index_folder` · `list_indexed_folders` · `index_status` · `list_files` · `get_file_info` · `remove_folder` · `reindex_all`

## 数据存储

运行时数据位于 `~/Library/Application Support/Paozier/`：

- **`searchkit.index`** — SearchKit 索引
- **`fts.db`** — SQLite FTS5 数据库
- **`folders.json`** — 已索引文件夹
- **`history.json`** — 搜索历史
- **`bookmarks.json`** — 书签
- **`compendium.json`** — 报告

## License

MIT
