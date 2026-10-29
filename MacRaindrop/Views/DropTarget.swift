import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Lets a sidebar row or folder tile take dropped bookmarks, and collections take
    /// dropped collections:
    ///
    /// - a collection: bookmarks move into it, collections nest inside it
    /// - Unsorted: bookmarks move there
    /// - Favorites: bookmarks become favorites
    /// - Trash: bookmarks are deleted (asking first for any already in the Trash)
    /// - a tag: bookmarks get that tag
    func dropTarget(for item: SidebarItem) -> some View {
        modifier(DropTarget(target: .item(item)))
    }

    /// Lets the Collections heading take dropped collections, moving them to the top level.
    func topLevelCollectionsDropTarget() -> some View {
        modifier(DropTarget(target: .topLevel))
    }
}

private struct DropTarget: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    let target: LibraryDrop.Target
    @State private var isTargeted = false

    private var acceptedTypes: [UTType] {
        switch target {
        case .item(.collection): [.raindropBookmark, .raindropCollection]
        case .item(.all): []
        case .item: [.raindropBookmark]
        case .topLevel: [.raindropCollection]
        }
    }

    func body(content: Content) -> some View {
        content
            .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
                Task { await drop(providers) }
                return true
            }
            .background {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.tint.opacity(0.25))
                        .padding(-4)
                }
            }
    }

    private func drop(_ providers: [NSItemProvider]) async {
        let bookmarks = await load(RaindropLink.self, from: providers, type: .raindropBookmark).map(\.id)
        let collections = await load(CollectionDrag.self, from: providers, type: .raindropCollection).map(\.id)
        let action = LibraryDrop(target: target, store: store, prompts: prompts)
        if !bookmarks.isEmpty { await action.bookmarks(bookmarks) }
        for id in collections { await action.collection(id) }
    }

    /// Decodes the dragged items of `type`, skipping any that don't decode.
    private func load<Item: Transferable & Sendable>(_ item: Item.Type, from providers: [NSItemProvider], type: UTType) async -> [Item] {
        var items: [Item] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let loaded: Item? = await withCheckedContinuation { continuation in
                _ = provider.loadTransferable(type: Item.self) { continuation.resume(returning: try? $0.get()) }
            }
            if let loaded { items.append(loaded) }
        }
        return items
    }
}

/// The same drop actions serve SwiftUI sidebar targets and the AppKit collection.
struct LibraryDrop {
    enum Target {
        case item(SidebarItem)
        case topLevel
    }

    let target: Target
    let store: LibraryStore
    let prompts: ActionPrompts

    func bookmarks(_ ids: [Raindrop.ID]) async {
        guard case .item(let item) = target, store.canModify(ids) else { return }
        switch item {
        case .collection(let id):
            await store.attempt("Couldn't Move Bookmarks") { try await store.move(ids, to: id) }
        case .unsorted:
            await store.attempt("Couldn't Move Bookmarks") { try await store.move(ids, to: SystemCollectionID.unsorted) }
        case .important:
            await store.attempt("Couldn't Add to Favorites") { try await store.setImportant(ids, true) }
        case .trash:
            prompts.delete(ids.compactMap(store.raindrop(id:)), in: store)
        case .tag(let tag):
            await store.attempt("Couldn't Add Tag") { try await store.addTags([tag], to: ids) }
        case .all:
            break
        }
    }

    func collection(_ id: RaindropCollection.ID) async {
        guard store.canWrite else { return }
        switch target {
        case .item(.collection(let parent)):
            await store.attempt("Couldn't Move Collection") { try await store.moveCollection(id, into: parent) }
        case .topLevel:
            await store.attempt("Couldn't Move Collection") { try await store.moveCollection(id, into: nil) }
        case .item:
            break
        }
    }

}
