import SwiftUI

extension FocusedValues {
    /// The focused window's navigation, for the Go menu.
    @Entry var navigation: NavigationModel?
}

/// The Go menu, like Finder's: Back, Forward and Enclosing Folder.
struct GoCommands: Commands {
    let store: LibraryStore
    @FocusedValue(\.navigation) private var navigation

    var body: some Commands {
        CommandMenu("Go") {
            Button("Back") { navigation?.goBack() }
                .keyboardShortcut("[")
                .disabled(navigation?.canGoBack != true)
            Button("Forward") { navigation?.goForward() }
                .keyboardShortcut("]")
                .disabled(navigation?.canGoForward != true)
            Button("Enclosing Folder") {
                if let navigation, let parent = navigation.enclosingCollection(in: store) {
                    navigation.go(to: .collection(parent))
                }
            }
            .keyboardShortcut(.upArrow)
            .disabled(navigation?.enclosingCollection(in: store) == nil)
        }
    }
}
