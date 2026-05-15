import SwiftUI

@main
struct PaozierApp: App {
    @StateObject private var indexManager = IndexManager()

    init() {
        GlobalSearchPopupController.shared.registerHotkey()
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
