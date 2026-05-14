import SwiftUI

struct ContentView: View {
    @EnvironmentObject var solrManager: SolrManager
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false
    // Proximity search
    @State private var proximityActive = false
    @State private var proxTerm1 = ""
    @State private var proxTerm2 = ""
    @State private var proxDistance: Double = 5
    // Preview mode
    @State private var previewMode: PreviewMode = .live

    enum PreviewMode { case live, pdf }

    private var searchTerms: [String] {
        if proximityActive {
            return [proxTerm1, proxTerm2].filter { !$0.isEmpty }
        }
        return searchText.split(separator: " ").map(String.init)
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

                // Proximity search panel
                ProximitySearchView(
                    isActive: $proximityActive,
                    term1: $proxTerm1,
                    term2: $proxTerm2,
                    distance: $proxDistance,
                    onSearch: performProximitySearch
                )
                .padding(8)
            }
        } detail: {
            if let result = selectedResult {
                VStack(spacing: 0) {
                    // Toggle between Live Preview and PDF
                    HStack(spacing: 0) {
                        Button { previewMode = .live } label: {
                            Label("Live Preview", systemImage: "text.magnifyingglass")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(previewMode == .live ? .blue : .gray)
                        .controlSize(.small)

                        Button { previewMode = .pdf } label: {
                            Label("PDF", systemImage: "doc.richtext")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(previewMode == .pdf ? .blue : .gray)
                        .controlSize(.small)
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
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("高亮搜索词 · 直接复制文本 · 无需打开原文件")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await solrManager.startSolr()
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        Task {
            let items = try? await SolrService.shared.search(query: searchText)
            await MainActor.run {
                results = items ?? []
                isSearching = false
            }
        }
    }

    private func performProximitySearch() {
        guard !proxTerm1.isEmpty, !proxTerm2.isEmpty else { return }
        isSearching = true
        searchText = "\(proxTerm1) \(proxTerm2)"
        Task {
            let items = try? await SolrService.shared.search(
                query: "\(proxTerm1) \(proxTerm2)",
                proximity: Int(proxDistance)
            )
            await MainActor.run {
                results = items ?? []
                isSearching = false
            }
        }
    }
}
