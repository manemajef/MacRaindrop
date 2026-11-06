import SwiftUI

/// The "Collections" heading and the collection chips under it, packed from the left. Collapsed,
/// only the first row shows.
struct CollectionSection: View {
    let collections: [RaindropCollection]
    @Binding var selection: RaindropCollection.ID?
    let open: (RaindropCollection.ID) -> Void
    /// Selecting a collection clears the bookmark selection.
    let didSelect: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @AppStorage("gridShowsAllFolders") private var showsAll = false
    /// The collection a drag is over.
    @State private var dropTarget: RaindropCollection.ID?
    @State private var fullHeight: CGFloat = 0
    @State private var rowHeight: CGFloat = 0

    private var overflows: Bool { fullHeight > rowHeight + 1 }

    var body: some View {
        SectionHeader(title: "Collections", count: collections.count)
            .frame(height: GridMetrics.headerHeight)
            .overlay(alignment: .bottomTrailing) {
                if overflows {
                    Button(showsAll ? "Show Less" : "Show All") {
                        withAnimation { showsAll.toggle() }
                    }
                    .buttonStyle(.link)
                    .padding(.trailing, GridMetrics.inset)
                    .padding(.bottom, 6)
                }
            }

        FlowLayout(spacing: GridMetrics.columnSpacing) {
            ForEach(collections) { collection in
                chip(collection)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        .frame(height: showsAll || !overflows ? nil : rowHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, GridMetrics.inset)
        .padding(.top, 4)
    }

    private func chip(_ collection: RaindropCollection) -> some View {
        CollectionTile(collection: collection, isSelected: selection == collection.id, isDropTarget: dropTarget == collection.id)
            .frame(maxWidth: CollectionTile.maxWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2 { return open(collection.id) }
                selection = collection.id
                didSelect()
            }
            .contextMenu {
                Button("Open", systemImage: "folder") { open(collection.id) }
            }
            .draggable(CollectionDrag(id: collection.id))
            .overlay {
                CollectionDropZone(collection: collection.id, canWrite: store.canWrite) { isOver in
                    if isOver { dropTarget = collection.id } else if dropTarget == collection.id { dropTarget = nil }
                } drop: { bookmarks, collections in
                    let action = LibraryDrop(target: .item(.collection(collection.id)), store: store, prompts: prompts)
                    Task {
                        if !bookmarks.isEmpty { await action.bookmarks(bookmarks) }
                        for id in collections { await action.collection(id) }
                    }
                }
            }
    }
}
