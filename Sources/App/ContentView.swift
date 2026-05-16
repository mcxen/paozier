import SwiftUI

struct ContentView: View {
    @EnvironmentObject var indexManager: IndexManager
    @StateObject private var dataManager = DataManager.shared
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false
    @State private var fileTypeFilter: FileTypeFilter = .all
    @State private var previewMode: PreviewMode = .live
    @State private var showCompendium = false
    @State private var showHistory = false
    @FocusState private var searchFieldFocused: Bool

    enum PreviewMode { case live, pdf }

    private var searchTerms: [String] {
        searchText.split(separator: " ").filter { !$0.hasPrefix("-") }.map { $0.replacingOccurrences(of: "\"", with: "") }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            contentPane
        } detail: {
            detailPane
                .id(selectedResult?.id)
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

            // File type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(FileTypeFilter.allCases) { filter in
                        Button(filter.rawValue) {
                            withAnimation(.easeInOut(duration: 0.15)) { fileTypeFilter = filter }
                            if !results.isEmpty { performSearch() }
                        }
                        .font(.system(size: 11, weight: fileTypeFilter == filter ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(fileTypeFilter == filter ? Color.accentColor.opacity(0.12) : Color.clear)
                        .foregroundStyle(fileTypeFilter == filter ? Color.accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

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
        .frame(minWidth: 300, idealWidth: 360)
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

                        Spacer()

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
                            LivePreviewView(result: result, searchTerms: searchTerms)
                        } else {
                            PDFPreviewView(filePath: result.filePath, searchTerms: searchTerms)
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

    // MARK: - Search

    private func performSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let items = await indexManager.search(query: q, fileTypeFilter: fileTypeFilter)
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
