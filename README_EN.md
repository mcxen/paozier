<div align="center">

<img width="128" height="128" alt="Paozier App Icon" src="https://github.com/user-attachments/assets/9ccc3ca1-9768-4a32-a747-16a1ba1dcc3b" />

# Paozier

> **"Paozier"** — from "páo zi" (roe deer), the cute, curious forest deer that always finds what it's looking for in the woods.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

A native macOS full-text search client powered by Apple SearchKit + SQLite FTS5 + Tantivy (Rust) triple engines — sniffing out everything in your file forest like a roe deer.

![Search Interface](README.assets/search-interface.png)

![Search Results](README.assets/search-results.png)

## Features

- Triple-engine fusion search (SearchKit + FTS5 + Tantivy), CJK-aware
- Instant file search (ripgrep/grep, no indexing wait)
- Highlighted search snippets (Live Preview)
- Multi-format preview (PDF / QuickLook / Text)
- Global search popup (`⌘⇧F`) & Quick search panel (`⌘⇧K`), launch from any app
- Advanced query syntax: AND / OR / NOT, phrases, wildcards
- Regex search · Proximity search · Fuzzy space matching
- Image OCR (Vision framework)
- Incremental indexing, multi-folder management
- Built-in HTTP search service (port 9880) with web UI
- Built-in MCP server (port 9881) for AI tool integration (Cursor / Claude / etc.)
- External Memos source search
- Bundled Textual terminal client (TUI)
- Search history, bookmarks, compendium · Custom app icons

## Supported Formats

PDF · Word (docx/doc) · Excel (xlsx/xls) · PowerPoint (pptx/ppt) · RTF · ODT · EPUB · HTML · TXT · Markdown · JSON · XML · CSV/TSV · YAML/TOML · Code files (Swift / Python / JS / TS / Java / C / C++ / Rust / Go / Ruby / PHP / Shell etc.)

## Tech Stack

- **SwiftUI** — macOS 14+ native app
- **Apple SearchKit** — TF-IDF relevance ranking
- **SQLite FTS5** — CJK full-text indexing
- **Tantivy** (Rust sidecar) — N-gram tokenization for CJK substring matching
- **Network.framework** — Lightweight HTTP/TCP server
- **PDFKit + QuickLook + Vision** — File preview & image OCR

## Installation & Usage

### Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+ (with Swift toolchain)

### Build from Source

```bash
git clone https://github.com/mcxen/paozier.git
cd paozier

# Build & run (auto-starts HTTP:9880 and MCP:9881)
swift run Paozier
```

### Package as .app

```bash
# Build universal binary + .app bundle (includes Rust Tantivy sidecar)
bash scripts/build_app.sh

# Install to /Applications
bash scripts/install.sh
```

No Java, Solr, or external dependencies required. The Rust sidecar is auto-built from `rust/` source.

### Quick Start

| Action | Description |
|--------|-------------|
| Add folders | Click "+" in sidebar to add folders for indexing |
| Search | Type keywords in search bar; supports AND/OR/NOT/wildcards |
| Global popup | Press `⌘⇧F` from any app for Spotlight-like search |
| Quick panel | Press `⌘⇧K` for a floating search panel |
| Preview | Click results to view highlighted snippets and file content |

### TUI Client

Textual-based terminal search client:

```bash
cd Sources/TUI
./run_tui.command
```

Creates `.venv` and installs dependencies on first run. Auto-launches the main app if HTTP service is not ready.

### HTTP API

```bash
# Search
curl "http://localhost:9880/api/search?q=keywords"

# Status
curl http://localhost:9880/api/status

# Web search UI
open http://localhost:9880
```

### MCP Server

Integrate with AI tools via JSON-RPC 2.0:

```bash
curl -X POST http://localhost:9881 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"full text search"}}}'
```

Available tools: `search_documents` · `get_document_content` · `search_memos` · `grep_search` · `index_folder` · `list_indexed_folders` · `index_status` · `list_files` · `get_file_info` · `remove_folder` · `reindex_all`

## Data Storage

Runtime data at `~/Library/Application Support/Paozier/`:

| File | Purpose |
|------|---------|
| `searchkit.index` | SearchKit index |
| `fts.db` | SQLite FTS5 database |
| `tantivy/` | Tantivy index directory |
| `text_cache/` | Text extraction cache |
| `folders.json` | Indexed folders |
| `history.json` | Search history |
| `bookmarks.json` | Bookmarks |
| `compendium.json` | Reports |

## License

MIT