# Paozier

macOS 本地 PDF 全文搜索客户端，基于 Apache Solr 引擎。

## 功能

- 选择本地文件夹，自动扫描并索引所有 PDF
- 基于 Solr + Tika 的全文搜索（支持中英文）
- 搜索结果高亮显示匹配片段
- 内置 PDF 预览（PDFKit）
- 增量索引，支持多文件夹管理

## 技术栈

- SwiftUI macOS App (macOS 14+)
- Apache Solr 9.7（嵌入式，内置 Tika PDF 解析）
- HTTP REST API 通信

## 快速开始

```bash
# 1. 下载 Solr
bash scripts/setup-solr.sh

# 2. 构建 App
swift build

# 3. 运行
swift run Paozier
```

## 手动测试 Solr

```bash
# 启动
SOLR_SECURITY_MANAGER_ENABLED=false solr/bin/solr start -p 8983

# 索引 PDF
curl "http://localhost:8983/solr/paozier/update/extract?literal.id=doc1&literal.file_name=test.pdf&commit=true" \
  -F "file=@/path/to/test.pdf"

# 搜索
curl "http://localhost:8983/solr/paozier/select?q=关键词&hl=true&wt=json"

# 停止
solr/bin/solr stop -all
```

## 目录结构

```
paozier/
├── Package.swift
├── Sources/
│   ├── App/           # SwiftUI 入口
│   ├── Views/         # 界面组件
│   ├── Services/      # Solr 通信和管理
│   └── Models/        # 数据模型
├── scripts/           # Solr 配置和脚本
│   ├── setup-solr.sh
│   ├── schema.xml
│   └── solrconfig.xml
└── solr/              # Solr 运行时（setup 后生成）
```
