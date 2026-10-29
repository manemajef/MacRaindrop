import SwiftUI

/// SwiftUI owns the content and actions; AppKit owns collection layout and selection.
struct RaindropGridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
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
            open: { openURL($0) }
        )
        // Under the toolbar, so cards scroll up behind it. The scroll view's content insets
        // keep the first row clear of it.
        .ignoresSafeArea(edges: .top)
    }
}

#Preview {
    @Previewable @State var selection: Set<Raindrop.ID> = []
    let store = LibraryStore.preview
    RaindropGridView(raindrops: store.raindrops(in: .all), selection: $selection)
        .frame(width: 800, height: 600)
        .environment(store)
        .environment(ActionPrompts())
}
