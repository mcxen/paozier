# Paozier - macOS 本地全文搜索客户端

## 技术方案

### 1. 架构概览

```
┌──────────────────────────────────────────────────────┐
│              macOS SwiftUI App (macOS 14+)            │
│  ┌──────────┬───────────────┬─────────────────────┐  │
│  │ 侧边栏   │ 搜索/结果列表  │ Live Preview / PDF  │  │
│  │ (文件夹)  │ (中间栏)      │ (详情栏)            │  │
│  └──────────┴───────────────┴─────────────────────┘  │
│                       │                               │
│              ┌────────┴────────┐                      │
│              │  IndexManager   │                      │
│              └────────┬────────┘                      │
│                       │                               │
│         ┌─────────────┼─────────────┐                │
│         ▼             ▼             ▼                │
│  ┌────────────┐ ┌──────────┐ ┌──────────┐           │
│  │SearchEngine│ │HTTPServer│ │ MCPServer │           │
│  │(双引擎)    │ │ :9880    │ │ :9881    │           │
│  └─────┬──────┘ └──────────┘ └──────────┘           │
│        │                                             │
│   ┌────┴────┐                                        │
│   ▼         ▼                                        │
│ SearchKit  SQLite FTS5                               │
│ (DFSearchKit) (DSFFullTextSearchIndex)               │
│                                                      │
│              本地文件系统                              │
└──────────────────────────────────────────────────────┘
```

### 2. 技术选型

| 层级 | 技术 | 理由 |
|------|------|------|
| 客户端 | SwiftUI (macOS 14+) | 原生 macOS 体验，NavigationSplitView 三栏布局 |
| 搜索引擎 | Apple SearchKit + SQLite FTS5 | 纯本地、无外部依赖、双引擎融合排序 |
| SearchKit 封装 | DFSearchKit 1.5 | Swift 封装 Apple SearchKit API |
| FTS 封装 | DSFFullTextSearchIndex 1.1 | SQLite FTS5 全文索引封装，CJK 友好 |
| 文本提取 | PDFKit + NSAttributedString + unzip | 原生解析 PDF/RTF，ZIP 解压 Office XML |
| 网络服务 | NWListener (Network.framework) | 轻量 HTTP/TCP 服务器，无第三方依赖 |
| 文件预览 | PDFKit + QuickLook + 文本渲染 | 多格式预览 |
| 数据持久化 | JSON 文件 | 文件夹列表、历史、书签、报告 |

### 3. 支持的文件格式

| 类别 | 扩展名 |
|------|--------|
| 文档 | pdf, docx, doc, rtf, odt, epub |
| 表格 | xlsx, xls, csv, tsv, ods |
| 演示 | pptx, ppt, odp |
| 网页 | html, htm, xml |
| 文本 | txt, md, markdown, log, json, yaml, yml, toml, ini, conf |
| 代码 | swift, py, js, ts, java, c, h, cpp, rs, go, rb, php, sh |

### 4. 核心流程

#### 4.1 索引建立
1. 用户通过 NSOpenPanel 选择本地文件夹
2. 递归扫描所有支持格式的文件
3. 对每个文件调用 `SearchEngine.indexFile(at:)` 提取文本
4. 同时写入 SearchKit 索引和 SQLite FTS5 索引
5. 文件夹信息持久化到 `folders.json`

#### 4.2 全文搜索（双引擎融合）
1. 用户输入关键词
2. SearchKit 返回结果（权重 0.6）— 擅长英文 TF-IDF 排序
3. SQLite FTS5 返回结果（权重 0.4）— 擅长 CJK 分词
4. 合并去重，按融合分数排序
5. 提取匹配片段（snippet）展示

#### 4.3 文本提取策略
- **PDF**: PDFKit 逐页提取
- **DOCX/PPTX**: unzip 解压 → XML 解析文本节点
- **XLSX**: unzip → 解析 sharedStrings + worksheet cells
- **RTF**: NSAttributedString 解析
- **HTML/XML**: 正则去标签
- **其他**: 多编码尝试直接读取

### 5. 服务层

#### 5.1 HTTP Server (端口 9880)
- `GET /` — 内置搜索网页（完整 HTML/CSS/JS）
- `GET /api/search?q=` — JSON 搜索 API
- `GET /api/status` — 索引状态

#### 5.2 MCP Server (端口 9881)
JSON-RPC 2.0 协议，供 AI 工具集成：
- `search_documents` — 全文搜索
- `get_document_content` — 读取文件内容
- `index_folder` — 索引文件夹
- `list_indexed_folders` — 列出已索引文件夹
- `index_status` — 索引状态
- `list_files` — 列出目录文件
- `get_file_info` — 文件元数据
- `remove_folder` — 移除文件夹
- `reindex_all` — 重建索引

### 6. 界面设计

NavigationSplitView 三栏布局：
- **左侧栏**：引擎状态、文件夹列表、索引进度、HTTP/MCP 服务开关、支持格式
- **中间栏**：搜索栏 + 结果列表（文件图标、标题、摘要、文件类型标签）
- **右侧栏**：
  - Live Preview（高亮搜索词、可复制文本）
  - PDF/文件原始预览（PDFKit / QuickLook / 文本）
  - 文件夹内容浏览

附加功能：
- **报告（Compendium）**：收集搜索摘录，导出 Markdown
- **搜索历史**：最近 100 条搜索记录
- **书签**：保存常用搜索

### 7. 目录结构

```
paozier/
├── Package.swift           # SPM 配置，依赖 DFSearchKit + DSFFullTextSearchIndex
├── Sources/
│   ├── App/
│   │   ├── PaozierApp.swift      # @main 入口
│   │   └── ContentView.swift     # 主界面（三栏布局 + 搜索逻辑）
│   ├── Views/
│   │   ├── SidebarView.swift     # 侧边栏（状态/文件夹/服务）
│   │   ├── SearchResultsView.swift # 搜索结果列表 + ResultRow
│   │   ├── PDFPreviewView.swift  # 多格式预览（PDF/文本/QuickLook）
│   │   ├── LivePreviewView.swift # 高亮搜索词的文本预览
│   │   ├── FolderContentView.swift # 文件夹内容浏览
│   │   ├── HistoryView.swift     # 搜索历史 + 书签
│   │   ├── CompendiumView.swift  # 报告管理
│   │   └── ProximitySearchView.swift # 邻近搜索 UI
│   ├── Services/
│   │   ├── SearchEngine.swift    # 双引擎搜索 + 文本提取（actor）
│   │   ├── IndexManager.swift    # 索引管理 + 文件夹管理
│   │   ├── DataManager.swift     # 报告/历史/书签持久化
│   │   ├── HTTPServer.swift      # HTTP 搜索服务
│   │   └── MCPServer.swift       # MCP AI 工具服务
│   └── Models/
│       └── Models.swift          # 数据模型定义
├── scripts/                # （预留）
├── .github/
│   └── workflows/
│       └── release-dmg.yml # CI: 构建 universal binary → App Bundle → DMG
└── README.md
```

### 8. 数据存储

所有运行时数据存储在 `~/Library/Application Support/Paozier/`：
- `searchkit.index` — SearchKit 索引文件
- `fts.db` — SQLite FTS5 数据库
- `folders.json` — 已索引文件夹列表
- `compendium.json` — 报告数据
- `history.json` — 搜索历史
- `bookmarks.json` — 搜索书签

### 9. CI/CD

GitHub Actions 自动发布：
- 触发：推送 `v*` tag 或手动输入版本号
- 构建：`swift build -c release --arch arm64 --arch x86_64`（Universal Binary）
- 打包：生成 `.app` Bundle + `.dmg` 安装镜像
- 发布：创建 GitHub Release 并上传 DMG
