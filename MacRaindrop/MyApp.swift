import SwiftUI

@main struct MyApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if let store = session.store {
                    ContentView()
                        .environment(store)
                        // A new token means a new library: start from a fresh window state.
                        .id(ObjectIdentifier(store))
                } else {
                    TokenPromptView()
                }
            }
            .environment(session)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            if let store = session.store {
                GoCommands(store: store)
                BookmarkCommands(store: store)
                #if DEBUG
                CommandMenu("Debug") {
                    Button("Sync Now") { Task { await store.sync() } }
                        .keyboardShortcut("r")
                        .disabled(store.isSyncing)
                    Toggle("Simulate Write Failures", isOn: Binding {
                        store.simulatesWriteFailures
                    } set: {
                        store.simulatesWriteFailures = $0
                    })
                }
                #endif
            }
        }

        Settings {
            TokenSettingsView()
                .environment(session)
        }
    }
}
