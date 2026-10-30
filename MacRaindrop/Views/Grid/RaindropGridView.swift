import SwiftUI

/// SwiftUI owns the content and actions; AppKit owns collection layout and selection.
struct RaindropGridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    @AppStorage(CardSpacing.storageKey) private var cardSpacing: CardSpacing = .stretch
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>
    var folders: [RaindropCollection] = []
    var openFolder: (RaindropCollection.ID) -> Void = { _ in }

    var body: some View {
        GridCollectionView(
            raindrops: raindrops,
            folders: folders,
            selection: $selection,
            store: store,
            prompts: prompts,
            openFolder: openFolder,
            open: { openURL($0) },
            cardSpacing: cardSpacing
        )
        // Under the toolbar, so cards scroll up behind it. The scroll view's content insets
        // keep the first row clear of it.
        .ignoresSafeArea(edges: .top)
    }
}

#Preview {
    @Previewable @State var store = LibraryStore.preview
    @Previewable @State var selection: Set<Raindrop.ID> = []
    RaindropGridView(raindrops: store.raindrops(in: .all), selection: $selection)
        .frame(width: 800, height: 600)
        .environment(store)
        .environment(ActionPrompts())
}

#Preview("With Folders") {
    @Previewable @State var store = LibraryStore.preview
    @Previewable @State var selection: Set<Raindrop.ID> = []
    // The collection with subcollections holding the most bookmarks, as cards mode shows it:
    // folders first, then bookmarks.
    let parent = store.collections
        .filter { !store.subcollections(of: $0.id).isEmpty }
        .max { store.count(for: .collection($0.id)) < store.count(for: .collection($1.id)) }!
    RaindropGridView(
        raindrops: store.raindrops(in: .collection(parent.id)),
        selection: $selection,
        folders: store.subcollections(of: parent.id)
    )
    .frame(width: 800, height: 600)
    .environment(store)
    .environment(ActionPrompts())
}
