import SwiftUI
import AppKit

// MARK: - Panel Controller

@MainActor
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
            panel.title = L("快速搜索")
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: QuickSearchPanelView())
            addPinAccessory(to: panel)
            applySettings()
            panel.center()
            self.panel = panel
        }
        applySettings()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applySettings() {
        guard let panel else { return }
        let pinned = AppSettings.shared.quickSearchPanelAlwaysOnTop
        panel.isFloatingPanel = pinned
        panel.level = pinned ? .floating : .normal
        panel.hidesOnDeactivate = !pinned
    }

    private func addPinAccessory(to panel: NSPanel) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = NSHostingView(rootView: QuickSearchPinButton())
        panel.addTitlebarAccessoryViewController(accessory)
    }
}

@MainActor
final class QuickSearchStatusItemController: NSObject {
    static let shared = QuickSearchStatusItemController()
    private var statusItem: NSStatusItem?

    func sync() {
        if AppSettings.shared.quickSearchMenuBarEnabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: L("快速搜索"))
                ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: L("快速搜索"))
            button.imagePosition = .imageOnly
            button.toolTip = L("打开 Paozier 快速搜索")
            button.target = self
            button.action = #selector(openQuickSearch)
        }
        statusItem = item
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func openQuickSearch() {
        QuickSearchPanelController.shared.show()
    }
}

// MARK: - SwiftUI View

private struct QuickSearchPinButton: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button {
            settings.quickSearchPanelAlwaysOnTop.toggle()
            settings.save()
            QuickSearchPanelController.shared.applySettings()
        } label: {
            Image(systemName: settings.quickSearchPanelAlwaysOnTop ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(settings.quickSearchPanelAlwaysOnTop ? Color.accentColor : .secondary)
        .help(settings.quickSearchPanelAlwaysOnTop ? L("取消固定在最前") : L("固定在最前"))
    }
}

struct QuickSearchPanelView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索..."), text: $query)
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
                    Text(query.isEmpty ? L("输入关键词快速搜索") : L("无结果"))
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
