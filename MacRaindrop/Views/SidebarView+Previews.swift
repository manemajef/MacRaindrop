import SwiftUI

// The sidebar's previews live apart from `SidebarView.swift` on purpose. The canvas recompiles
// the previewed file in its own mode, and a `List` with sections built in that mode trips a
// SwiftUI assertion (`ViewListTree.visitItem`) that crashes the preview. The same list built
// from an ordinary compile, as here, previews fine.

#Preview("Sidebar") {
    @Previewable @State var browser = BrowserModel()
    NavigationSplitView {
        SidebarView(browser: browser)
    } detail: {
        Text("Detail")
    }
    // A real window size, so the split view doesn't squeeze the sidebar to fit its content.
    .frame(width: 700, height: 400)
    .environment(LibraryStore.preview)
    .environment(ActionPrompts())
}

#Preview("Collections Open, One Selected") {
    OpenCollectionsPreview()
        .frame(width: 700, height: 640)
}

/// Every collection with subcollections open, and the most deeply nested one selected.
/// Set up before the first frame: opening them in `onAppear` leaves the canvas blank.
private struct OpenCollectionsPreview: View {
    @State private var store: LibraryStore
    @State private var browser: BrowserModel

    init() {
        let store = LibraryStore.preview
        let browser = BrowserModel()
        browser.expandedCollections = Set(store.collections.compactMap(\.parentID))
        if let deepest = store.collections.max(by: { store.ancestors(of: $0.id).count < store.ancestors(of: $1.id).count }) {
            browser.go(to: .collection(deepest.id))
        }
        _store = State(initialValue: store)
        _browser = State(initialValue: browser)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(browser: browser)
        } detail: {
            Text("Detail")
        }
        .environment(store)
        .environment(ActionPrompts())
    }
}
