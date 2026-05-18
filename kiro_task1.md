Create a new file Sources/Services/GrepSearchEngine.swift in the Paozier project.

This is a grep-based search engine for the app. Requirements:

1. Actor class named GrepSearchEngine
2. On init, check if `rg` (ripgrep) is available via `which rg`. If available, use it. If not, use `/usr/bin/grep`.
3. A method `search(query: String, folderPaths: [String], allowedExtensions: Set<String>?, isRegex: Bool) -> AsyncStream<[SearchResult]>`
4. For each folder, run grep recursively:
   - `rg -rni --max-count=50 {query}` if ripgrep available
   - `grep -rni --max-count=50 {query}` if not
   - Regex mode: omit fixed-strings flag
   - Skip binary extensions (.pdf, .docx, .pptx, .xlsx, .jpg, .png, .gif, etc.)
5. Parse grep output format: `filepath:line:content`
6. Yield results in batches of 10 via AsyncStream continuation
7. Each SearchResult should have:
   - id: "grep:{filePath}:{lineNumber}"
   - filePath, fileName (lastPathComponent), title (fileName)
   - snippet: "行{lineNumber}: {content}" with context
   - content: the matched text
8. Respect allowedExtensions filter (skip files not matching)
9. Respect folderPaths filter (only search within given folders)

Write only this single file. Use Foundation, no third-party dependencies.
Import the project's Models for SearchResult.
