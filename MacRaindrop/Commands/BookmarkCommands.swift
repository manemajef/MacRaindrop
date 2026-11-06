import SwiftUI

/// The selection of the focused window, for the menu bar's Bookmark menu.
struct BookmarkContext {
    var raindrops: [Raindrop]
    var prompts: ActionPrompts
}

extension FocusedValues {
    @Entry var bookmarkContext: BookmarkContext?
}

struct BookmarkCommands: Commands {
    let store: LibraryStore
    @FocusedValue(\.bookmarkContext) private var context

    var body: some Commands {
        CommandMenu("Bookmark") {
            RaindropActions(raindrops: context?.raindrops ?? [], showsShortcuts: true)
                .environment(store)
                .environment(context?.prompts ?? ActionPrompts())
        }
    }
}
