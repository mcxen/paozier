import SwiftUI
import AppKit

// MARK: - Panel Controller

final class QuickSearchPanelController {
    static let shared = QuickSearchPanelController()
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.close()
            self.panel = nil
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "快速搜索"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: QuickSearchPanelView())
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI View

struct QuickSearchPanelView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit(search)
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text(query.isEmpty ? "输入关键词快速搜索" : "无结果")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { result in
                    Button { openFile(result) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.blue).font(.caption)
                                Text(result.fileName)
                                    .font(.callout.weight(.medium)).lineLimit(1)
                            }
                            Text(result.snippet.isEmpty ? String(result.content.prefix(120)) : result.snippet)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let items = await SearchEngine.shared.search(query: q, limit: 15)
            await MainActor.run { results = items; isSearching = false }
        }
    }

    private func openFile(_ result: SearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath))
    }
}
