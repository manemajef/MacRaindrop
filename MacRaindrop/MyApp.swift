import SwiftUI

@main struct MyApp: App {
    @State private var store = LibraryStore(service: RaindropServices.makeDefault())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Sync Now") { Task { await store.sync() } }
                    .keyboardShortcut("r")
                    .disabled(store.isSyncing)
            }
        }
    }
}
