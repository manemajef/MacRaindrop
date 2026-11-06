import SwiftUI

// The sidebar's previews live apart from `SidebarView.swift` on purpose. The canvas recompiles
// the previewed file in its own mode, and a `List` with sections built in that mode trips a
// SwiftUI assertion (`ViewListTree.visitItem`) that crashes the preview. The same list built
// from an ordinary compile, as here, previews fine.

#Preview("Sidebar") {
    @Previewable @State var navigation = NavigationModel()
    NavigationSplitView {
        SidebarView(navigation: navigation)
    } detail: {
        Text("Detail")
    }
    // A real window size, so the split view doesn't squeeze the sidebar to fit its content.
    .frame(width: 700, height: 400)
    .previewEnvironment()
}

#Preview("Collections Open, One Selected") {
    OpenCollectionsPreview()
        .frame(width: 700, height: 640)
}

/// Every collection with subcollections open, and the most deeply nested one selected.
/// Set up before the first frame: opening them in `onAppear` leaves the canvas blank.
private struct OpenCollectionsPreview: View {
    @State private var store: LibraryStore
    @State private var navigation: NavigationModel

    init() {
        let store = LibraryStore.preview
        let navigation = NavigationModel()
        navigation.expandedCollections = Set(store.collections.compactMap(\.parentID))
        if let deepest = store.collections.max(by: { store.ancestors(of: $0.id).count < store.ancestors(of: $1.id).count }) {
            navigation.go(to: .collection(deepest.id))
        }
        _store = State(initialValue: store)
        _navigation = State(initialValue: navigation)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(navigation: navigation)
        } detail: {
            Text("Detail")
        }
        .previewEnvironment(store)
    }
}
