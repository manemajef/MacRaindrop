import AppKit
import SwiftUI

/// The actions for one or more raindrops, in the iOS app's order. The same items fill the
/// context menus and the Bookmark menu in the menu bar.
struct RaindropActions: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    /// Only the menu bar's copy carries keyboard shortcuts, so each shortcut exists once.
    var showsShortcuts = false

    private var ids: [Raindrop.ID] { raindrops.map(\.id) }
    private var urls: [URL] { raindrops.compactMap(\.url) }
    private var allFavorites: Bool { !raindrops.isEmpty && raindrops.allSatisfy(\.important) }
    private var canModify: Bool { !raindrops.isEmpty && store.canModify(ids) }

    var body: some View {
        Button("Open in Browser", systemImage: "safari") { urls.forEach { openURL($0) } }
            .shortcut("o", if: showsShortcuts)
            .disabled(urls.isEmpty)

        Button("Edit…", systemImage: "pencil") {
            if let raindrop = raindrops.first { prompts.editing = raindrop }
        }
        .shortcut("e", if: showsShortcuts)
        .disabled(raindrops.count != 1 || !canModify)

        Divider()

        Button(urls.count > 1 ? "Copy \(urls.count) Links" : "Copy Link", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        }
        .shortcut("c", modifiers: [.command, .shift], if: showsShortcuts)
        .disabled(urls.isEmpty)

        if urls.isEmpty {
            Button("Share…", systemImage: "square.and.arrow.up") {}
                .disabled(true)
        } else {
            ShareLink(items: urls) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }

        MoveMenu(raindrops: raindrops)
            .disabled(!canModify)

        Button("Add Tags…", systemImage: "number") {
            prompts.tagging = TagRequest(ids: ids)
        }
        .shortcut("t", modifiers: [.command, .shift], if: showsShortcuts)
        .disabled(!canModify)

        Button(
            allFavorites ? "Remove from Favorites" : "Add to Favorites",
            systemImage: allFavorites ? "heart.slash" : "heart"
        ) {
            let ids = ids
            let important = !allFavorites
            Task {
                await store.attempt(important ? "Couldn't Add to Favorites" : "Couldn't Remove from Favorites") {
                    try await store.setImportant(ids, important)
                }
            }
        }
        .shortcut("d", if: showsShortcuts)
        .disabled(!canModify)

        Divider()

        let deletesForGood = raindrops.contains(where: \.isInTrash)
        Button(deletesForGood ? "Delete Immediately…" : "Move to Trash", systemImage: "trash", role: .destructive) {
            prompts.delete(raindrops, in: store)
        }
        .shortcut(.delete, if: showsShortcuts)
        .disabled(!canModify)
    }
}

/// "Move to" with the collection tree as nested submenus.
private struct MoveMenu: View {
    @Environment(LibraryStore.self) private var store
    let raindrops: [Raindrop]

    var body: some View {
        Menu("Move to", systemImage: "folder") {
            CollectionMenuItems(isDisabled: { collectionID in
                // Nothing to do when every raindrop is already there.
                raindrops.allSatisfy { $0.collectionID == collectionID && !$0.isInTrash }
            }, choose: { collectionID in
                let ids = raindrops.map(\.id)
                Task {
                    await store.attempt("Couldn't Move Bookmarks") {
                        try await store.move(ids, to: collectionID)
                    }
                }
            })
        }
    }
}

private extension View {
    func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command, if condition: Bool) -> some View {
        keyboardShortcut(condition ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }
}
