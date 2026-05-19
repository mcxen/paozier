import SwiftUI

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
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
