import SwiftUI

@main
struct PaozierApp: App {
    @StateObject private var solrManager = SolrManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(solrManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
