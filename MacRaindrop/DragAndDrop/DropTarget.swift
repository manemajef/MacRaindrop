import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Lets a sidebar row or collection chip take dropped bookmarks, and collections take
    /// dropped collections:
    ///
    /// - a collection: bookmarks move into it, collections nest inside it
    /// - Unsorted: bookmarks move there
    /// - Favorites: bookmarks become favorites
    /// - Trash: bookmarks are deleted (asking first for any already in the Trash)
    /// - a tag: bookmarks get that tag
    ///
    /// `highlights` draws a tint while something is dragged over it. Sidebar rows turn it off:
    /// the outline view under the `List` draws its own, and the tint, which only clears when its
    /// row hears the drag leave, could stay on after a drag the outline view ended.
    func dropTarget(for item: SidebarItem, highlights: Bool = true) -> some View {
        modifier(DropTarget(target: .item(item), highlights: highlights))
    }

    /// Lets the Collections heading take dropped collections, moving them to the top level.
    func topLevelCollectionsDropTarget() -> some View {
        modifier(DropTarget(target: .topLevel, highlights: true))
    }
}

private struct DropTarget: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    let target: LibraryDrop.Target
    let highlights: Bool
    @State private var isTargeted = false

    private var acceptedTypes: [UTType] {
        switch target {
        case .item(.collection): [.raindropBookmark, .raindropCollection]
        case .item(.all), .item(.filter): []
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
                if highlights, isTargeted {
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
