<div align="center">

<img width="128" height="128" alt="狍子应用图标" src="https://github.com/user-attachments/assets/9ccc3ca1-9768-4a32-a747-16a1ba1d3ccb" />

# 狍子 (Paozier)

> **"狍子"（páo zi）** — 森林中可爱又充满好奇心的小鹿，总能在密林深处找到它想要的东西。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

macOS 本地全文搜索客户端，融合 Apple SearchKit + SQLite FTS5 + Tantivy（Rust）三引擎，像狍子一样灵敏地在你的文件森林中找到一切。

![狍子搜索界面，展示关键词输入和实时搜索结果](README.assets/search-interface.png)

![索引结果列表，展示匹配文件及高亮片段预览](README.assets/search-results.png)

## 功能特性

- 三引擎融合搜索（SearchKit + FTS5 + Tantivy），支持中英文及 CJK 分词
- 即时文件搜索（基于 ripgrep/grep，无需等待索引）
- 搜索结果高亮匹配片段（Live Preview）
- 内置多格式预览（PDF / QuickLook / 文本）
- 全局搜索弹窗（`⌘⇧F`）与快捷搜索面板（`⌘⇧K`），任意应用内呼出
- 高级查询语法：AND / OR / NOT、短语匹配、通配符
- 正则表达式搜索 · 邻近词搜索 · 模糊空格匹配
- 图片 OCR 文字识别（Vision 引擎）
- 增量索引，多文件夹管理
- 内置 HTTP 搜索服务（端口 9880），含网页版搜索界面
- 内置 MCP 服务器（端口 9881），供 AI 工具集成（Cursor / Claude 等）
- 外部 Memos 笔记源搜索集成
- 附带 Textual 终端客户端（TUI）
- 搜索历史、书签、报告收集 · 自定义应用图标

## 支持格式

PDF · Word (docx/doc) · Excel (xlsx/xls) · PowerPoint (pptx/ppt) · RTF · ODT · EPUB · HTML · TXT · Markdown · JSON · XML · CSV/TSV · YAML/TOML · 代码文件（Swift / Python / JS / TS / Java / C / C++ / Rust / Go / Ruby / PHP / Shell 等）

## 技术栈

- **SwiftUI** — macOS 14+ 原生应用
- **Apple SearchKit** — TF-IDF 相关性排序
- **SQLite FTS5** — CJK 全文索引
- **Tantivy**（Rust 侧车）— N-gram 分词，增强中文子串匹配
- **Network.framework** — 轻量 HTTP / TCP 服务器
- **PDFKit + QuickLook + Vision** — 文件预览与图片 OCR

## 安装与运行

### 前置条件

- macOS 14 (Sonoma) 或更高版本
- Xcode 15+（含 Swift toolchain）

### 源码构建运行

```bash
git clone https://github.com/mcxen/paozier.git
cd paozier

# 构建并运行（自动启动 HTTP:9880 和 MCP:9881 服务）
swift run Paozier
```

### 打包 .app

```bash
# 构建通用二进制并打包为 .app（含 Rust Tantivy 侧车）
bash scripts/build_app.sh

# 安装到 /Applications
bash scripts/install.sh
```

无需安装 Java、Solr 或任何外部依赖。Rust 侧车在构建时自动从 `rust/` 源码编译。

### 快速上手

| 操作 | 说明 |
|------|------|
| 添加文件夹 | 侧边栏点击 "+" 添加要索引的文件夹 |
| 搜索 | 搜索栏输入关键词，支持 AND / OR / NOT、通配符 |
| 全局弹出 | 任意应用内按 `⌘⇧F` 呼出 Spotlight 式搜索 |
| 快捷面板 | 按 `⌘⇧K` 打开浮动搜索面板 |
| 预览 | 点击结果查看高亮片段与文件内容 |

### TUI 客户端

基于 Textual 的终端搜索客户端：

```bash
cd Sources/TUI
./run_tui.command
```

首次运行自动创建 `.venv` 并安装依赖。如 HTTP 服务未就绪会自动拉起主应用。

### HTTP API

```bash
# 搜索
curl "http://localhost:9880/api/search?q=关键词"

# 状态
curl http://localhost:9880/api/status

# 网页搜索界面
open http://localhost:9880
```

### MCP Server

通过 JSON-RPC 2.0 协议与 AI 工具集成：

```bash
curl -X POST http://localhost:9881 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"全文搜索"}}}'
```

可用工具：`search_documents` · `get_document_content` · `search_memos` · `grep_search` · `index_folder` · `list_indexed_folders` · `index_status` · `list_files` · `get_file_info` · `remove_folder` · `reindex_all`

## 数据存储

运行时数据位于 `~/Library/Application Support/Paozier/`：

| 文件 | 用途 |
|------|------|
| `searchkit.index` | SearchKit 索引 |
| `fts.db` | SQLite FTS5 数据库 |
| `tantivy/` | Tantivy 索引目录 |
| `text_cache/` | 文本提取缓存 |
| `folders.json` | 已索引文件夹 |
| `history.json` | 搜索历史 |
| `bookmarks.json` | 书签 |
| `compendium.json` | 报告收集 |

## License

MIT