import SwiftUI

struct ListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>
    /// Whether rows say which collection they're in. See `SidebarItem.showsCollectionLabel`.
    var showsCollectionLabel = true

    private var selected: [Raindrop] { raindrops.filter { selection.contains($0.id) } }

    var body: some View {
        List(raindrops, selection: $selection) { raindrop in
            RaindropRow(raindrop: raindrop, isPending: store.pendingIDs.contains(raindrop.id),
                        collectionTitle: showsCollectionLabel ? store.collectionTitle(for: raindrop.collectionID) : nil)
                .draggable(containerItemID: raindrop.id)
        }
        .contextMenu(forSelectionType: Raindrop.ID.self) { ids in
            RaindropActions(raindrops: ids.compactMap(store.raindrop(id:)))
        } primaryAction: { ids in
            // Double-click (or Return) opens the page in the default browser.
            for url in ids.compactMap({ store.raindrop(id: $0)?.url }) {
                openURL(url)
            }
        }
        .raindropDragContainer(selection: selection)
        .copyable(selected.compactMap(\.url))
        .onDeleteCommand { prompts.delete(selected, in: store) }
    }
}

#Preview {
    @Previewable @State var selection: Set<Raindrop.ID> = []
    let store = LibraryStore.preview
    ListView(raindrops: store.raindrops(in: .all), selection: $selection)
        .previewEnvironment(store)
}
