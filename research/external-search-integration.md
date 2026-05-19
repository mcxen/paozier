# Paozier 外部文档搜索接口集成调研报告

> 生成时间：2026-05-19
> 调研范围：Memos、Notion、Obsidian 及其他外部笔记/文档源的集成可行性

---

## 1. 执行摘要

Paozier 当前是本地文档搜索引擎（SearchKit + FTS5），已提供 HTTP API 和 MCP Server 两种接入方式。接入外部文档搜索源的核心思路是：**Paozier 作为统一搜索中转层，将外部源的结果与本地结果融合后返回**。

推荐优先实施 **Memos 集成**，因为：
- Memos 是自托管的 Markdown 笔记系统，API 简洁，认证简单（Bearer Token）
- 存在成熟的 MCP Server 实现（memos-api-mcp，npm 可安装）
- Memos 笔记本身是 Markdown，与 Paozier 已有的 Markdown 处理能力完全兼容

---

## 2. Paozier 当前搜索架构分析

### 2.1 引擎层
- **SearchKit** (DFSearchKit): 苹果原生搜索框架，支持相关性排序、高亮、拼写检查
- **SQLite FTS5** (DSFFullTextSearchIndex): 全文索引，突出 CJK 文本搜索
- 双引擎融合搜索：分别打分后按权重加和（默认 SK 0.6 / FTS 0.4）

### 2.2 网络服务层
- **HTTP Server** (localhost:9880):
  - `GET /api/search?q=...` 本地搜索
  - `GET /api/grep_search?q=...` Grep 快速搜索
  - `GET /api/status` 索引状态
  - `GET /api/open?path=...` 打开文件
  - `GET /api/reveal?path=...` Finder 定位
  - `GET /api/content?path=...` 获取文件内容
  - `/` 内置 Web 搜索界面

- **MCP Server** (localhost:9881):
  - `search_documents` 全文搜索（可配置片段/全文返回）
  - `grep_search` 快速 Grep 搜索
  - `get_document_content` 读取文件内容
  - `index_folder` / `list_indexed_folders` / `reindex_all` 索引管理
  - `list_files` / `get_file_info` 文件系统探查
  - `remove_folder` 移除索引
  - `index_status` 状态查询

### 2.3 文件处理能力
- 支持格式：PDF、Markdown、DOCX、PPTX、XLSX、RTF、HTML/XML、普通文本、图片 OCR
- 文本提取缓存：`extracted-text-cache` 目录持久化
- 编码检测和 Unicode 标准化（破折号、引号等）

---

## 3. 外部文档源评估

### 3.1 Memos (推荐，高优先级)

**Memos** 是一款自托管的轻量级笔记应用，以 Markdown 为核心，支持标签、可见性控制、多用户。

#### API 概况
- 基础路径: `https://<instance>/api/v1`
- 认证: `Authorization: Bearer <token>`
- 分页: `pageSize` + `pageToken`
- 过滤: Google AIP-160 标准
- 列出笔记: `GET /api/v1/memos`
- 搜索笔记: `GET /api/v1/memos?filter=content.contains("关键词")` (具体语法需根据版本确认)

#### MCP Server 现成方案
1. **Red5d/memos_mcp** (GitHub)
   - 提供 Memos 的搜索、创建、更新等 MCP 工具
   - 适合作为独立 MCP 服务器运行

2. **MemTensor/memos-api-mcp** (GitHub / npm)
   - npm 包名: `memos-api-mcp`
   - 版本: 1.1.0
   - 环境变量: `MEMOS_API_KEY`
   - CLI 启动: `npx memos-api-mcp`
   - 工具列表: `mcp_memos_search_memos`, `mcp_memos_list_memos` 等
   - 适合直接集成到 Hermes MCP 配置

#### 集成复杂度
| 项目 | 评估 |
|---|---|
| 认证 | 低 — 单一 Bearer Token |
| API 稳定性 | 中 — 自托管版本可能不同 |
| 数据格式 | 低 — 纯 Markdown，无需转换 |
| 搜索能力 | 中 — 支持内容搜索，但可能无高亮/片段 |
| 缓存需求 | 中 — 建议本地缓存笔记内容 |

### 3.2 Notion (中等优先级)

**Notion** 是协作式知识库，支持页面、数据库、嵌套块级内容。

#### API / MCP 概况
- 官方提供远程 MCP Server: `https://mcp.notion.com/mcp`
- 社区实现: `suekou/mcp-notion-server` (891 stars, TypeScript)
- 认证: `NOTION_API_TOKEN` (Integration Token)
- 工具: 搜索页面、查询数据库、创建/更新页面、评论管理

#### 集成复杂度
| 项目 | 评估 |
|---|---|
| 认证 | 中 — OAuth / Integration Token |
| API 限速 | 中 — Notion API 有 rate limit (3 req/s) |
| 数据格式 | 高 — 块级数据需转换为平文本 |
| 搜索能力 | 中 — 支持搜索 API，但结果为页面 ID 需二次 fetch |
| 缓存需求 | 高 — 块级内容建议全量缓存 |

### 3.3 Obsidian (已支持，无需集成)

**Obsidian** 是本地 Markdown 笔记应用，笔记以文件形式存储。

Paozier **已经支持** 通过 `index_folder` 工具直接索引 Obsidian vault 文件夹。只需在设置中添加 vault 路径，即可搜索其中的所有 Markdown 文件。

### 3.4 其他外部源（低优先级 / 未来考虑）

| 服务 | 状态 | 集成方式 |
|---|---|---|
| Readwise | 需 API Key | REST API |
| Pocket | 需 API Key | REST API (pocket API 已部分弃用) |
| GitHub Issues | 有 MCP Server | `@modelcontextprotocol/server-github` |
| Confluence | 需 API Key | REST API |
| 腾讯文档 / 石墨 | 无公开 MCP | 只能通过下载/导出索引 |

---

## 4. 集成方案设计

### 4.1 总体架构思路

```
+---------------------------------------------------+
|                   Paozier App                       |
|  +----------------+  +---------------------------+  |
|  | Local Search   |  | External Search Manager   |  |
|  | (SearchKit+FTS5)|  |                           |  |
|  +----------------+  |  +---------------------+    |  |
|           |          |  | ExternalSearchProvider|  |  |
|           v          |  |   Protocol          |  |  |
|     SearchResult     |  +----------+------------+  |  |
|                      |             |               |  |
|  +----------------+  |    +--------+--------+      |  |
|  | MCPServer      |  |    | MemosProvider  |      |  |
|  | HTTPServer     |  |    | NotionProvider |      |  |
|  +----------------+  |    +----------------+      |  |
|                      +---------------------------+  |
+---------------------------------------------------+
```

核心原则：
1. **协议抽象**：定义 `ExternalSearchProvider` 协议，统一外部源的搜索行为
2. **结果融合**：本地结果与外部结果按来源分组展示，不强行打分合并（因为不同源的相关性计分无法直接比较）
3. **缓存机制**：外部结果建议缓存，避免频繁 API 调用
4. **配置化**：用户可在 SettingsView 中开关/配置外部源

### 4.2 方案对比

| 方案 | 描述 | 优点 | 缺点 | 适合场景 |
|---|---|---|---|---|
| A. Paozier 调用外部 MCP | Paozier 作为 MCP client，运行 memos-api-mcp 并通过 stdin/stdout 调用 | 无需重复实现 API 客户端，利用现成 MCP 工具 | 需运行额外进程，进程管理复杂 | 外部源已有成熟 MCP server |
| B. Paozier 内置 HTTP 客户端 | 在 Paozier 中直接实现 Memos/Notion 的 REST API 调用 | 控制权完全在自己手中，无额外进稏 | 需为每个源写 HTTP 客户端 | 外部源 API 简单/稳定 |
| C. 本地同步索引 | 定期将外部笔记同步到本地文件系统，再索引 | 搜索速度最快，无网络依赖 | 数据可能过期，同步逻辑复杂 | 外部源内容变化不频繁 |

### 4.3 推荐方案

**以方案 B 为主，方案 A 为辅助**。

具体路线：
1. **首先在 Paozier 内部实现 HTTP API 客户端**（方案 B），因为：
   - Memos API 非常简洁（REST + Bearer Token），实现成本低
   - 不需要运行额外进程，减少系统资源占用
   - 结果格式可完全控制，与 SearchResult 高度兼容
   - 无需处理 MCP 进程生命周期

2. **后期可以支持方案 A**（运行外部 MCP Server），作为插件机制：
   - 对于 Notion 等已有成熟官方/社区 MCP Server 的源，可以通过 Hermes 的 `native-mcp` 客户端直接连接
   - 这时 Paozier 不需自己实现 HTTP 客户端，只需做一层结果映射

---

## 5. 技术实现建议

### 5.1 新增协议

在 `Sources/Services/` 下新增 `ExternalSearchProvider.swift`：

```swift
/// 外部搜索源协议
protocol ExternalSearchProvider: AnyObject {
    var name: String { get }
    var isEnabled: Bool { get set }
    var isConfigured: Bool { get }
    
    /// 在外部源中搜索
    func search(query: String, limit: Int) async throws -> [ExternalSearchResult]
    
    /// 获取笔记/文档全文
    func getContent(identifier: String) async throws -> String
}

struct ExternalSearchResult {
    let id: String                // 外部源唯一 ID
    let title: String
    let snippet: String
    let content: String?          // 可选全文（缓存/预加载）
    let source: String            // "memos", "notion", 等
    let url: URL?                 // 外部链接
    let date: Date?               // 创建/修改时间
}
```

### 5.2 MemosProvider 实现设计

```swift
actor MemosProvider: ExternalSearchProvider {
    let name = "Memos"
    var isEnabled = false
    
    private var baseURL: URL
    private var apiToken: String
    private var cache: [String: ExternalSearchResult] = [:]
    
    var isConfigured: Bool {
        !apiToken.isEmpty && !baseURL.absoluteString.isEmpty
    }
    
    func search(query: String, limit: Int) async throws -> [ExternalSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/memos"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: String(limit)),
            URLQueryItem(name: "filter", value: "content.contains(\"\(query)\")")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        // 解析 JSON，映射为 ExternalSearchResult
        // Memos 笔记是 Markdown，snippet 可直接取前 N 个字符
    }
    
    func getContent(identifier: String) async throws -> String {
        // 如果缓存中有直接返回，否则调用 GET /api/v1/memos/{id}
    }
}
```

### 5.3 MCPServer 新增工具

在 `MCPServer.swift` 的 `toolsJSON` 中新增：

```json
{
  "name": "search_external_notes",
  "description": "Search notes from configured external sources (Memos, Notion, etc.). Results include source label and external URL.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Search keywords" },
      "source": { "type": "string", "description": "Filter by source name: memos, notion, or all (default)" },
      "limit": { "type": "integer", "description": "Max results per source (default 10)" }
    },
    "required": ["query"]
  }
}
```

### 5.4 HTTPServer 扩展

新增 API 端点：
- `GET /api/external_search?q=...&source=...&limit=...` — 统一外部搜索接口
- `GET /api/external_content?source=memos&id=...` — 获取外部笔记全文

Web UI 搜索页面增加 "外部笔记" Tab 或过滤器，与本地结果分区展示。

### 5.5 SettingsView 配置

新增 "外部源" 配置面板：

```
外部文档源
┌─────────────────────────────────────────┐
│  [+] 添加外部源                          │
│  Memos                                   [开关] │
│    地址: https://memos.example.com          │
│    Token: ***********                        │
│    [测试连接]                               │
│  Notion                                  [开关] │
│    Token: secret_xxxxxxxxxx                  │
│    [测试连接]                               │
└─────────────────────────────────────────┘
```

---

## 6. Memos 集成详细设计

### 6.1 认证流程

1. 用户在 Memos Web UI 中生成 Access Token
2. 在 Paozier SettingsView 中填写：
   - **实例地址**: `https://memos.example.com` (自托管地址)
   - **Access Token**: `从 Memos 设置中复制的 Token`
3. Paozier 发送 `GET /api/v1/user/me` 验证 Token 有效性
4. 验证成功后保存到 Keychain，开启 Memos 搜索

### 6.2 搜索接口

Memos API 搜索笔记（基于文档猜测，需实际 API 调试确认）：

```
GET /api/v1/memos?pageSize=20&filter=content.contains("搜索词")

Headers:
  Authorization: Bearer <token>
  Accept: application/json
```

响应示例（猜测）：
```json
{
  "memos": [
    {
      "id": 123,
      "content": "# 标题\n\n正文内容...",
      "tags": ["tag1", "tag2"],
      "visibility": "PUBLIC",
      "createTime": "2026-05-01T10:00:00Z",
      "updateTime": "2026-05-10T15:00:00Z"
    }
  ],
  "nextPageToken": "..."
}
```

### 6.3 结果映射

Memos 笔记 → Paozier SearchResult/外部结果：

| Memos 字段 | Paozier 字段 | 处理逻辑 |
|---|---|---|
| id | id | `memos-\(id)` |
| content | snippet | 前 200 个字符 + 高亮匹配词 |
| content | content | 完整 Markdown（可缓存） |
| tags | 标签 | 作为元数据附加 |
| createTime/updateTime | date | 显示在结果中 |
| visibility | 来源标识 | `来源: Memos` |
| - | url | `https://memos.example.com/m/123` (可能的浏览链接) |

### 6.4 缓存策略

建议采用两级缓存：
1. **结果缓存** (5 min TTL): 同一搜索词短时间内不重复请求
2. **笔记内容缓存** (60 min TTL): 已打开的笔记全文缓存，避免重复 fetch
3. **本地持久缓存** (SQLite): 可选功能，将经常访问的笔记持久化到本地 SQLite，支持离线搜索

### 6.5 开发梳理

建议从以下步骤开始实施：
1. 定义 `ExternalSearchProvider` 协议
2. 实现 `MemosProvider` HTTP 客户端
3. 修改 `MCPServer` 添加 `search_external_notes` 工具
4. 修改 `HTTPServer` 添加 `/api/external_search` 接口
5. 修改 Web UI 搜索页面，支持外部源分区展示
6. 修改 `SettingsView`，添加外部源配置
7. 添加实时搜索融合（可选：在本地结果和外部结果之间做简单的分区或分组展示）

---

## 7. 其他外部源扩展方向

### 7.1 Notion 集成
Notion 已有官方 MCP Server (`https://mcp.notion.com/mcp`)，通过 Hermes 的 `native-mcp` 客户端或直接运行 `npx @suekou/mcp-notion-server` 可连接。

Notion 数据结构复杂（block-level），需要：
- 将 block 树平展为 Markdown-like 文本
- 处理数据库查询结果
- 管理 OAuth 认证流程

### 7.2 GitHub 集成
`@modelcontextprotocol/server-github` 已是成熟的 MCP Server，支持 Issues/PRs 搜索。可通过方案 A 接入：运行 GitHub MCP Server，由 Hermes/Kiro 调用，Paozier 做结果聚合层。

### 7.3 Obsidian 已支持
无需额外开发。在 SettingsView 中添加一个快捷入口 "添加 Obsidian Vault" 即可。

---

## 8. 实施优先级与路线图

| 阶段 | 内容 | 估计工作量 | 优先级 |
|---|---|---|---|
| P0 | 定义 ExternalSearchProvider 协议 + MemosProvider 实现 | 2-3 天 | 高 |
| P0 | MCPServer 新增 search_external_notes 工具 | 1 天 | 高 |
| P1 | HTTPServer 新增 /api/external_search + /api/external_content | 1 天 | 中 |
| P1 | SettingsView 外部源配置面板 | 1 天 | 中 |
| P2 | Web UI 外部结果分区展示 | 1-2 天 | 中 |
| P2 | 缓存机制 + 持久化 | 1 天 | 低 |
| P3 | NotionProvider 实现 | 2-3 天 | 低 |
| P3 | GitHub MCP Server 聚合 | 1 天 | 低 |

---

## 9. 风险与应对

| 风险 | 影响 | 应对措施 |
|---|---|---|
| Memos API 变化 | 搜索失败 | 在 Provider 中做版本适配，增加 API 响应校验 |
| 网络不可用 | 外部搜索为空 | 搜索结果显示 "外部源暂时不可用"，本地搜索不受影响 |
| Token 失效 | 401 Unauthorized | 设置面板提示重新配置 |
| 外部源数据量大 | 搜索慢 | 实施分页和缓存机制，限制单次请求结果数 |
| 认证信息泄露 | 安全风险 | Token 存储在 macOS Keychain，不存储在 plist |

---

## 10. 参考资料

1. Memos API 文档: https://usememos.com/docs/api/latest
2. memos-api-mcp (npm): https://github.com/MemTensor/memos-api-mcp
3. memos_mcp (GitHub): https://github.com/Red5d/memos_mcp
4. Notion MCP Server: https://github.com/suekou/mcp-notion-server
5. Notion MCP 官方文档: https://developers.notion.com/guides/mcp/overview
6. MCP 协议规范: https://modelcontextprotocol.io

---

*Report generated by kiro + Hermes research pipeline*
*Status: 待 kiro 审阅和技术细节补充*
