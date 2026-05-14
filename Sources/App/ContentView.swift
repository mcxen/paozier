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
                Text("选择搜索结果预览 PDF")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
