import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Global Popup Controller

final class GlobalSearchPopupController {
    static let shared = GlobalSearchPopupController()
    private var window: NSWindow?
    private var monitor: Any?
    private var localMonitor: Any?

    func registerHotkey() {
        // Cmd+Shift+F global hotkey
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 3 { // 3 = 'F'
                DispatchQueue.main.async { self?.toggle() }
            }
        }
        // Also monitor when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 3 {
                DispatchQueue.main.async { self?.toggle() }
                return nil
            }
            return event
        }
    }

    func toggle() {
        if let window, window.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.hasShadow = true
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: GlobalSearchPopupView(onDismiss: { [weak self] in self?.dismiss() }))
            self.window = w
        }
        // Center on screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - 560) / 2
            let y = (screen.frame.height - 400) / 2 + 100
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}

// MARK: - SwiftUI View

struct GlobalSearchPopupView: View {
    var onDismiss: () -> Void
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0
    @State private var isSearching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.blue)
                TextField("全局搜索文档...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(openSelected)
                if isSearching { ProgressView().controlSize(.small) }
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(14)

            Divider()

            if results.isEmpty && !query.isEmpty && !isSearching {
                Text("无匹配结果").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                Text("输入关键词搜索已索引文档").font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(results.enumerated()), id: \.element.id) { idx, result in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(idx == selectedIndex ? .white : .blue)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.fileName)
                                    .font(.callout.weight(.medium)).lineLimit(1)
                                    .foregroundStyle(idx == selectedIndex ? .white : .primary)
                                Text(result.snippet.isEmpty ? String(result.content.prefix(100)) : result.snippet)
                                    .font(.caption).lineLimit(1)
                                    .foregroundStyle(idx == selectedIndex ? .white.opacity(0.8) : .secondary)
                            }
                            Spacer()
                            if idx == selectedIndex {
                                Text("⏎").font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(idx == selectedIndex ? Color.blue : Color.clear))
                        .id(idx)
                        .onTapGesture { openResult(result) }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { _, newVal in
                        proxy.scrollTo(newVal, anchor: .center)
                    }
                }
            }

            // Footer
            HStack(spacing: 12) {
                Text("↑↓ 选择").font(.caption2).foregroundStyle(.tertiary)
                Text("⏎ 打开").font(.caption2).foregroundStyle(.tertiary)
                Text("⎋ 关闭").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("\(results.count) 个结果").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in search() }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        Task {
            let items = await SearchEngine.shared.search(query: q, limit: 12)
            await MainActor.run { results = items; selectedIndex = 0; isSearching = false }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    private func openSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        openResult(results[selectedIndex])
    }

    private func openResult(_ result: SearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: result.filePath))
        onDismiss()
    }
}
