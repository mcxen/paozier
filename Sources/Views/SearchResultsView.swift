import SwiftUI

struct SearchResultsView: View {
    @Binding var searchText: String
    @Binding var results: [SearchResult]
    @Binding var selectedResult: SearchResult?
    @Binding var isSearching: Bool
    var onSearch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索 PDF 内容...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit(onSearch)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.bar)

            Divider()

            // Results
            if results.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty ? "输入关键词搜索 PDF 全文" : "无匹配结果")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, selection: $selectedResult) { result in
                    ResultRow(result: result)
                        .tag(result)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 320)
    }
}

struct ResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(result.title.isEmpty ? result.fileName : result.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if !result.author.isEmpty {
                    Label(result.author, systemImage: "person")
                }
                if result.fileSize > 0 {
                    Label(formatSize(result.fileSize), systemImage: "doc")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
