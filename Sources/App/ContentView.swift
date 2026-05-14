import SwiftUI

struct ContentView: View {
    @EnvironmentObject var solrManager: SolrManager
    @StateObject private var dataManager = DataManager.shared
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false
    // Proximity
    @State private var proximityActive = false
    @State private var proxTerm1 = ""
    @State private var proxTerm2 = ""
    @State private var proxDistance: Double = 5
    // Search mode
    @State private var useRegex = false
    // Preview
    @State private var previewMode: PreviewMode = .live
    // Panels
    @State private var showCompendium = false
    @State private var showHistory = false

    enum PreviewMode { case live, pdf }

    private var searchTerms: [String] {
        if proximityActive { return [proxTerm1, proxTerm2].filter { !$0.isEmpty } }
        return searchText.split(separator: " ").filter { !$0.hasPrefix("-") }.map { $0.replacingOccurrences(of: "\"", with: "") }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            VStack(spacing: 0) {
                SearchResultsView(
                    searchText: $searchText,
                    results: $results,
                    selectedResult: $selectedResult,
                    isSearching: $isSearching,
                    onSearch: performSearch
                )

                Divider()

                // Search options
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        Toggle("正则", isOn: $useRegex).toggleStyle(.checkbox).font(.caption)
                        Spacer()
                        Button { showHistory.toggle() } label: {
                            Label("历史", systemImage: "clock")
                        }.font(.caption).buttonStyle(.borderless)
                        Button { showCompendium.toggle() } label: {
                            Label("报告", systemImage: "doc.text.image")
                        }.font(.caption).buttonStyle(.borderless)
                    }

                    ProximitySearchView(
                        isActive: $proximityActive,
                        term1: $proxTerm1,
                        term2: $proxTerm2,
                        distance: $proxDistance,
                        onSearch: performProximitySearch
                    )
                }
                .padding(8)
            }
        } detail: {
            if let result = selectedResult {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Button { previewMode = .live } label: {
                            Label("Live Preview", systemImage: "text.magnifyingglass").font(.caption).frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(previewMode == .live ? .blue : .gray).controlSize(.small)
                        Button { previewMode = .pdf } label: {
                            Label("PDF", systemImage: "doc.richtext").font(.caption).frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(previewMode == .pdf ? .blue : .gray).controlSize(.small)

                        Spacer()

                        // Actions
                        Menu {
                            Button("添加到报告") { dataManager.addToCompendium(result: result, query: searchText) }
                            Button("导出高亮文档") { dataManager.exportHighlighted(result: result, terms: searchTerms) }
                            Button("收藏搜索") { dataManager.addBookmark(name: searchText, query: searchText) }
                            Divider()
                            Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 28)
                    }
                    .padding(6)
                    .background(.bar)
                    Divider()

                    if previewMode == .live {
                        LivePreviewView(result: result, searchTerms: searchTerms)
                    } else {
                        PDFPreviewView(filePath: result.filePath)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("选择结果查看 Live Preview")
                        .foregroundStyle(.secondary).font(.callout)
                    Text("支持排除词(-term) · 引号精确匹配 · 正则表达式 · 邻近搜索")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showCompendium) { CompendiumView() }
        .sheet(isPresented: $showHistory) { HistoryView(onSelect: { query in searchText = query; showHistory = false; performSearch() }) }
        .task { await solrManager.startSolr() }
        .environmentObject(dataManager)
    }

    private func performSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let items = try? await SolrService.shared.search(query: q, useRegex: useRegex)
            await MainActor.run {
                results = items ?? []
                isSearching = false
                dataManager.addHistory(query: q, resultCount: results.count)
            }
        }
    }

    private func performProximitySearch() {
        guard !proxTerm1.isEmpty, !proxTerm2.isEmpty else { return }
        isSearching = true
        searchText = "\(proxTerm1) \(proxTerm2)"
        Task {
            let items = try? await SolrService.shared.search(query: "\(proxTerm1) \(proxTerm2)", proximity: Int(proxDistance))
            await MainActor.run {
                results = items ?? []
                isSearching = false
                dataManager.addHistory(query: searchText, resultCount: results.count)
            }
        }
    }
}
