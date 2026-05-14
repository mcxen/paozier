import SwiftUI

struct ContentView: View {
    @EnvironmentObject var solrManager: SolrManager
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var isSearching = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            SearchResultsView(
                searchText: $searchText,
                results: $results,
                selectedResult: $selectedResult,
                isSearching: $isSearching,
                onSearch: performSearch
            )
        } detail: {
            if let result = selectedResult {
                PDFPreviewView(filePath: result.filePath)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("选择搜索结果预览文档")
                        .foregroundStyle(.secondary)
                        .font(.callout)
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
            do {
                let items = try await SolrService.shared.search(query: searchText)
                await MainActor.run {
                    results = items
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }
}
