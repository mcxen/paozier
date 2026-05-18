# Advanced Paozier TUI - Upgrade Specification

Upgrade Sources/TUI/paozier_tui.py with these advanced features:

## 1. Left-Right Split Pane Layout (Horizontal Split)
- Left pane: Search results list (width: 2fr, or 40%)
- Right pane: File detail/preview viewer (width: 3fr, or 60%)
- Use `Horizontal` container with CSS: `#left-pane { width: 2fr; } #right-pane { width: 3fr; }`
- Right pane automatically shows preview when a result is selected
- Both panes should be scrollable independently
- Right pane has a header showing file name + file type badge + size

## 2. Search Term Highlighting
- In search results snippet: highlight the matched query terms using `[bold yellow]...[/]` Rich markup
- In the preview pane: highlight all occurrences of search terms in the file content
- Use `textual.text_highlight` or Rich's `Text` with `highlight_regex` or manual string replacement with `[bold yellow on $surface]term[/]`
- Support multiple search terms (split by space)
- Case-insensitive highlighting

## 3. Advanced Result Display
- Show file path in dim text, snippet with highlighted terms
- File type badge with color (PDF=red, DOC/DOCX=blue, etc.)
- File size formatted nicely (KB/MB)
- Line number for grep-style results if available
- Keyboard: j/k or Up/Down to navigate results, Enter to open preview in right pane

## 4. Enhanced Preview Pane
- Show full file content (first 8000 chars)
- Highlight ALL occurrences of the current search term throughout the content
- File type icon + name at top
- File path in dim text below title
- Scrollable content area

## 5. Keyboard Shortcuts
- Ctrl+F: Focus search input
- Ctrl+Q: Quit  
- Ctrl+R: Refresh
- j/k: Navigate results up/down (vim-style)
- Enter: Open preview in right pane
- Tab: Focus toggle between search input and results list
- Escape: Clear search or close preview

## 6. Visual Polish
- Colored file type badges using Rich markup
- Status bar showing: connection status (green/red dot), docs count, folders count
- Results counter showing "N results" updating live
- Loading spinner during search
- Empty state with helpful message
- Disconnected state with auto-reconnect

## Implementation Notes
- Use Textual framework's CSS for all layout and styling
- Use `Rich` markup `[color]text[/]` for all colored text
- For highlight in preview: split content around matches, interleave match spans with `[bold yellow]...[yellow]/]` markers
- Keep the HTTP API integration the same (localhost:9880)
- Single file: Sources/TUI/paozier_tui.py
