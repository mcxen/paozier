import SwiftUI
import AppKit

@main
struct PaozierApp: App {
    @StateObject private var indexManager = IndexManager()

    init() {
        // Ensure app activates as regular GUI app when launched from .app bundle
        NSApplication.shared.setActivationPolicy(.regular)
        // Defer hotkey registration until after run loop is established
        DispatchQueue.main.async {
            GlobalSearchPopupController.shared.registerHotkey()
            QuickSearchStatusItemController.shared.sync()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(indexManager)
                .frame(minWidth: 900, minHeight: 600)
                .background(MainWindowConfigurator())
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L("设置...")) {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu(L("快捷设置")) {
                Button(L("打开设置")) {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button(L("快速搜索面板")) {
                    QuickSearchPanelController.shared.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button(L("全局搜索")) {
                    GlobalSearchPopupController.shared.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button(L("打开网页搜索")) {
                    openWebSearch()
                }
                .disabled(!indexManager.httpRunning)

                Divider()

                Button(indexManager.httpRunning ? L("停止 HTTP 搜索服务") : L("启动 HTTP 搜索服务")) {
                    indexManager.httpRunning ? indexManager.stopHTTP() : indexManager.startHTTP()
                }

                Button(indexManager.mcpRunning ? L("停止 MCP AI 工具服务") : L("启动 MCP AI 工具服务")) {
                    indexManager.mcpRunning ? indexManager.stopMCP() : indexManager.startMCP()
                }

                Divider()

                Button(L("重建全部索引")) {
                    Task { await indexManager.reindexAll() }
                }
                .disabled(indexManager.isIndexing)
            }
        }
    }

    private func openWebSearch() {
        guard let url = URL(string: "http://localhost:\(indexManager.httpServer.port)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(window: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(window: nsView.window) }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}
