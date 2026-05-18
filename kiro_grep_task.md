# Task: Add GrepSearchEngine to Paozier

## What to build
Add a new grep-based search engine to Paozier that uses the system `grep` command (or pure Swift grep-like implementation via FileManager + String) to search file contents directly. This is a third engine alongside SearchKit and FTS5.

## Requirements

### 1. New file: GrepSearchEngine.swift in Sources/Services/
- Class/actor named `GrepSearchEngine`
- On first call, check if `ripgrep` (`rg`) is available on the system. If yes, use `rg` for speed. If not, fall back to:
  - A pure Swift implementation that opens files and searches line-by-line (for small files < 5MB)
  - For larger files, spawn `/usr/bin/grep -rn -i --max-count=50`
- Support regex mode
- Support case-insensitive search
- Return results as they're found — use an async stream / continuation pattern
- Each result: file path, line number, matching line content, snippet context (±2 lines)
- Batch results into groups of 10 and emit them as they're found
- Respect file type filters (extension whitelist)
- Respect folder path limits

### 2. Search mode toggle
- Add a `SearchMode` enum: `.fused` (current SearchKit+FTS5) and `.grep` (new grep engine)
- In the UI, add a small toggle/segmented control between "索引搜索" and "快速检索"
- When `.grep` mode is selected, performSearch calls GrepSearchEngine instead

### 3. Streaming / batch display
- GrepSearchEngine should return results via an AsyncStream or Combine publisher
- The search results view should update incrementally as batches arrive (not wait for all results)
- Show a live counter: "已找到 N 个结果..." updating in real-time
- Results displayed as they come in, earlier matches shown first

### 4. Integration points
- Wire into ContentView → performSearch() 
- Wire into SearchResultsView to support streaming updates
- Wire into IndexManager → add a grepSearch method
- Wire into MCP server (add a `grep_search` tool)
- Wire into HTTP server (add `/api/grep_search` endpoint)

### 5. File scope
- Grep engine searches ALL files in the indexed folders (not just indexed ones), so it can find things the index hasn't caught up on
- But still respect file type filters
- Skip binary files automatically (check extension + file type)

## Architecture notes
- GrepSearchEngine should be a separate actor, not part of SearchEngine
- Use `AsyncStream<GrepBatchResult>` for streaming
- `GrepBatchResult`: `{ results: [SearchResult], isFinal: Bool }`
- In the View, collect batches with `.onReceive` or a custom async task that appends to the results array
- For rg/grep: use Process() with pipe, parse stdout line by line
- Parse format: `filename:line:content`

## Files to modify
- Sources/Services/ (new: GrepSearchEngine.swift)
- Sources/Services/IndexManager.swift (add grepSearch method)
- Sources/Models/Models.swift (maybe add GrepBatchResult)
- Sources/App/ContentView.swift (add search mode toggle, wire up streaming)
- Sources/Views/SearchResultsView.swift (support streaming updates)
- Sources/Services/MCPServer.swift (add grep_search tool)
- Sources/Services/HTTPServer.swift (add /api/grep_search)
