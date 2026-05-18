Build a Terminal User Interface (TUI) client for the Paozier search app.
Paozier runs an HTTP server at http://localhost:9880 (see API below).
Build the TUI as a Python application using the `textual` library (pip install textual).

## API Reference (Paozier HTTP Server)

GET /api/search?q=<query>
  -> {"results": [{"id","fileName","filePath","snippet","fileSize"}], "total": N, "query": "..."}
GET /api/status
  -> {"ok": true, "documents": N, "folders": ["/path/to/folder", ...]}
GET /api/content?path=<filePath>
  -> raw text content of the file (max 32000 chars, text files only)
GET /api/open?path=<filePath>  (opens in Finder)

## TUI Requirements

1. Main screen: search bar + live result count + scrollable result list
2. Connect to localhost:9880 and search using /api/search
3. Display results: file name, file path, snippet, file size, file type icon
4. Press Enter on a result to show full file content in a detail panel
5. Support file type filtering (PDF, DOC, TXT, MD, CODE, etc.)
6. Show indexed folder count and total documents from /api/status
7. Show a status bar with connection status, documents count, folders count
8. Keyboard shortcuts: Ctrl+F focus search, Ctrl+Q quit, Ctrl+R refresh, j/k navigate
9. Real-time search as you type (debounced 300ms)
10. Color coded file type icons in the terminal

## Implementation

Create a single file: Sources/TUI/paozier_tui.py
It should be runnable with: python paozier_tui.py

Use:
- `textual` library for the TUI framework
- `httpx` (or `aiohttp`) for async HTTP requests to the Paozier server
- Rich-compatible output

Make the UI beautiful with:
- A header showing "Paozier TUI" + connection status dot
- Search input widget at top
- Results list in the middle with file type colors
- Detail/footer panel at bottom showing result count and keyboard hints
- Loading animation while searching
- Empty state message when no results

## File type colors (terminal)
PDF = red, DOC/DOCX = blue, XLS/XLSX = green, MD = purple, TXT = gray, CODE = yellow
