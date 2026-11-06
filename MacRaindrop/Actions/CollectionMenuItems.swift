import SwiftUI

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
