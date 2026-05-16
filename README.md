# 狍子 (Paozier)

> **"狍子"（páo zi）** — 森林中可爱又充满好奇心的小鹿，总能在密林深处找到它想要的东西。

---

macOS 本地全文搜索客户端，基于 Apple SearchKit + SQLite FTS5 双引擎，像狍子一样灵敏地在你的文件森林中找到一切。

搜索界面

![搜索界面](README.assets/search-interface.png)

支持查看索引结果：

![索引结果](README.assets/search-results.png)

## 功能特性

- 选择本地文件夹，自动扫描并索引
- SearchKit + FTS5 双引擎融合搜索，支持中英文
- 搜索结果高亮匹配片段（Live Preview）
- 内置多格式预览（PDF / QuickLook / 文本）
- 增量索引，多文件夹管理
- 内置 HTTP 搜索服务（端口 9880）
- 内置 MCP 服务器（端口 9881），供 AI 工具集成
- 搜索历史、书签、报告收集

## 支持格式

PDF · Word (docx) · Excel (xlsx) · PowerPoint (pptx) · RTF · HTML · TXT · Markdown · JSON · XML · CSV · EPUB · 代码文件（swift/py/js/ts/java/c/cpp/rs/go 等）

## 技术栈

| 组件 | 说明 |
|---|---|
| SwiftUI | macOS 14+ 原生应用 |
| Apple SearchKit | TF-IDF 相关性排序 |
| SQLite FTS5 | CJK 全文索引 |
| Network.framework | 轻量 HTTP/TCP 服务器 |
| PDFKit + QuickLook | 文件预览 |

## 安装与运行

### 前置条件

- macOS 14 (Sonoma) 或更高版本
- Xcode 15+（含 Swift toolchain）

### 构建运行

```bash
# 克隆项目
git clone https://github.com/user/paozier.git
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
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"全文搜索"}}}' | nc localhost 9881
```

可用工具: `search_documents` · `get_document_content` · `index_folder` · `list_indexed_folders` · `index_status` · `list_files` · `get_file_info` · `remove_folder` · `reindex_all`

## 数据存储

运行时数据位于 `~/Library/Application Support/Paozier/`:

| 文件 | 用途 |
|---|---|
| `searchkit.index` | SearchKit 索引 |
| `fts.db` | SQLite FTS5 数据库 |
| `folders.json` | 已索引文件夹 |
| `history.json` | 搜索历史 |
| `bookmarks.json` | 书签 |
| `compendium.json` | 报告 |

## License

MIT
