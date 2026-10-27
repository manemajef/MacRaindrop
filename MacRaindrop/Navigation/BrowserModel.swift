import Observation

/// One window's place in the library: what it shows, how it got there, and what's selected.
@Observable
final class BrowserModel {
    /// The sidebar item or collection on screen.
    private(set) var location: SidebarItem? = .all
    private var backStack: [SidebarItem] = []
    private var forwardStack: [SidebarItem] = []
    var selection: Set<Raindrop.ID> = []
    var searchText = ""
    /// Collections open in the sidebar. Kept here rather than in the sidebar, so switching
    /// between list and cards (which rebuilds the sidebar) doesn't collapse them.
    var expandedCollections: Set<RaindropCollection.ID> = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Shows `item`, remembering the current location so Back returns to it.
    func go(to item: SidebarItem?) {
        guard item != location else { return }
        if let location { backStack.append(location) }
        forwardStack.removeAll()
        show(item)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let location { forwardStack.append(location) }
        show(previous)
    }

    /// The collection containing the current one, for Go › Enclosing Folder.
    func enclosingCollection(in store: LibraryStore) -> RaindropCollection.ID? {
        guard case .collection(let id) = location else { return nil }
        return store.collection(id: id)?.parentID
    }

    /// Opens the parents of the current collection in the sidebar, so its row is visible.
    func revealLocation(in store: LibraryStore) {
        guard case .collection(let id) = location else { return }
        expandedCollections.formUnion(store.ancestors(of: id))
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let location { backStack.append(location) }
        show(next)
    }

    /// A new location starts with nothing selected and no search.
    private func show(_ item: SidebarItem?) {
        location = item
        selection = []
        searchText = ""
    }
}
