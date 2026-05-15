import SwiftUI

struct ContentView: View {
    @EnvironmentObject var indexManager: IndexManager
    @StateObject private var dataManager = DataManager.shared
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false
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
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索文档内容...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFieldFocused)
                        .onSubmit(performSearch)
                    if isSearching { ProgressView().controlSize(.small) }
                    if !searchText.isEmpty {
                        Button { searchText = ""; results = []; searchFieldFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }.buttonStyle(.plain).focusable(false)
                    }
                    Button { performSearch() } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    Button { QuickSearchPanelController.shared.toggle(); searchFieldFocused = true } label: {
                        Image(systemName: "rectangle.and.text.magnifyingglass")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("快速搜索面板")
                }
                .padding(10)
                .background(.regularMaterial)

                Divider()

                if !results.isEmpty {
                    HStack {
                        Text("\(results.count) 个结果").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { showHistory.toggle() } label: { Label("历史", systemImage: "clock") }.font(.caption).buttonStyle(.borderless)
                        Button { showCompendium.toggle() } label: { Label("报告", systemImage: "doc.text.image") }.font(.caption).buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    Divider()
                }

                if results.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass").font(.system(size: 40, weight: .thin)).foregroundStyle(.quaternary)
                        Text(searchText.isEmpty ? "输入关键词搜索全部文档" : "无匹配结果").font(.callout).foregroundStyle(.secondary)
                        Text("SearchKit + SQLite FTS5 双引擎 · 支持中英文").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, selection: $selectedResult) { result in
                        ResultRow(result: result).tag(result)
                    }.listStyle(.plain)
                }
            }
            .frame(minWidth: 320)
        } detail: {
            if let result = selectedResult {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Button { previewMode = .live } label: { Label("Live Preview", systemImage: "text.magnifyingglass").font(.caption).frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(previewMode == .live ? .blue : .gray).controlSize(.small)
                        Button { previewMode = .pdf } label: { Label("原文件", systemImage: "doc.richtext").font(.caption).frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(previewMode == .pdf ? .blue : .gray).controlSize(.small)
                        Spacer()
                        Menu {
                            Button("添加到报告") { dataManager.addToCompendium(result: result, query: searchText) }
                            Button("导出高亮文档") { dataManager.exportHighlighted(result: result, terms: searchTerms) }
                            Button("收藏搜索") { dataManager.addBookmark(name: searchText, query: searchText) }
                            Divider()
                            Button("打开文件") { NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath)) }
                            Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "") }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 28)
                    }
                    .padding(6).background(.bar)
                    Divider()
                    if previewMode == .live {
                        LivePreviewView(result: result, searchTerms: searchTerms)
                    } else {
                        PDFPreviewView(filePath: result.filePath)
                    }
                }
            } else if let folder = indexManager.selectedFolder {
                FolderContentView(folder: folder)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.below.ecg").font(.system(size: 44, weight: .thin)).foregroundStyle(.quaternary)
                    Text("选择结果查看 Live Preview").foregroundStyle(.secondary).font(.callout)
                    Text("高亮搜索词 · 直接复制文本 · 无需打开原文件").font(.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    private func performSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let items = await indexManager.search(query: q)
            await MainActor.run {
                results = items
                selectedResult = items.first
                isSearching = false
                dataManager.addHistory(query: q, resultCount: items.count)
                searchFieldFocused = true
            }
        }
    }
}
