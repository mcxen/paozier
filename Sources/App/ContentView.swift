import SwiftUI

struct ContentView: View {
    @EnvironmentObject var indexManager: IndexManager
    @StateObject private var dataManager = DataManager.shared
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false
    @State private var selectedFileTypes: Set<FileTypeFilter> = []
    @State private var selectedSearchFolderPath: String?
    @State private var usesRegex = false
    @State private var fuzzySpaces = true
    @State private var showSearchOptions = false
    @State private var previewMode: PreviewMode = .live
    @State private var showCompendium = false
    @State private var showHistory = false
    @State private var activePane: MainPane = .search
    @State private var primaryMatchStep = 0
    @State private var previewFindText = ""
    @State private var previewFindStep = 0
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
                TextField("搜索文档内容...", text: $searchText)
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
                .help("搜索条件")
                if isSearching {
                    ProgressView().controlSize(.small)
                }
                if !searchText.isEmpty {
                    Button { searchText = ""; results = []; searchFieldFocused = true } label: {
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
                .help("快速搜索面板")
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
                    Text("\(results.count) 个结果")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { showHistory.toggle() } label: {
                        Image(systemName: "clock").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("搜索历史")
                    Button { showCompendium.toggle() } label: {
                        Image(systemName: "doc.text.image").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("报告")
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
                    Text(searchText.isEmpty ? "输入关键词搜索全部文档" : "无匹配结果")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("SearchKit + SQLite FTS5 双引擎 · 支持中英文")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List(results, selection: $selectedResult) { result in
                    ResultRow(result: result, isSelected: selectedResult == result)
                        .tag(result)
                        .contextMenu {
                            Button("打开文件") { NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath)) }
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.filePath)]) }
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
                            Label("原文件", systemImage: "doc.richtext").tag(PreviewMode.pdf)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

                        matchNavigationControls

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("预览内查找", text: $previewFindText)
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
                            Button("添加到报告") { dataManager.addToCompendium(result: result, query: searchText) }
                            Button("导出高亮文档") { dataManager.exportHighlighted(result: result, terms: searchTerms) }
                            Button("收藏搜索") { dataManager.addBookmark(name: searchText, query: searchText) }
                            Divider()
                            Button("打开文件") { NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath)) }
                            Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "") }
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
                }
            } else if let folder = indexManager.selectedFolder {
                FolderContentView(folder: folder)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("选择结果查看 Live Preview")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("高亮搜索词 · 直接复制文本 · 无需打开原文件")
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
        .help("跳转搜索词高亮")
    }

    private var hasActiveSearchOptions: Bool {
        !selectedFileTypes.isEmpty || selectedSearchFolderPath != nil || usesRegex || !fuzzySpaces
    }

    private var fileTypeSummary: String {
        if selectedFileTypes.isEmpty { return "全部类型" }
        return FileTypeFilter.allCases
            .filter { selectedFileTypes.contains($0) && $0 != .all }
            .map(\.rawValue)
            .joined(separator: "、")
    }

    private var searchScopeSummary: String {
        guard let selectedSearchFolderPath else { return "全部文件夹" }
        return URL(fileURLWithPath: selectedSearchFolderPath).lastPathComponent
    }

    private var searchOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("搜索条件", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(searchScopeSummary) · \(fileTypeSummary)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Toggle("正则", isOn: searchOptionBinding(\.usesRegex))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Toggle("空格模糊", isOn: searchOptionBinding(\.fuzzySpaces))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }

            HStack(spacing: 8) {
                Text("范围")
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
                    Text("全部已添加文件夹").tag("")
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
                        Button(filter.rawValue) {
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
        guard !q.isEmpty else { return }
        isSearching = true
        let options = currentSearchOptions
        Task {
            let items = await indexManager.search(options: options)
            await MainActor.run {
                withAnimation(.smooth(duration: 0.25)) {
                    results = items
                    selectedResult = items.first
                }
                isSearching = false
                dataManager.addHistory(query: q, resultCount: items.count)
                searchFieldFocused = true
            }
        }
    }
}
