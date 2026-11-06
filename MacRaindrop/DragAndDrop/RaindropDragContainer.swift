import SwiftUI

extension View {
    /// Lets the raindrops inside drag out as URLs, all of the selection at once when a selected one is dragged.
    func raindropDragContainer(selection: Set<Raindrop.ID>) -> some View {
        modifier(RaindropDragContainer(selection: selection))
    }
}

private struct RaindropDragContainer: ViewModifier {
    @Environment(LibraryStore.self) private var store
    let selection: Set<Raindrop.ID>

    func body(content: Content) -> some View {
        content
            .dragContainer(for: RaindropLink.self) { ids in
                ids.compactMap { id in
                    store.raindrop(id: id)?.url.map { RaindropLink(id: id, url: $0) }
                }
            }
            .dragContainerSelection(Array(selection))
    }
}
