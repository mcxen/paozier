import SwiftUI

struct SearchResultsView: View {
    @Binding var searchText: String
    @Binding var results: [SearchResult]
    @Binding var selectedResult: SearchResult?
    @Binding var isSearching: Bool
    @Binding var fileTypeFilter: FileTypeFilter
    let searchError: String?
    var onSearch: () -> Void

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("搜索文档内容...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .focused($searchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit { runSearchIfReady() }
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
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    runSearchIfReady()
                } label: {
                    Label("搜索", systemImage: "arrow.right.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.45) : Color.blue)
                .help("搜索")
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            // File type filter
            HStack(spacing: 6) {
                ForEach(FileTypeFilter.allCases) { filter in
                    Button(filter.rawValue) {
                        fileTypeFilter = filter
                        if !results.isEmpty { onSearch() }
                    }
                    .buttonStyle(.bordered)
                    .tint(fileTypeFilter == filter ? .blue : .gray)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            Divider()

            // Results count
            if !results.isEmpty {
                HStack {
                    Text("\(results.count) 个结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }

            // Results list
            if isSearching && results.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在搜索...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let searchError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(.orange)
                    Text(searchError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "text.magnifyingglass" : "doc.questionmark")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text(searchText.isEmpty ? "输入关键词搜索全部文档" : "无匹配结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Text("支持 PDF、Word、Excel、TXT、Markdown 等格式")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
        .onAppear {
            searchFieldFocused = true
        }
    }

    private func runSearchIfReady() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSearch()
    }
}

struct ResultRow: View {
    let result: SearchResult
    var isSelected: Bool = false

    @State private var isHovered = false

    private var fileIcon: String {
        let ext = URL(fileURLWithPath: result.filePath).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc": return "doc.fill"
        case "xlsx", "xls", "csv": return "tablecells.fill"
        case "pptx", "ppt": return "rectangle.fill.on.rectangle.fill"
        case "html", "htm": return "globe"
        case "md", "markdown": return "text.document"
        case "json", "xml": return "curlybraces"
        default: return "doc.text.fill"
        }
    }

    private var iconColor: Color {
        let ext = URL(fileURLWithPath: result.filePath).pathExtension.lowercased()
        switch ext {
        case "pdf": return .red
        case "docx", "doc": return .blue
        case "xlsx", "xls", "csv": return .green
        case "pptx", "ppt": return .orange
        case "html", "htm": return .purple
        default: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fileIcon)
                .foregroundStyle(iconColor)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title.isEmpty ? result.fileName : result.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: result.filePath).pathExtension.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(iconColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if result.fileSize > 0 {
                        Text(formatSize(result.fileSize))
                            .font(.system(size: 10))
                    }

                    if !result.author.isEmpty {
                        Text(result.author)
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && !isSelected ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
