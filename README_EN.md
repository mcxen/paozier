# Paozier

> **"Paozier"** comes from "páo zi" (roe deer) — the cute, curious forest deer that always finds what it's looking for in the woods.

---

A native macOS full-text search client powered by Apple SearchKit + SQLite FTS5 dual engines — sniffing out everything in your file forest like a roe deer.

Search Interface

![Search Interface](README.assets/search-interface.png)

Search results with indexed content preview:

![Search Results](README.assets/search-results.png)

## Features

- Select local folders, auto-scan and index
- Dual-engine search with SearchKit + FTS5, CJK support
- Highlighted search snippets (Live Preview)
- Built-in multi-format preview (PDF / QuickLook / Text)
- Incremental indexing, multi-folder management
- Built-in HTTP search service (port 9880)
- Built-in MCP server (port 9881) for AI tool integration
- Bundled Textual terminal client (TUI)
- Search history, bookmarks, reports

## Supported Formats

PDF · Word (docx) · Excel (xlsx) · PowerPoint (pptx) · RTF · HTML · TXT · Markdown · JSON · XML · CSV · EPUB · Code files (swift/py/js/ts/java/c/cpp/rs/go etc.)

## Tech Stack

| Component | Description |
|---|---|
| SwiftUI | macOS 14+ native app |
| Apple SearchKit | TF-IDF relevance ranking |
| SQLite FTS5 | CJK full-text indexing |
| Network.framework | Lightweight HTTP/TCP server |
| PDFKit + QuickLook | File preview |

## Installation & Usage

### Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+ (with Swift toolchain)

### Build & Run

```bash
# Clone
git clone https://github.com/user/paozier.git
cd paozier

# Build
swift build

# Run (auto-starts HTTP:9880 and MCP:9881 services)
swift run Paozier
```

No Java, Solr, or external dependencies required.

### Basic Usage

1. Launch the app, click "+" in sidebar to add folders
2. Wait for indexing to complete
3. Type keywords in the search bar to search
4. Click results to preview with highlighted snippets

### TUI Client

The repo also includes a Textual-based terminal client. Details live in [Sources/TUI/README.md](/Users/mcx/Documents/OpenSpring/paozier/Sources/TUI/README.md).

```bash
cd Sources/TUI
./run_tui.command
```

On first launch it creates a local `.venv`, installs `Textual` / `httpx`, and tries to open the main app if the HTTP service is not ready. Common shortcuts: `Ctrl+F` search, `Ctrl+R` refresh, `Ctrl+O` open file, `Ctrl+E` reveal in Finder, `j/k` move, `Ctrl+Q` quit.

### HTTP API

```bash
# Status
curl http://localhost:9880/api/status

# Search
curl "http://localhost:9880/api/search?q=keywords"

# Web UI
open http://localhost:9880
```

### MCP Server

Integrate with AI tools via JSON-RPC 2.0:

```bash
# Search documents
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_documents","arguments":{"query":"full text search"}}}' | nc localhost 9881
```

Available tools: `search_documents` · `get_document_content` · `index_folder` · `list_indexed_folders` · `index_status` · `list_files` · `get_file_info` · `remove_folder` · `reindex_all`

## Data Storage

Runtime data at `~/Library/Application Support/Paozier/`:

| File | Purpose |
|---|---|
| `searchkit.index` | SearchKit index |
| `fts.db` | SQLite FTS5 database |
| `folders.json` | Indexed folders |
| `history.json` | Search history |
| `bookmarks.json` | Bookmarks |
| `compendium.json` | Reports |

## License

MIT
