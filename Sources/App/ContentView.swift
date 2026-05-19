import SwiftUI

struct ContentView: View {
    @EnvironmentObject var indexManager: IndexManager
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var dataManager = DataManager.shared
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false
    @State private var selectedFileTypes: Set<FileTypeFilter> = []
    @State private var selectedSearchFolderPath: String?
    @State private var usesRegex = false
    @State private var fuzzySpaces = true
    @State private var includeMemos = true
    @State private var showSearchOptions = false
    @State private var previewMode: PreviewMode = .live
    @State private var showCompendium = false
    @State private var showHistory = false
    @State private var activePane: MainPane = .search
    @State private var primaryMatchStep = 0
    @State private var previewFindText = ""
    @State private var previewFindStep = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var documentMatchesCollapsed = false
    @State private var documentMatchesHeight: CGFloat = 190
    @State private var documentMatchJumpCycle = 0
    @FocusState private var searchFieldFocused: Bool
    @FocusState private var previewFindFocused: Bool

    enum PreviewMode { case live, pdf }
    enum MainPane { case search, index }

    private var searchTerms: [String] {
        currentSearchOptions.highlightTerms
    }

    private var currentSearchOptions: SearchOptions {
        SearchOptions(
            query: searchText,
            selectedFileTypes: selectedFileTypes,
            folderPaths: selectedSearchFolderPath.map { Set([$0]) } ?? [],
            usesRegex: usesRegex,
            fuzzySpaces: fuzzySpaces
        )
    }

    private var hasEnabledMemosSources: Bool {
        settings.memosSources.contains { source in
            source.isEnabled &&
            !source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !source.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(activePane: $activePane)
        } content: {
            if activePane == .search {
                contentPane
            } else {
                IndexManagementView()
            }
        } detail: {
            detailPane
                .id(selectedResult?.id ?? indexManager.selectedFolder?.id ?? "empty")
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: selectedResult?.id)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showCompendium) { CompendiumView().environmentObject(dataManager) }
        .sheet(isPresented: $showHistory) { HistoryView(onSelect: { q in searchText = q; showHistory = false; performSearch() }).environmentObject(dataManager) }
        .background {
            Button("") { GlobalSearchPopupController.shared.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .hidden()
            Button("") { previewFindFocused = true }
                .keyboardShortcut("f", modifiers: [.command])
                .hidden()
        }
        .task { await indexManager.startup() }
        .onAppear { searchFieldFocused = true }
        .onChange(of: showHistory) { _, newValue in
            if !newValue { searchFieldFocused = true }
        }
        .onChange(of: showCompendium) { _, newValue in
            if !newValue { searchFieldFocused = true }
        }
        .onChange(of: indexManager.selectedFolder?.id) { _, _ in
            selectedResult = nil
        }
        .onChange(of: selectedResult) { _, newValue in
            guard let newValue else { return }
            primaryMatchStep = initialMatchIndex(for: newValue)
            previewFindStep = 0
            documentMatchJumpCycle = 0
        }
        .onChange(of: indexManager.indexedFolders.map(\.path)) { _, paths in
            if let selectedSearchFolderPath, !paths.contains(selectedSearchFolderPath) {
                self.selectedSearchFolderPath = nil
                rerunSearchIfNeeded()
            }
        }
    }

    // MARK: - Content Pane (Search + Results)

    private var contentPane: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField(L("搜索文档内容..."), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($searchFieldFocused)
                    .onSubmit(performSearch)
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { showSearchOptions.toggle() }
                } label: {
                    Image(systemName: showSearchOptions ? "slider.horizontal.3" : "slider.horizontal.below.rectangle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSearchOptions || hasActiveSearchOptions ? Color.accentColor : .secondary)
                .focusable(false)
                .help(L("搜索条件"))
                if isSearching {
                    ProgressView().controlSize(.small)
                }
                if !searchText.isEmpty {
                    Button {
                        searchTask?.cancel()
                        isSearching = false
                        searchText = ""
                        results = []
                        selectedResult = nil
                        searchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }.buttonStyle(.plain).focusable(false)
                }
                Button { performSearch() } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.blue)
                .focusable(false)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                Button { QuickSearchPanelController.shared.toggle(); searchFieldFocused = true } label: {
                    Image(systemName: "rectangle.and.text.magnifyingglass").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)
                .help(L("快速搜索面板"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if showSearchOptions {
                searchOptionsPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            // Results header
            if !results.isEmpty {
                HStack(spacing: 8) {
                    Text(isSearching ? LF("已找到 %d 个结果...", results.count) : LF("%d 个结果", results.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { showHistory.toggle() } label: {
                        Image(systemName: "clock").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help(L("搜索历史"))
                    Button { showCompendium.toggle() } label: {
                        Image(systemName: "doc.text.image").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help(L("报告"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                Divider()
            }

            // Results list or empty state
            if results.isEmpty && !isSearching {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty ? L("输入关键词搜索全部文档") : L("无匹配结果"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(hasEnabledMemosSources ? "SearchKit + SQLite FTS5 + grep + Memos" : "SearchKit + SQLite FTS5 + grep")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List(results, selection: $selectedResult) { result in
                    ResultRow(result: result, isSelected: selectedResult == result)
                        .tag(result)
                        .contextMenu {
                            if result.isExternal {
                                Button(L("打开链接")) { openResult(result) }
                            } else {
                                Button(L("打开文件")) { openResult(result) }
                                Button(L("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.filePath)]) }
                            }
                        }
                }
                .listStyle(.plain)
                .animation(.smooth(duration: 0.25), value: results.map(\.id))
            }
        }
        .frame(minWidth: 300)
    }

    // MARK: - Detail Pane (Preview)

    private var detailPane: some View {
        Group {
            if let result = selectedResult {
                VStack(spacing: 0) {
                    // Preview toolbar
                    HStack(spacing: 8) {
                        Picker("", selection: $previewMode) {
                            Label("Live Preview", systemImage: "text.magnifyingglass").tag(PreviewMode.live)
                            Label(L("原文件"), systemImage: "doc.richtext").tag(PreviewMode.pdf)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

                        matchNavigationControls

                        Spacer()

                        HStack(spacing: 4) {
                            TextField(L("预览内查找"), text: $previewFindText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                                .frame(width: 150)
                                .focused($previewFindFocused)
                                .onSubmit { previewFindStep += 1 }
                            Button { previewFindStep -= 1 } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.plain)
                            .disabled(previewFindText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button { previewFindStep += 1 } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.plain)
                            .disabled(previewFindText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Menu {
                            Button(L("添加到报告")) { dataManager.addToCompendium(result: result, query: searchText) }
                            Button(L("导出高亮文档")) { dataManager.exportHighlighted(result: result, terms: searchTerms) }
                            Button(L("收藏搜索")) { dataManager.addBookmark(name: searchText, query: searchText) }
                            Divider()
                            if result.isExternal {
                                Button(L("打开链接")) { openResult(result) }
                            } else {
                                Button(L("打开文件")) { openResult(result) }
                                Button(L("在 Finder 中显示")) { NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "") }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)

                    Divider()

                    // Preview content with crossfade
                    Group {
                        if previewMode == .live {
                            LivePreviewView(
                                result: result,
                                searchOptions: currentSearchOptions,
                                primaryNavigationStep: primaryMatchStep,
                                secondaryQuery: previewFindText,
                                secondaryNavigationStep: previewFindStep
                            )
                        } else if result.isExternal {
                            LivePreviewView(
                                result: result,
                                searchOptions: currentSearchOptions,
                                primaryNavigationStep: primaryMatchStep,
                                secondaryQuery: previewFindText,
                                secondaryNavigationStep: previewFindStep
                            )
                        } else {
                            PDFPreviewView(
                                filePath: result.filePath,
                                searchTerms: searchTerms,
                                primaryNavigationStep: primaryMatchStep,
                                secondarySearchTerms: previewFindTerms,
                                secondaryNavigationStep: previewFindStep
                            )
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: previewMode)

                    if !documentMatchSnippets(for: result).isEmpty {
                        Divider()
                        documentMatchesPanel(for: result)
                    }
                }
            } else if let folder = indexManager.selectedFolder {
                FolderContentView(folder: folder)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text(L("选择结果查看 Live Preview"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(L("高亮搜索词 · 直接复制文本 · 无需打开原文件"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var previewFindTerms: [String] {
        previewFindText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private struct DocumentMatchSnippet: Identifiable, Hashable {
        let id: Int
        let snippet: String
    }

    private func initialMatchIndex(for result: SearchResult) -> Int {
        let content = result.content.isEmpty ? result.snippet : result.content
        let ranges = documentMatchRanges(in: content)
        guard !ranges.isEmpty else { return 0 }

        if let lineNumber = lineNumber(from: result.snippet) {
            let targetOffset = characterOffset(forLine: lineNumber, in: content)
            return ranges.enumerated()
                .min { lhs, rhs in
                    abs(content.distance(from: content.startIndex, to: lhs.element.lowerBound) - targetOffset) <
                    abs(content.distance(from: content.startIndex, to: rhs.element.lowerBound) - targetOffset)
                }?
                .offset ?? 0
        }

        let cleanedSnippet = normalizedMatchText(result.snippet)
        guard !cleanedSnippet.isEmpty else { return 0 }

        let context = max(80, AppSettings.shared.matchContextChars)
        return ranges.enumerated()
            .map { idx, range in
                let nearby = normalizedMatchText(snippetAround(range, in: content, context: context))
                return (idx: idx, score: snippetSimilarityScore(cleanedSnippet, nearby))
            }
            .max { $0.score < $1.score }?
            .idx ?? 0
    }

    private func documentMatchSnippets(for result: SearchResult) -> [DocumentMatchSnippet] {
        let content = result.content.isEmpty ? result.snippet : result.content
        let context = max(0, AppSettings.shared.matchContextChars)
        guard !content.isEmpty else { return [] }

        return documentMatchRanges(in: content)
            .enumerated()
            .map { idx, range in
                DocumentMatchSnippet(id: idx, snippet: snippetAround(range, in: content, context: context))
            }
    }

    private func documentMatchRanges(in content: String) -> [Range<String.Index>] {
        guard !content.isEmpty else { return [] }

        if currentSearchOptions.usesRegex {
            guard let regex = try? NSRegularExpression(pattern: currentSearchOptions.trimmedQuery, options: [.caseInsensitive]) else { return [] }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            return regex.matches(in: content, range: range).compactMap { match in
                Range(match.range, in: content)
            }
        }

        let terms = currentSearchOptions.highlightTerms
        guard !terms.isEmpty else { return [] }
        let lower = content.lowercased()
        var ranges: [Range<String.Index>] = []
        for term in terms {
            let needle = term.lowercased()
            guard !needle.isEmpty else { continue }
            var start = lower.startIndex
            while let range = lower.range(of: needle, range: start..<lower.endIndex) {
                ranges.append(range)
                start = range.upperBound
            }
        }

        return ranges
            .sorted { $0.lowerBound < $1.lowerBound }
    }

    private func lineNumber(from snippet: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*行\s*(\d+)\s*:"#) else { return nil }
        let range = NSRange(snippet.startIndex..<snippet.endIndex, in: snippet)
        guard let match = regex.firstMatch(in: snippet, range: range),
              let numberRange = Range(match.range(at: 1), in: snippet) else { return nil }
        return Int(snippet[numberRange])
    }

    private func characterOffset(forLine lineNumber: Int, in content: String) -> Int {
        guard lineNumber > 1 else { return 0 }
        var line = 1
        var offset = 0
        for char in content {
            if line >= lineNumber { break }
            offset += 1
            if char.isNewline { line += 1 }
        }
        return offset
    }

    private func normalizedMatchText(_ text: String) -> String {
        let withoutLinePrefix = text.replacingOccurrences(of: #"^\s*行\s*\d+\s*:\s*"#, with: "", options: .regularExpression)
        let withoutFilenamePrefix = withoutLinePrefix.replacingOccurrences(of: #"^\s*文件名匹配\s*:\s*"#, with: "", options: .regularExpression)
        return withoutFilenamePrefix
            .lowercased()
            .replacingOccurrences(of: #"[\s…\.]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snippetSimilarityScore(_ needle: String, _ haystack: String) -> Int {
        guard !needle.isEmpty, !haystack.isEmpty else { return 0 }
        if haystack.contains(needle) { return needle.count }

        let chars = Array(needle)
        let maxLength = min(chars.count, 48)
        guard maxLength >= 4 else { return haystack.contains(needle) ? needle.count : 0 }

        for length in stride(from: maxLength, through: 4, by: -1) {
            for start in 0...(chars.count - length) {
                let fragment = String(chars[start..<(start + length)])
                if haystack.contains(fragment) {
                    return length
                }
            }
        }
        return 0
    }

    private func snippetAround(_ range: Range<String.Index>, in content: String, context: Int) -> String {
        let start = content.index(range.lowerBound, offsetBy: -context, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: context, limitedBy: content.endIndex) ?? content.endIndex
        let prefix = start == content.startIndex ? "" : "…"
        let suffix = end == content.endIndex ? "" : "…"
        return prefix + String(content[start..<end]).replacingOccurrences(of: "\n", with: " ") + suffix
    }

    private func documentMatchesPanel(for result: SearchResult) -> some View {
        let matches = documentMatchSnippets(for: result)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.secondary.opacity(0.42))
                    .frame(width: 34, height: 4)
                Label(LF("当前文档 %d 个命中", matches.count), systemImage: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        documentMatchesCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: documentMatchesCollapsed ? "chevron.up.square" : "chevron.down.square")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help(documentMatchesCollapsed ? L("展开命中列表") : L("收起命中列表"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        guard !documentMatchesCollapsed else { return }
                        documentMatchesHeight = min(360, max(92, documentMatchesHeight - value.translation.height))
                    }
            )

            if !documentMatchesCollapsed {
                Divider()
                List(matches) { match in
                    Button {
                        documentMatchJumpCycle += 1
                        primaryMatchStep = match.id - max(matches.count, 1) * documentMatchJumpCycle
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(match.id + 1)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 22, alignment: .trailing)
                            Text(match.snippet)
                                .font(.system(size: 12))
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(height: documentMatchesHeight)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var matchNavigationControls: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.yellow)
            Button { primaryMatchStep -= 1 } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(searchTerms.isEmpty)
            Button { primaryMatchStep += 1 } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(searchTerms.isEmpty)
        }
        .help(L("跳转搜索词高亮"))
    }

    private var hasActiveSearchOptions: Bool {
        !selectedFileTypes.isEmpty || selectedSearchFolderPath != nil || usesRegex || !fuzzySpaces
    }

    private var fileTypeSummary: String {
        if selectedFileTypes.isEmpty { return L("全部类型") }
        return FileTypeFilter.allCases
            .filter { selectedFileTypes.contains($0) && $0 != .all }
            .map(\.displayName)
            .joined(separator: "、")
    }

    private var searchScopeSummary: String {
        guard let selectedSearchFolderPath else { return L("全部文件夹") }
        return URL(fileURLWithPath: selectedSearchFolderPath).lastPathComponent
    }

    private var searchOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L("搜索条件"), systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(searchScopeSummary) · \(fileTypeSummary)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Toggle(L("正则"), isOn: searchOptionBinding(\.usesRegex))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Toggle(L("空格模糊"), isOn: searchOptionBinding(\.fuzzySpaces))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Toggle("Memos", isOn: $includeMemos)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .disabled(!hasEnabledMemosSources)
                    .help(hasEnabledMemosSources ? "同时搜索已启用的 Memos 源" : "未配置启用的 Memos 源")
                    .onChange(of: includeMemos) { _, _ in rerunSearchIfNeeded() }
            }

            HStack(spacing: 8) {
                Text(L("范围"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                Picker("", selection: Binding(
                    get: { selectedSearchFolderPath ?? "" },
                    set: { newValue in
                        selectedSearchFolderPath = newValue.isEmpty ? nil : newValue
                        rerunSearchIfNeeded()
                    }
                )) {
                    Text(L("全部已添加文件夹")).tag("")
                    ForEach(indexManager.indexedFolders) { folder in
                        Text(URL(fileURLWithPath: folder.path).lastPathComponent).tag(folder.path)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(FileTypeFilter.allCases) { filter in
                        Button(filter.displayName) {
                            toggleFileType(filter)
                        }
                        .font(.system(size: 11, weight: isFileTypeSelected(filter) ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isFileTypeSelected(filter) ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                        .foregroundStyle(isFileTypeSelected(filter) ? Color.accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
    }

    private func searchOptionBinding(_ keyPath: WritableKeyPath<SearchOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                switch keyPath {
                case \SearchOptions.usesRegex: return usesRegex
                case \SearchOptions.fuzzySpaces: return fuzzySpaces
                default: return false
                }
            },
            set: { newValue in
                switch keyPath {
                case \SearchOptions.usesRegex: usesRegex = newValue
                case \SearchOptions.fuzzySpaces: fuzzySpaces = newValue
                default: break
                }
                rerunSearchIfNeeded()
            }
        )
    }

    private func isFileTypeSelected(_ filter: FileTypeFilter) -> Bool {
        filter == .all ? selectedFileTypes.isEmpty : selectedFileTypes.contains(filter)
    }

    private func toggleFileType(_ filter: FileTypeFilter) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if filter == .all {
                selectedFileTypes.removeAll()
            } else if selectedFileTypes.contains(filter) {
                selectedFileTypes.remove(filter)
            } else {
                selectedFileTypes.insert(filter)
            }
        }
        rerunSearchIfNeeded()
    }

    private func rerunSearchIfNeeded() {
        if !results.isEmpty {
            performSearch()
        }
        searchFieldFocused = true
    }

    // MARK: - Search

    private func performSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            searchTask?.cancel()
            isSearching = false
            return
        }
        searchTask?.cancel()
        isSearching = true
        results = []
        selectedResult = nil
        let options = currentSearchOptions
        searchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let items = await indexManager.search(options: options)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        appendSearchResults(items)
                    }
                }

                group.addTask {
                    let stream = await indexManager.grepSearch(options: options)
                    for await batch in stream {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            appendSearchResults(batch.results)
                        }
                    }
                }

                if includeMemos && !options.usesRegex {
                    group.addTask {
                        let memosResults = await MemosSearchService.shared.search(query: options.trimmedQuery, limit: 20)
                        let items = memosResults.map(Self.memosSearchResult)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            appendSearchResults(items)
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                isSearching = false
                dataManager.addHistory(query: q, resultCount: results.count)
                searchFieldFocused = true
            }
        }
    }

    private func appendSearchResults(_ newItems: [SearchResult]) {
        guard !newItems.isEmpty else { return }
        var didChange = false

        withAnimation(.smooth(duration: 0.18)) {
            for item in newItems {
                if let idx = results.firstIndex(where: { $0.filePath == item.filePath }) {
                    let existing = results[idx]
                    if item.content.count > existing.content.count {
                        results[idx] = item
                        if selectedResult?.filePath == item.filePath {
                            selectedResult = item
                        }
                        didChange = true
                    }
                } else {
                    results.append(item)
                    didChange = true
                }
            }

            if didChange, selectedResult == nil {
                selectedResult = results.first
            }
        }
    }

    nonisolated private static func memosSearchResult(_ result: ExternalSearchResult) -> SearchResult {
        SearchResult(
            id: result.id,
            filePath: result.url.isEmpty ? "memos://\(result.sourceID)/\(result.externalID)" : result.url,
            fileName: result.title,
            title: result.title,
            author: result.sourceName,
            snippet: result.snippet,
            content: result.content,
            fileSize: 0,
            lastModified: result.updatedAt,
            sourceKind: result.sourceKind,
            sourceName: result.sourceName,
            externalURL: result.url,
            externalID: result.externalID
        )
    }

    private func openResult(_ result: SearchResult) {
        if result.isExternal {
            guard let url = URL(string: result.externalURL.isEmpty ? result.filePath : result.externalURL) else { return }
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath))
        }
    }
}
