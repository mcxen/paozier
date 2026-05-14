# Paozier - macOS 本地 PDF 全文搜索客户端

## 技术方案

### 1. 架构概览

```
┌─────────────────────────────────────────────┐
│           macOS SwiftUI App                  │
│  ┌───────────┬──────────┬────────────────┐  │
│  │ 文件夹选择 │ 搜索栏   │ 结果列表/预览  │  │
│  └───────────┴──────────┴────────────────┘  │
│                    │                         │
│            HTTP REST API                     │
│                    │                         │
│  ┌─────────────────────────────────────┐    │
│  │     嵌入式 Solr 9.x (Java)          │    │
│  │  ┌──────────┐  ┌────────────────┐   │    │
│  │  │ PDF Core │  │ Tika Extractor │   │    │
│  │  └──────────┘  └────────────────┘   │    │
│  └─────────────────────────────────────┘    │
│                    │                         │
│            本地文件系统                       │
└─────────────────────────────────────────────┘
```

### 2. 技术选型

| 层级 | 技术 | 理由 |
|------|------|------|
| 客户端 | SwiftUI + AppKit | 原生 macOS 体验，紧凑现代 |
| 搜索引擎 | Apache Solr 9.7 | 内置 Tika PDF 解析，REST API，开箱即用 |
| PDF 解析 | Solr ExtractingRequestHandler (Tika) | 自动提取 PDF 文本、元数据 |
| 运行时 | 内嵌 JRE (Temurin 21) | 用户无需安装 Java |
| 进程管理 | Swift Process API | 启动/停止 Solr 进程 |
| 通信 | HTTP JSON (localhost:8983) | Solr 原生 REST |

### 3. 核心流程

#### 3.1 索引建立
1. 用户选择本地文件夹
2. 递归扫描 .pdf 文件
3. 对每个 PDF 调用 Solr `/update/extract` (Tika)
4. Solr 自动提取文本、标题、作者、页数等
5. 建立全文索引 + 元数据索引

#### 3.2 全文搜索
1. 用户输入关键词
2. 调用 Solr `/select?q=...&hl=true`
3. 返回匹配文档 + 高亮片段
4. 展示结果列表，点击可预览 PDF

#### 3.3 增量更新
- 使用 FSEvents 监听文件夹变更
- 新增/修改的 PDF 自动重新索引
- 删除的文件从索引中移除

### 4. Solr Schema 设计

```xml
<field name="id" type="string" indexed="true" stored="true" required="true"/>
<field name="file_path" type="string" indexed="true" stored="true"/>
<field name="file_name" type="text_general" indexed="true" stored="true"/>
<field name="content" type="text_cjk" indexed="true" stored="true" termVectors="true"/>
<field name="title" type="text_cjk" indexed="true" stored="true"/>
<field name="author" type="string" indexed="true" stored="true"/>
<field name="pages" type="pint" indexed="true" stored="true"/>
<field name="file_size" type="plong" indexed="true" stored="true"/>
<field name="last_modified" type="pdate" indexed="true" stored="true"/>
<field name="indexed_at" type="pdate" indexed="true" stored="true" default="NOW"/>
```

### 5. 界面设计

紧凑三栏式布局：
- **左侧栏**：文件夹列表 + 索引状态
- **中间**：搜索栏 + 结果列表（文件名、高亮摘要、路径）
- **右侧**：PDF 预览 (PDFKit)

### 6. 目录结构

```
paozier/
├── PaozierApp/              # SwiftUI macOS App
│   ├── App/
│   │   ├── PaozierApp.swift
│   │   └── ContentView.swift
│   ├── Views/
│   │   ├── SearchView.swift
│   │   ├── ResultListView.swift
│   │   ├── PDFPreviewView.swift
│   │   └── SidebarView.swift
│   ├── Services/
│   │   ├── SolrService.swift
│   │   ├── SolrManager.swift
│   │   └── IndexService.swift
│   └── Models/
│       ├── SearchResult.swift
│       └── IndexedFolder.swift
├── solr/                    # 嵌入式 Solr
│   ├── server/
│   ├── bin/
│   └── configsets/
│       └── paozier/
│           └── conf/
│               ├── schema.xml
│               └── solrconfig.xml
├── scripts/
│   ├── setup-solr.sh
│   └── download-jre.sh
└── README.md
```

### 7. 部署方式

App Bundle 内嵌：
- `Paozier.app/Contents/Resources/solr/` — Solr 二进制
- `Paozier.app/Contents/Resources/jre/` — Temurin JRE 21
- 数据目录：`~/Library/Application Support/Paozier/`
