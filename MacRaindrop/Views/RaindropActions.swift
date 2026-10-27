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

/// Unsorted, then the collection tree as nested submenus, for choosing a collection.
struct CollectionMenuItems: View {
    @Environment(LibraryStore.self) private var store
    var isDisabled: (RaindropCollection.ID) -> Bool = { _ in false }
    let choose: (RaindropCollection.ID) -> Void

    var body: some View {
        Button("Unsorted", systemImage: "tray") { choose(SystemCollectionID.unsorted) }
            .disabled(isDisabled(SystemCollectionID.unsorted))
        Divider()
        ForEach(store.collectionTree) { node in
            CollectionMenuNode(node: node, isDisabled: isDisabled, choose: choose)
        }
    }
}

private struct CollectionMenuNode: View {
    let node: CollectionNode
    let isDisabled: (RaindropCollection.ID) -> Bool
    let choose: (RaindropCollection.ID) -> Void

    var body: some View {
        let title = node.collection.title
        if let children = node.children {
            Menu(title) {
                Button("“\(title)”") { choose(node.id) }
                    .disabled(isDisabled(node.id))
                Divider()
                ForEach(children) { CollectionMenuNode(node: $0, isDisabled: isDisabled, choose: choose) }
            }
        } else {
            Button(title) { choose(node.id) }
                .disabled(isDisabled(node.id))
        }
    }
}

// MARK: Prompts

/// Actions that need to ask something first. Each window has one; `ContentView` presents them.
@Observable
final class ActionPrompts {
    var editing: Raindrop?
    var tagging: TagRequest?
    var deletion: DeletionRequest?

    /// Moves raindrops to the Trash right away, since that can be undone from there. If any are
    /// already in the Trash, asks first, because deleting those is permanent.
    func delete(_ raindrops: [Raindrop], in store: LibraryStore) {
        guard !raindrops.isEmpty else { return }
        let ids = raindrops.map(\.id)
        if raindrops.contains(where: \.isInTrash) {
            deletion = DeletionRequest(ids: ids, includesOthers: !raindrops.allSatisfy(\.isInTrash))
        } else {
            Task {
                await store.attempt("Couldn't Move to Trash") { try await store.delete(ids) }
            }
        }
    }
}

struct TagRequest: Identifiable {
    let id = UUID()
    let ids: [Raindrop.ID]
}

struct DeletionRequest: Identifiable {
    let id = UUID()
    let ids: [Raindrop.ID]
    /// Some of the raindrops aren't in the Trash yet, so they'll move there instead.
    let includesOthers: Bool
}

/// Asks for tags to add to one or more raindrops, and waits for the server before closing.
struct AddTagsSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: TagRequest

    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Comma-separated, with any leading `#` dropped.
    private var tags: [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var suggestions: [String] {
        store.tags.map(\.name).filter { !tags.contains($0) }.prefix(12).map(\.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.ids.count == 1 ? "Add Tags" : "Add Tags to \(request.ids.count) Bookmarks")
                .font(.headline)

            TextField("Tags", text: $text, prompt: Text("design, swift, to read"))
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)
                .onSubmit(save)

            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button("#\(tag)") { text = (tags + [tag]).joined(separator: ", ") }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tags.isEmpty || isSaving || !store.canModify(request.ids))
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        guard !tags.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await store.addTags(tags, to: request.ids)
                dismiss()
            } catch {
                // Stay open with what was typed, so nothing is lost.
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: Menu bar

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

private extension View {
    func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command, if condition: Bool) -> some View {
        keyboardShortcut(condition ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }
}
