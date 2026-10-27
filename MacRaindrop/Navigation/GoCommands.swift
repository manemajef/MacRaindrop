import SwiftUI

extension FocusedValues {
    /// The focused window's navigation, for the Go menu.
    @Entry var browser: BrowserModel?
}

/// The Go menu, like Finder's: Back, Forward and Enclosing Folder.
struct GoCommands: Commands {
    let store: LibraryStore
    @FocusedValue(\.browser) private var browser

    var body: some Commands {
        CommandMenu("Go") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[")
                .disabled(browser?.canGoBack != true)
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]")
                .disabled(browser?.canGoForward != true)
            Button("Enclosing Folder") {
                if let browser, let parent = browser.enclosingCollection(in: store) {
                    browser.go(to: .collection(parent))
                }
            }
            .keyboardShortcut(.upArrow)
            .disabled(browser?.enclosingCollection(in: store) == nil)
        }
    }
}
